module button_event #(
    parameter int STABLE_TICKS = 10
) (
    input  logic clk,
    input  logic rst_n,
    input  logic tick,
    input  logic raw_pressed,
    output logic pressed_level,
    output logic pressed_pulse
);

    logic synchronized_pressed;

    sync_2ff u_sync (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (raw_pressed),
        .sync_out (synchronized_pressed)
    );

    debounce #(
        .STABLE_TICKS(STABLE_TICKS)
    ) u_debounce (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick      (tick),
        .noisy_in  (synchronized_pressed),
        .clean_out (pressed_level)
    );

    edge_detect u_edge (
        .clk       (clk),
        .rst_n     (rst_n),
        .level_in  (pressed_level),
        .pulse_out (pressed_pulse)
    );

endmodule