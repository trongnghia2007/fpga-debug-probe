module debug_probe_phase2_top (
    input  logic       MAX10_CLK1_50,
    input  logic       KEY0,
    input  logic       KEY1,
    input  logic       ROW_0,

    output logic       LEDR0,
    output logic       LEDR1,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1
);

    logic [25:0] count;

    logic key1_pressed_raw;
    logic key1_pressed_sync;
    logic key1_pressed_clean;

    logic tick_1ms;
    logic press_pulse;
    logic [7:0] press_count;

    logic trigger_in;
    logic trigger_sync;
    logic trigger_rise_pulse;

    logic arm_event;
    logic trigger_event;

    logic [1:0] capture_state;
    logic capture_armed;
    logic capture_capturing;
    logic capture_done;

    logic       sample_we;
    logic [7:0] write_addr;
    logic [8:0] samples_written;

    logic [7:0] pattern_lfsr;
    logic       sample_data;

    logic [7:0] read_addr;
    logic       read_data;

    logic [3:0] hex0_value;
    logic [3:0] hex1_value;

    assign key1_pressed_raw = ~KEY1;
    assign trigger_in       = ~ROW_0;

    // KEY1 synchronization.
    sync_2ff u_key1_sync (
        .clk      (MAX10_CLK1_50),
        .rst_n    (KEY0),
        .async_in (key1_pressed_raw),
        .sync_out (key1_pressed_sync)
    );

    // Shared 1 ms enable for debounce and capture sampling.
    clock_enable #(
        .CLK_HZ  (50_000_000),
        .TICK_HZ (1_000)
    ) u_tick_1ms (
        .clk   (MAX10_CLK1_50),
        .rst_n (KEY0),
        .tick  (tick_1ms)
    );

    debounce #(
        .STABLE_TICKS (10)
    ) u_key1_debounce (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .tick      (tick_1ms),
        .noisy_in  (key1_pressed_sync),
        .clean_out (key1_pressed_clean)
    );

    edge_detect u_key1_edge (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .level_in  (key1_pressed_clean),
        .pulse_out (press_pulse)
    );

    // External trigger path, unchanged from Phase 1.
    sync_2ff u_trigger_sync (
        .clk      (MAX10_CLK1_50),
        .rst_n    (KEY0),
        .async_in (trigger_in),
        .sync_out (trigger_sync)
    );

    edge_detect u_trigger_edge (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .level_in  (trigger_sync),
        .pulse_out (trigger_rise_pulse)
    );

    assign arm_event =
        press_pulse && (capture_state == 2'd0);

    assign trigger_event =
        trigger_rise_pulse && (capture_state == 2'd1);

    // Deterministic internal sample source.
    assign sample_data = pattern_lfsr[0];

    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0) begin
            pattern_lfsr <= 8'hA5;
        end else if (sample_we) begin
            pattern_lfsr <= {
                pattern_lfsr[6:0],
                pattern_lfsr[7] ^
                pattern_lfsr[5] ^
                pattern_lfsr[4] ^
                pattern_lfsr[3]
            };
        end
    end

    capture_core u_capture_core (
        .clk             (MAX10_CLK1_50),
        .rst_n           (KEY0),

        .arm_pulse       (arm_event),
        .trigger_pulse   (trigger_event),
        .sample_tick     (tick_1ms),
        .sample_data     (sample_data),

        .rd_addr         (read_addr),
        .rd_data         (read_data),

        .state           (capture_state),
        .armed           (capture_armed),
        .capturing       (capture_capturing),
        .done            (capture_done),

        .sample_we       (sample_we),
        .write_addr      (write_addr),
        .samples_written (samples_written)
    );

    // In DONE, each KEY1 press advances the RAM read address.
    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0)
            read_addr <= 8'd0;
        else if (capture_done && press_pulse)
            read_addr <= read_addr + 8'd1;
    end

    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0)
            press_count <= 8'd0;
        else if (press_pulse)
            press_count <= press_count + 8'd1;
    end

    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0)
            count <= '0;
        else
            count <= count + 1'b1;
    end

    assign LEDR0 = count[25];

    assign LEDR1 =
        capture_done ? read_data : key1_pressed_clean;

    assign hex0_value =
        capture_done ? read_addr[7:4] :
                       {2'b00, capture_state};

    assign hex1_value =
        capture_done ? read_addr[3:0] :
                       press_count[3:0];

    hex_to_7seg u_hex0 (
        .hex (hex0_value),
        .seg (HEX0)
    );

    hex_to_7seg u_hex1 (
        .hex (hex1_value),
        .seg (HEX1)
    );

endmodule