# Phase 2 — Capture Controller, RAM và Board Readback

## Trạng thái

Hoàn thành trong phạm vi:
- Capture 1 kênh × 256 mẫu sau trigger.
- Sử dụng nguồn dữ liệu thử nội bộ.
- Kiểm thử controller, RAM và khối tích hợp bằng Questa.
- Kiểm thử ARM, trigger, capture và đọc dữ liệu trên DE10-Lite.

Chưa bao gồm capture tín hiệu dữ liệu từ GPIO bên ngoài.

## 1. Mục tiêu

Mở rộng Phase 1 từ việc nhận trigger sang quá trình capture thực tế:

ARM → chờ trigger → ghi 256 mẫu vào RAM → DONE → đọc lại dữ liệu.

Phase 1 được giữ lại trong `debug_probe_phase1_top.sv`.
Phase 2 sử dụng top-level mới: `debug_probe_phase2_top`.

## 2. Thông số thiết kế

| Thuộc tính | Giá trị |
|---|---|
| Board | DE10-Lite |
| Clock hệ thống | 50 MHz |
| Số kênh dữ liệu | 1 bit |
| Số mẫu mỗi phiên | 256 |
| Địa chỉ RAM | 0–255 (`00`–`FF`) |
| Sample enable trên board | 1 kHz, một mẫu mỗi 1 ms |
| Thời gian capture | Khoảng 256 ms |
| Chế độ capture | Sau trigger, không có pre-trigger |
| Nguồn dữ liệu hiện tại | Bộ tạo mẫu nội bộ `pattern_lfsr` |
| Cách đọc dữ liệu | KEY1 chọn địa chỉ, HEX hiển thị địa chỉ, LEDR1 hiển thị bit |

Toàn bộ logic hoạt động theo clock 50 MHz.
`sample_tick` là clock enable, không phải một clock riêng.

## 3. Kiến trúc

```text
KEY1 → Synchronizer → Debounce → Edge detector → ARM
                                                   │
ROW_0 → Normalize → Synchronizer → Edge detector → Trigger
                                                   │
                                                   ▼
                                           capture_controller
                                            │            │
                                        sample_we    write_addr
                                            │            │
                                            ▼            ▼
pattern_lfsr ─────── sample_data ───────────► capture_ram
                                                │
KEY1 trong DONE ───► read_addr ───────────────────┤
                                                ▼
                                             read_data
                                                │
                                              LEDR1
```

`capture_core` ghép `capture_controller` với `capture_ram`.

## 4. Capture controller

Controller có bốn trạng thái:

| Mã | Trạng thái | Hành vi |
|---|---|---|
| 0 | IDLE | Chờ ARM, bỏ qua trigger |
| 1 | ARMED | Chờ trigger |
| 2 | CAPTURING | Ghi mẫu khi `sample_tick = 1` |
| 3 | DONE | Chặn ghi thêm, giữ kết quả đến reset |

Quy tắc lấy mẫu:

- Tick trùng cạnh nhận trigger không được tính là mẫu.
- Trong CAPTURING, mỗi cạnh clock có `sample_we = 1` ghi một mẫu.
- Địa chỉ ghi tăng tuần tự từ 0 đến 255.
- Lần ghi thứ 256 sử dụng địa chỉ 255.
- Sau lần ghi cuối, `samples_written = 256` và controller vào DONE.
- Muốn bắt đầu phiên capture mới phải reset.

## 5. RAM

RAM có dung lượng 256 × 1 bit:

- Ghi đồng bộ theo cạnh lên clock.
- Đọc đồng bộ theo cạnh lên clock.
- Có địa chỉ đọc và địa chỉ ghi riêng.
- Không xóa toàn bộ RAM khi reset.

Reset đưa controller và địa chỉ đọc về trạng thái khởi đầu.
Dữ liệu RAM chỉ được xem là kết quả capture hợp lệ sau khi phiên mới hoàn tất.

Việc mô tả RAM bằng RTL chưa xác nhận nó được triển khai bằng
block RAM chuyên dụng hay logic. Cần xem báo cáo synthesis/fitter
để chốt tài nguyên thực tế.

## 6. Nguồn dữ liệu thử nội bộ

`pattern_lfsr` là thanh ghi 8 bit, khởi tạo bằng `8'hA5`.

Mỗi lần ghi, RAM lấy bit thấp nhất:

```systemverilog
assign sample_data = pattern_lfsr;
```

Thanh ghi chỉ chuyển sang giá trị tiếp theo khi `sample_we = 1`:

```systemverilog
pattern_lfsr <= {
    pattern_lfsr[6:0],
    pattern_lfsr ^[1]
    pattern_lfsr ^
    pattern_lfsr ^
    pattern_lfsr
};
```

Nguồn thử có tính xác định: sau mỗi reset, nó tạo lại cùng chuỗi bit.

16 mẫu đầu kỳ vọng:

```text
Địa chỉ: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
Dữ liệu:  1  0  1  0  0  1  1  1  0  1  1  1  0  1  1  0
```

Lưu ý: giá trị đúng tại địa chỉ `07` là `1`.

## 7. Điều khiển và hiển thị trên board

### Điều khiển

| Thành phần | Chức năng |
|---|---|
| KEY0 | Reset active-low |
| KEY1 trong IDLE | ARM |
| Keypad qua ROW_0 trong ARMED | Trigger |
| KEY1 trong DONE | Tăng địa chỉ đọc RAM |

Trigger được chuẩn hóa bằng:

```systemverilog
assign trigger_in = ~ROW_0;
```

Cấu hình đã dùng từ Phase 1:

- `ROW_0`: `PIN_AB3`.
- Weak Pull-Up bật.
- Cột keypad được giữ thấp để khi nhấn phím, ROW_0 bị kéo xuống.

### Hiển thị trước DONE

| Thành phần | Nội dung |
|---|---|
| HEX0 | State: IDLE=0, ARMED=1, CAPTURING=2 |
| HEX1 | Chữ số thấp của bộ đếm nhấn KEY1 |
| LEDR0 | Heartbeat |
| LEDR1 | Trạng thái KEY1 đã debounce |

### Hiển thị sau DONE

| Thành phần | Nội dung |
|---|---|
| HEX0 | Nibble cao của địa chỉ đọc |
| HEX1 | Nibble thấp của địa chỉ đọc |
| LEDR0 | Heartbeat |
| LEDR1 | Bit đọc từ RAM |

Đọc địa chỉ theo thứ tự HEX0 rồi HEX1, không suy ra thứ tự
từ vị trí trái/phải của hai màn hình trên board.

Khi DONE, `00` là địa chỉ đọc RAM, không phải thông báo trở về IDLE.

## 8. Kiểm thử mô phỏng

### Controller — `tb_capture_controller`

Đã PASS:
- Reset.
- Trigger trong IDLE bị bỏ qua.
- ARMED chờ trigger.
- Cạnh nhận trigger chưa ghi mẫu.
- Đúng 256 lần ghi, địa chỉ 0–255.
- DONE chặn ghi thêm.
- Reset sau DONE.

Kết quả:

```text
ALL TESTS PASSED
```

### RAM — `tb_capture_ram`

Đã PASS:
- Ghi và đọc lại toàn bộ 256 địa chỉ.
- `wr_en = 0` giữ nguyên dữ liệu.
- Ghi đè bằng mẫu khác và đọc lại đúng.

Kết quả:

```text
ALL RAM TESTS PASSED
```

### Tích hợp — `tb_capture_core`

Đã PASS:
- IDLE và ARMED không ghi dữ liệu.
- Tick trùng cạnh trigger không được tính là mẫu.
- Không ghi trong khoảng không có sample tick.
- Đúng 256 lần ghi với địa chỉ tuần tự.
- Đọc lại đủ 256 ô và so sánh với dữ liệu tại cạnh lấy mẫu.
- DONE giữ nguyên dữ liệu.
- Reset và capture lần hai với mẫu dữ liệu đảo.

Kết quả:

```text
ALL CAPTURE CORE TESTS PASSED
```

## 9. Kiểm thử trên DE10-Lite

Đã kiểm tra theo kịch bản board:
- Reset về IDLE.
- Trigger trong IDLE bị bỏ qua.
- KEY1 đưa hệ thống sang ARMED.
- ARMED giữ trạng thái khi chưa có trigger.
- Nhấn KEY1 thêm khi ARMED không tự trigger.
- Keypad kích hoạt capture.
- Capture hoàn tất và chuyển sang chế độ đọc RAM.
- Đọc địa chỉ `00`–`0F` khớp chuỗi dữ liệu kỳ vọng.
- DONE bỏ qua trigger tiếp theo và giữ dữ liệu.
- Địa chỉ đọc chuyển đúng qua `0F → 10`.
- Reset rồi capture lại cho chuỗi dữ liệu đầu giống phiên trước.

Phạm vi kiểm chứng:
- Đủ 256 ô được so sánh tự động trong mô phỏng.
- Trên board mới đối chiếu các địa chỉ theo kịch bản,
  chưa kiểm tra thủ công toàn bộ 256 ô.

## 10. Build và chạy

1. Mở project Quartus.
2. Chọn top-level `debug_probe_phase2_top`.
3. Kiểm tra đường dẫn source file, đặc biệt các module trong `rtl/`.
4. Giữ pin assignment đã dùng ở Phase 1.
5. Chạy Full Compilation.
6. Nạp file `.sof` vừa tạo bằng Quartus Programmer.
7. Reset → ARM → trigger → đọc dữ liệu.

Không đưa file `tb_*.sv` vào danh sách source tổng hợp phần cứng.
Testbench được cấu hình riêng cho mô phỏng.

Nếu NativeLink đang bật tự chạy gate-level simulation sau compilation,
cần tắt khi không sử dụng hoặc bảo đảm cấu hình simulation hợp lệ.

Khi di chuyển source file, phải kiểm tra cả:
- Danh sách file của project Quartus.
- Danh sách file testbench/simulation hoặc script mô phỏng.

## 11. Giới hạn hiện tại

- Chưa capture dữ liệu từ GPIO ngoài.
- Chưa có pre-trigger.
- Chưa có streaming hoặc xuất dữ liệu qua UART/USB.
- Chưa đối chiếu thủ công đủ 256 ô trên board.
- Chưa chốt loại tài nguyên RAM từ báo cáo tổng hợp.

## 12. Hướng tiếp theo

Phase 3 dự kiến:
- Thay nguồn dữ liệu thử nội bộ bằng đầu vào dữ liệu ngoài.
- Giữ baseline capture controller và RAM đã kiểm thử.
- Bắt đầu với một kênh, 256 mẫu và trigger riêng.