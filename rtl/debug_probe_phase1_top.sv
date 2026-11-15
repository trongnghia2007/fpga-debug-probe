module debug_probe_phase1_top (
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
	 
	 logic [1:0] capture_state;
	 logic capture_armed;
	 logic capture_done;
	 
	 logic arm_event;
	 logic trigger_event;
	 
	 logic trigger_in;
	 logic trigger_sync;
	 logic trigger_rise_pulse;
	 
	 assign trigger_in = ~ROW_0;

    // Normalize button: 1 means pressed.
    assign key1_pressed_raw = ~KEY1;

    // Synchronize the button input.
    sync_2ff u_key1_sync (
        .clk      (MAX10_CLK1_50),
        .rst_n    (KEY0),
        .async_in (key1_pressed_raw),
        .sync_out (key1_pressed_sync)
    );

    // Generate a one-cycle tick every 1 ms.
    clock_enable #(
        .CLK_HZ  (50_000_000),
        .TICK_HZ (1_000)
    ) u_tick_1ms (
        .clk   (MAX10_CLK1_50),
        .rst_n (KEY0),
        .tick  (tick_1ms)
    );

    // Debounce the synchronized button.
    debounce #(
        .STABLE_TICKS(10)
    ) u_key1_debounce (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .tick      (tick_1ms),
        .noisy_in  (key1_pressed_sync),
        .clean_out (key1_pressed_clean)
    );

    // Generate one pulse for each debounced press.
    edge_detect u_key1_edge (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .level_in  (key1_pressed_clean),
        .pulse_out (press_pulse)
    );
	 
	 // Synchronize the external trigger input.
    sync_2ff u_trigger_sync (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .async_in  (trigger_in),
        .sync_out  (trigger_sync)
    );

    // Generate one pulse for each detected rising edge.
    edge_detect u_trigger_edge (
        .clk       (MAX10_CLK1_50),
        .rst_n     (KEY0),
        .level_in  (trigger_sync),
        .pulse_out (trigger_rise_pulse)
    );

    // Count press events.
    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0)
            press_count <= 8'd0;
        else if (press_pulse)
            press_count <= press_count + 8'd1;
    end

    // Keep the verified heartbeat.
    always_ff @(posedge MAX10_CLK1_50 or negedge KEY0) begin
        if (!KEY0)
            count <= '0;
        else
            count <= count + 1'b1;
    end

	 
    assign arm_event = press_pulse && (capture_state == 2'd0);
    assign trigger_event = trigger_rise_pulse && (capture_state == 2'd1);
	 
	 capture_fsm u_capture_fsm (
		 .clk           (MAX10_CLK1_50),
		 .rst_n         (KEY0),

		 .arm_pulse     (arm_event),
		 .trigger_pulse (trigger_event),
		 .clear_pulse   (1'b0),

		 .state         (capture_state),
		 .armed         (capture_armed),
		 .done          (capture_done)
	);
	 
    assign LEDR0 = count[25];
    assign LEDR1 = key1_pressed_clean;

    // Low hexadecimal digit.
    hex_to_7seg u_hex0 (
		 .hex ({2'b00, capture_state}),
		 .seg (HEX0)
	);

	hex_to_7seg u_hex1 (
		 .hex (press_count[3:0]),
		 .seg (HEX1)
	);

endmodule