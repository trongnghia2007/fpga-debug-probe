`timescale 1ns/1ps

module tb_capture_controller;

    logic clk;
    logic rst_n;

    logic arm_pulse;
    logic trigger_pulse;
    logic sample_tick;

    logic [1:0] state;
    logic armed;
    logic capturing;
    logic done;

    logic sample_we;
    logic [7:0] write_addr;
    logic [8:0] samples_written;

    integer observed_writes;
    integer i;

    localparam logic [1:0] S_IDLE      = 2'd0;
    localparam logic [1:0] S_ARMED     = 2'd1;
    localparam logic [1:0] S_CAPTURING = 2'd2;
    localparam logic [1:0] S_DONE      = 2'd3;

    capture_controller dut (
        .clk             (clk),
        .rst_n           (rst_n),

        .arm_pulse       (arm_pulse),
        .trigger_pulse   (trigger_pulse),
        .sample_tick     (sample_tick),

        .state           (state),
        .armed           (armed),
        .capturing       (capturing),
        .done            (done),

        .sample_we       (sample_we),
        .write_addr      (write_addr),
        .samples_written (samples_written)
    );

    // 50 MHz clock: period = 20 ns.
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // Observe writes at the same edge a synchronous RAM would use.
    always @(posedge clk) begin
        if (!rst_n) begin
            observed_writes = 0;
        end else begin
            if (sample_we === 1'b1) begin
                if (state !== S_CAPTURING)
                    $fatal(1, "Write outside CAPTURING");

                if (observed_writes >= 256)
                    $fatal(1, "More than 256 writes");

                if (write_addr !== observed_writes[7:0])
                    $fatal(
                        1,
                        "Address mismatch: expected %0d, got %0d",
                        observed_writes,
                        write_addr
                    );

                observed_writes = observed_writes + 1;
            end else if (sample_we !== 1'b0) begin
                $fatal(1, "sample_we contains X/Z");
            end
        end
    end

    // Drive inputs on falling edges; inspect results after rising edges.
    task automatic step(
        input logic arm_value,
        input logic trigger_value,
        input logic tick_value
    );
        @(negedge clk);
        arm_pulse     = arm_value;
        trigger_pulse = trigger_value;
        sample_tick   = tick_value;

        @(posedge clk);
        #1;
    endtask

    task automatic check_status(
        input logic [1:0] expected_state,
        input integer expected_count
    );
        if (state !== expected_state)
            $fatal(
                1,
                "State mismatch: expected %0d, got %0d",
                expected_state,
                state
            );

        if (samples_written !== expected_count[8:0])
            $fatal(
                1,
                "Count mismatch: expected %0d, got %0d",
                expected_count,
                samples_written
            );

        if (observed_writes != expected_count)
            $fatal(
                1,
                "Observed writes: expected %0d, got %0d",
                expected_count,
                observed_writes
            );

        if (armed !== (expected_state == S_ARMED))
            $fatal(1, "armed flag mismatch");

        if (capturing !== (expected_state == S_CAPTURING))
            $fatal(1, "capturing flag mismatch");

        if (done !== (expected_state == S_DONE))
            $fatal(1, "done flag mismatch");
    endtask

    initial begin
        rst_n          = 1'b0;
        arm_pulse      = 1'b0;
        trigger_pulse  = 1'b0;
        sample_tick    = 1'b0;

        repeat (3) @(posedge clk);
        #1;
        check_status(S_IDLE, 0);
        $display("PASS: reset");

        @(negedge clk);
        rst_n = 1'b1;

        // A trigger before ARM must be ignored.
        step(0, 1, 1);
        check_status(S_IDLE, 0);
        $display("PASS: trigger ignored in IDLE");

        // ARM, then wait with ticks but no trigger.
        step(1, 0, 0);
        check_status(S_ARMED, 0);

        repeat (3) begin
            step(0, 0, 1);
            check_status(S_ARMED, 0);
        end

        // Additional ARM does not start capture.
        step(1, 0, 1);
        check_status(S_ARMED, 0);
        $display("PASS: ARMED waits for trigger");

        // A simultaneous tick is not captured on the transition edge.
        step(0, 1, 1);
        check_status(S_CAPTURING, 0);
        $display("PASS: trigger enters CAPTURING without writing");

        step(0, 0, 0);
        check_status(S_CAPTURING, 0);

        // Issue 256 write cycles, with periodic gaps.
        for (i = 0; i < 256; i = i + 1) begin
            if ((i % 4) == 0) begin
                step(0, 0, 0);
                check_status(S_CAPTURING, i);
            end

            step(0, 0, 1);

            if (i == 255)
                check_status(S_DONE, 256);
            else
                check_status(S_CAPTURING, i + 1);
        end

        $display("PASS: exactly 256 writes, addresses 0 through 255");

        // DONE must ignore all further requests.
        repeat (5) begin
            step(1, 1, 1);
            check_status(S_DONE, 256);
        end

        if (sample_we !== 1'b0)
            $fatal(1, "sample_we must be LOW in DONE");

        $display("PASS: DONE blocks further writes");

        // Reset the completed acquisition.
        @(negedge clk);
        rst_n         = 1'b0;
        arm_pulse     = 1'b0;
        trigger_pulse = 1'b0;
        sample_tick   = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        check_status(S_IDLE, 0);
        $display("PASS: reset after DONE");

        $display("ALL TESTS PASSED");
        $finish;
    end

    // Prevent a broken test from running forever.
    initial begin
        #100_000;
        $fatal(1, "Simulation timeout");
    end

endmodule