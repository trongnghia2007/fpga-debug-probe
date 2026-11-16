# Phase 1 — Điều khiển ARM và nhận trigger

## Trạng thái và phạm vi

Phase 1 là nguyên mẫu điều khiển và nhận trigger viết bằng SystemVerilog, đã được kiểm thử trên board Terasic DE10-Lite.

Mục tiêu của giai đoạn này:

```text
Nhận lệnh ARM → chờ trigger ngoài → giữ trạng thái DONE đến khi reset
```

**Phạm vi của Phase 1:** chỉ có đường điều khiển và phát hiện trigger. Top-level Phase 1 không tích hợp RAM thu mẫu và không xuất dữ liệu dạng sóng.

> Đây là tài liệu cho baseline Phase 1, không phải mô tả toàn bộ phiên bản mới nhất của dự án. Phase 2 đã được triển khai riêng với controller, RAM và chức năng đọc lại dữ liệu. Không dùng mã trạng thái hoặc ý nghĩa hiển thị của Phase 2 để diễn giải Phase 1.

## 1. Phần cứng và công cụ

- Board Terasic DE10-Lite.
- Clock đầu vào 50 MHz: `MAX10_CLK1_50`.
- KEY0: reset active-low.
- KEY1: nút ARM active-low.
- Keypad ma trận 4 × 4: nguồn trigger thủ công qua `ROW_0`.
- HEX0, HEX1, LEDR0 và LEDR1: hiển thị chẩn đoán.
- Quartus Prime: tổng hợp, triển khai và nạp thiết kế.

Top-level của baseline này là:

```text
debug_probe_phase1_top
```

## 2. Kiến trúc

```text
KEY1 (active-low)
    │
    ▼
Đảo mức → Đồng bộ 2 FF → Debounce → Phát hiện cạnh lên
                                      │
                                  press_pulse
                                      │
                       ┌──────────────┴──────────────┐
                       ▼                             ▼
                 Bộ đếm lần nhấn                  ARM event
                       │                             │
                       ▼                             ▼
                     HEX1                       capture_fsm → HEX0
                                                     ▲
                                                     │
ROW_0 → Đảo mức → Đồng bộ 2 FF → Phát hiện cạnh lên → Trigger event

KEY0                     → Reset
Clock 50 MHz             → Bộ đếm heartbeat → LEDR0
Mức KEY1 sau debounce    → LEDR1
```

Các khối tuần tự trong bản tích hợp dùng chung `MAX10_CLK1_50`. Khối debounce sử dụng tick cho phép dài một chu kỳ clock, được tạo mỗi 1 ms; tick này không phải một clock riêng.

## 3. Máy trạng thái

| Trạng thái | Mã | Chức năng |
|---|---|---|
| IDLE | `0` | Chờ sự kiện nhấn KEY1 để ARM |
| ARMED | `1` | Chờ sự kiện trigger từ bên ngoài |
| DONE | `2` | Giữ trạng thái đã nhận trigger cho đến khi reset |

```text
IDLE ── nhấn KEY1 ──► ARMED ── trigger ngoài ──► DONE
 ▲                                               │
 └──────────────── KEY0 reset ────────────────────┘
```

KEY0 cũng reset hệ thống khi đang ở IDLE hoặc ARMED.

### Ý nghĩa của DONE

Trong Phase 1, DONE chỉ có nghĩa là controller đã nhận trigger hợp lệ. Nó không có nghĩa là một quá trình thu dữ liệu đã hoàn tất, vì Phase 1 chưa có bộ nhớ thu mẫu.

Module `capture_fsm` có cổng `clear_pulse`, nhưng top-level hiện nối cố định:

```systemverilog
.clear_pulse (1'b0)
```

Đường lệnh clear riêng không được kiểm thử trong baseline này. Cách đưa hệ thống về IDLE trên board là nhấn KEY0.

### Định tuyến sự kiện

```systemverilog
assign arm_event = press_pulse && (capture_state == 2'd0);
assign trigger_event = trigger_rise_pulse && (capture_state == 2'd1);
```

- KEY1 chỉ tạo lệnh ARM khi controller đang IDLE.
- Các lần nhấn KEY1 tiếp theo vẫn tăng bộ đếm chẩn đoán.
- Trong bản dùng trigger ngoài, KEY1 không được nối làm nguồn trigger.
- Trigger ngoài chỉ được chuyển đến FSM khi đang ARMED.
- DONE được giữ đến reset; không tự bắt đầu phiên mới.

## 4. Đầu vào trigger ngoài

Top-level nhận tín hiệu keypad active-low:

```systemverilog
input logic ROW_0;

assign trigger_in = ~ROW_0;
```

Khi nhấn đúng phím trong cấu hình thử, `ROW_0` bị kéo từ HIGH xuống LOW. Phép đảo tạo một cạnh lên trên `trigger_in`, sau đó tín hiệu đi qua bộ đồng bộ và bộ phát hiện cạnh.

Trigger được nhận sau các bước xử lý đồng bộ, không phải tức thời tại thời điểm mức điện áp ở chân vật lý đổi.

### Pin assignment đã kiểm thử

| Tín hiệu | Chân FPGA | Cấu hình |
|---|---|---|
| `ROW_0` | `PIN_AB3` | Input, bật Weak Pull-Up |

Đây là cấu hình đã được báo cáo chạy đúng trong quá trình kiểm thử. Xem file `.qsf` của project để biết đầy đủ assignment; không xem bảng một chân này là toàn bộ sơ đồ nối dây.

### Yêu cầu nối keypad

Phím của keypad thụ động chỉ nối một hàng với một cột khi được nhấn; bản thân phím không tự tạo mức LOW.

Để dùng làm trigger:

1. Hàng được chọn phải nối tới `ROW_0`.
2. Cột tương ứng phải được giữ LOW trong bộ gá thử.
3. Khi nhấn phím, hàng được kéo xuống LOW qua cột đó.

Top-level Phase 1 chỉ có đầu vào `ROW_0`, không có cổng điều khiển cột hoặc bộ quét keypad. Vì vậy, cách giữ cột LOW là một phần của cấu hình phần cứng thử nghiệm và cần được giữ nguyên khi tái lập kết quả.

Không mặc định mọi phím trên keypad đều tạo trigger. Không nối trực tiếp một cột xuống GND nếu đường đó đang được thiết bị khác hoặc chân FPGA điều khiển HIGH.

## 5. Hiển thị chẩn đoán

| Đầu ra | Ý nghĩa trong Phase 1 |
|---|---|
| HEX0 | State: `0` = IDLE, `1` = ARMED, `2` = DONE |
| HEX1 | Chữ số hexadecimal thấp của bộ đếm nhấn KEY1 |
| LEDR0 | Heartbeat lấy từ `count[25]` |
| LEDR1 | Mức KEY1 sau debounce; sáng khi giữ nút |

Bộ đếm `press_count` rộng 8 bit, nhưng HEX1 chỉ hiển thị `press_count[3:0]`. Chữ số hiển thị quay về `0` sau `F`.

Trigger keypad không tăng bộ đếm KEY1. LEDR1 không phải đèn báo ARMED hoặc DONE và không hiển thị dữ liệu RAM trong Phase 1.

## 6. Các module RTL

| Module | Vai trò |
|---|---|
| `debug_probe_phase1_top` | Ghép các khối, định tuyến sự kiện và hiển thị |
| `sync_2ff` | Đồng bộ đầu vào bất đồng bộ qua hai tầng FF |
| `clock_enable` | Tạo tick 1 ms |
| `debounce` | Lọc mức KEY1 đã đồng bộ, cấu hình `STABLE_TICKS = 10` |
| `edge_detect` | Tạo xung đã đăng ký khi phát hiện cạnh lên |
| `capture_fsm` | Thực hiện IDLE, ARMED và DONE |
| `hex_to_7seg` | Giải mã chữ số ra LED bảy đoạn |

## 7. Build và nạp baseline Phase 1

1. Mở project trong Quartus Prime.
2. Chọn `debug_probe_phase1_top` làm Top-Level Entity.
3. Kiểm tra tất cả source file cần thiết đã được thêm vào project với đúng đường dẫn.
4. Kiểm tra pin assignment trong `.qsf` và Pin Planner so với cách nối thực tế.
5. Xác nhận Weak Pull-Up của `ROW_0` vẫn bật.
6. Kiểm tra ràng buộc timing cho clock 50 MHz; tài liệu này không thay thế báo cáo timing.
7. Chạy Full Compilation và xem các warning, đặc biệt về assignment bị bỏ qua, tín hiệu không được điều khiển và ràng buộc timing còn thiếu.
8. Nạp file `.sof` vừa tạo bằng Quartus Programmer.
9. Thực hiện kịch bản kiểm thử bên dưới.

Compile thành công không đồng nghĩa thiết kế đã được xác nhận hoạt động trên phần cứng.

Nếu project hiện đang chọn top Phase 2, cần đổi lại top và compile trước khi nạp để kiểm thử baseline Phase 1. Tên project hoặc tên file đầu ra cũ không đủ để xác định top nào đang được dùng.

## 8. Kết quả kiểm thử trên board

### 8.1. Baseline ban đầu: KEY1 dùng cho cả ARM và trigger thử

Trước khi tích hợp trigger ngoài, một phiên bản trước dùng KEY1 để thử cả hai bước điều khiển. Các hành vi đã được báo cáo chạy đúng:

- Lần nhấn đầu: IDLE → ARMED.
- Giữ KEY1: không tự tăng bộ đếm nhiều lần và không tự chuyển trạng thái.
- Lần nhấn riêng biệt thứ hai: ARMED → DONE.
- Nhấn thêm trong DONE: giữ DONE, bộ đếm vẫn tăng.
- KEY0 reset state và bộ đếm.

Đây là kết quả lịch sử của baseline cũ, không phải cách định tuyến sự kiện trong top dùng trigger ngoài.

### 8.2. Bản tích hợp trigger ngoài

Chuỗi sau đã được xác nhận trên board:

| Bước | Thao tác | HEX0: state | HEX1: bộ đếm KEY1 |
|---|---|---|---|
| 1 | Nhấn rồi thả KEY0 | `0` | `0` |
| 2 | Nhấn rồi thả KEY1 một lần | `1` | `1` |
| 3 | Chờ, không nhấn keypad | Giữ `1` | Giữ `1` |
| 4 | Nhấn đúng phím keypad nối với đường trigger | `2` | Giữ `1` |
| 5 | Giữ rồi thả phím keypad | Giữ `2` | Giữ `1` |
| 6 | Nhấn keypad thêm lần nữa | Giữ `2` | Giữ `1` |
| 7 | Nhấn KEY0 | `0` | `0` |

Kết luận: đường điều khiển với trigger ngoài PASS trong phạm vi chuỗi kiểm thử này.

### 8.3. Regression: nhấn KEY1 thêm khi ARMED

Kịch bản cần dùng để phân biệt bản trigger ngoài với baseline KEY1-trigger cũ:

1. Reset.
2. Nhấn KEY1 để ARM.
3. Thả rồi nhấn KEY1 lần nữa, không tác động keypad.
4. Xác nhận HEX0 giữ `1`, HEX1 tăng lên `2`.
5. Nhấn keypad; xác nhận HEX0 sang `2`, HEX1 giữ `2`.

Tại thời điểm chốt Phase 1, chưa có báo cáo riêng xác nhận kịch bản này sau khi đổi sang trigger ngoài.

Trong quá trình kiểm thử Phase 2 sau đó, hành vi tương ứng — KEY1 bổ sung khi ARMED không tự trigger — đã được báo cáo PASS. Kết quả đó thuộc top Phase 2; không coi là một lần chạy lại trên top Phase 1.

## 9. Giới hạn và các mục chưa xác nhận

- DONE chỉ báo đã nhận trigger, không báo đã thu xong dữ liệu.
- Không có capture RAM, buffer mẫu hoặc xuất waveform trong top Phase 1.
- Chưa có thu dữ liệu nhiều kênh.
- Keypad được đồng bộ và phát hiện cạnh nhưng chưa debounce đường trigger.
- DONE giữ trạng thái có thể che các xung phát sinh thêm do dội phím; kiểm thử này không chứng minh mỗi lần nhấn keypad chỉ tạo một xung.
- Thiết kế không phải bộ giải mã keypad và không nhận dạng từng phím.
- Trigger ngoài ARMED không được xếp hàng để xử lý về sau.
- Chưa xác nhận khả năng nhận các xung rất ngắn, tần số trigger tối đa hoặc độ rộng xung tối thiểu.
- Kịch bản chuẩn bắt đầu với phím trigger được thả. Giữ trigger khi reset hoặc khi ARM chưa nằm trong chuỗi kiểm thử đã xác nhận.
- Đường clear riêng, cải tiến đồng bộ nhả reset và sign-off timing/CDC đầy đủ nằm ngoài phạm vi kiểm chứng của Phase 1.

## 10. Chuyển tiếp sang Phase 2

Phase 1 được giữ làm baseline cho đường xử lý nút bấm và trigger ngoài.

Phase 2 đã bổ sung:

- Controller riêng với trạng thái CAPTURING.
- Bộ đếm mẫu và địa chỉ ghi.
- RAM 1 bit × 256 mẫu.
- Điều kiện hoàn tất sau 256 lần ghi.
- Nguồn dữ liệu thử nội bộ và chức năng đọc lại trên board.

Khác biệt cốt lõi:

```text
Phase 1: DONE = đã nhận trigger.
Phase 2: DONE = đã hoàn tất ghi 256 mẫu sau trigger.
```

Mã DONE cũng khác nhau: Phase 1 dùng `2`, Phase 2 dùng `3`. Trong top Phase 2, khi DONE, hai HEX chuyển sang hiển thị địa chỉ RAM thay vì tiếp tục hiển thị state.

Xem [tài liệu Phase 2](phase2.md) nếu hai file được đặt cùng thư mục `docs/`.
