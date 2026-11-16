# FPGA Debug Probe

Dự án mini logic analyzer viết bằng SystemVerilog trên board Terasic DE10-Lite, phát triển theo từng giai đoạn từ điều khiển trigger đến thu và đọc lại dữ liệu.

## Phần cứng và công cụ

- Terasic DE10-Lite, clock 50 MHz.
- Quartus Prime Lite 24.1.
- Questa Intel Starter FPGA Edition.
- Keypad ngoài làm nguồn trigger thủ công.
- KEY, HEX và LED trên board để điều khiển và kiểm tra.

## Tiến độ

| Giai đoạn | Nội dung | Trạng thái |
|---|---|---|
| Phase 1 | ARM, chờ trigger ngoài, giữ DONE đến reset | Hoàn thành kiểm thử board |
| Phase 2 | Capture 1 bit × 256 mẫu từ nguồn nội bộ, lưu RAM và đọc lại | Hoàn thành mô phỏng và kiểm thử board theo kịch bản |
| Phase 3 | Capture tín hiệu dữ liệu ngoài qua GPIO | Dự kiến |

## Chức năng hiện tại

- KEY0: reset.
- KEY1: ARM; sau DONE dùng để chuyển địa chỉ đọc RAM.
- Keypad qua `ROW_0`: trigger.
- Thu 256 mẫu sau trigger với sample enable 1 kHz.
- Đọc dữ liệu đã lưu bằng HEX và LEDR1.

Nguồn dữ liệu capture hiện là bộ tạo mẫu nội bộ, chưa phải tín hiệu GPIO ngoài.

## Build và chạy

1. Mở project bằng Quartus Prime.
2. Chọn `debug_probe_phase2_top` làm top-level.
3. Kiểm tra đường dẫn source, pin assignment và cấu hình keypad.
4. Chạy Full Compilation, xem lại các warning.
5. Nạp file `.sof` vừa tạo bằng Quartus Programmer.
6. Reset → ARM → trigger → đọc lại dữ liệu.

## Kiểm chứng

- Controller, RAM và khối tích hợp đã PASS các testbench hiện có.
- Toàn bộ 256 ô RAM được so sánh tự động trong mô phỏng tích hợp.
- Trên board đã kiểm tra điều khiển, dữ liệu tại các địa chỉ theo kịch bản, giữ dữ liệu sau DONE và capture lại sau reset.

## Tài liệu

- [Phase 1 — Điều khiển ARM và nhận trigger](docs/phase1.md)
- [Phase 2 — Capture và đọc lại RAM](docs/phase2.md)

Chi tiết wiring, cách hiển thị, kết quả kiểm thử và giới hạn được ghi trong tài liệu từng phase.