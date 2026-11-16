`timescale 1ns/1ps

module tb_capture_core;

    logic clk = 1'b0;
    always #10 clk = ~clk;

    logic       rst_n;
    logic       arm_pulse;
    logic       trigger_pulse;
    logic       sample_tick;
    logic       sample_data;

    logic [7:0] rd_addr;
    logic       rd_data;

    logic [1:0] state;
    logic       armed;
    logic       capturing;
    logic       done;

    logic       sample_we;
    logic [7:0] write_addr;
    logic [8:0] samples_written;

    logic expected_mem [0:255];
    integer writes_seen = 0;

    capture_core dut (
        .clk             (clk),
        .rst_n           (rst_n),

        .arm_pulse       (arm_pulse),
        .trigger_pulse   (trigger_pulse),
        .sample_tick     (sample_tick),
        .sample_data     (sample_data),

        .rd_addr         (rd_addr),
        .rd_data         (rd_data),

        .state           (state),
        .armed           (armed),
        .capturing       (capturing),
        .done            (done),

        .sample_we       (sample_we),
        .write_addr      (write_addr),
        .samples_written (samples_written)
    );

    // Observe the same pre-update signals that the RAM uses.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            writes_seen = 0;
        end else if (sample_we) begin
            if (state !== 2'd2)
                $fatal(1, "Write outside CAPTURING");

            if (writes_seen >= 256)
                $fatal(1, "More than 256 writes");

            if (write_addr !== writes_seen[7:0])
                $fatal(
                    1,
                    "Address mismatch: expected=%0d actual=%0d",
                    writes_seen, write_addr
                );

            expected_mem[writes_seen] = sample_data;
            writes_seen = writes_seen + 1;
        end
    end

    function automatic logic pattern(
        input int index,
        input bit invert_pattern
    );
        pattern = (^index[7:0]) ^ invert_pattern;
    endfunction

    task automatic apply_reset;
        @(negedge clk);
        rst_n         = 1'b0;
        arm_pulse     = 1'b0;
        trigger_pulse = 1'b0;
        sample_tick   = 1'b0;
        sample_data   = 1'b0;
        rd_addr       = '0;

        repeat (2) @(negedge clk);

        rst_n = 1'b1;

        @(posedge clk);
        #1;

        if (state !== 2'd0 ||
            samples_written !== 9'd0 ||
            sample_we !== 1'b0 ||
            writes_seen != 0)
            $fatal(1, "Reset failed");
    endtask

    task automatic read_and_check;
        for (int i = 0; i < 256; i++) begin
            @(negedge clk);
            rd_addr = i;

            @(posedge clk);
            #1;

            if (rd_data !== expected_mem[i])
                $fatal(
                    1,
                    "RAM mismatch: addr=%0d expected=%b actual=%b",
                    i, expected_mem[i], rd_data
                );
        end
    endtask

    task automatic run_capture(input bit invert_pattern);

        // Trigger and ticks in IDLE must not write.
        @(negedge clk);
        trigger_pulse = 1'b1;
        sample_tick   = 1'b1;
        sample_data   = 1'b1;

        @(posedge clk);
        #1;

        if (state !== 2'd0 ||
            sample_we !== 1'b0 ||
            writes_seen != 0)
            $fatal(1, "IDLE accepted trigger or wrote data");

        // Arm without a trigger.
        @(negedge clk);
        trigger_pulse = 1'b0;
        sample_tick   = 1'b0;
        arm_pulse     = 1'b1;

        @(posedge clk);
        #1;

        if (state !== 2'd1 || armed !== 1'b1)
            $fatal(1, "Failed to enter ARMED");

        @(negedge clk);
        arm_pulse   = 1'b0;
        sample_tick = 1'b1;

        repeat (3) begin
            @(posedge clk);
            #1;

            if (state !== 2'd1 ||
                sample_we !== 1'b0 ||
                writes_seen != 0)
                $fatal(1, "ARMED wrote without trigger");
        end

        // Trigger and tick coincide: no write on this edge.
        @(negedge clk);
        trigger_pulse = 1'b1;
        sample_tick   = 1'b1;

        @(posedge clk);
        #1;

        if (state !== 2'd2 ||
            samples_written !== 9'd0 ||
            writes_seen != 0)
            $fatal(1, "Trigger edge incorrectly counted a sample");

        @(negedge clk);
        trigger_pulse = 1'b0;
        sample_tick   = 1'b0;

        $display("PASS: IDLE, ARMED and trigger-edge behavior");

        // Vary the gaps between ticks.
        for (int i = 0; i < 256; i++) begin

            for (int gap = 0; gap < (i % 3); gap++) begin
                @(negedge clk);
                sample_tick = 1'b0;
                sample_data = ~pattern(i, invert_pattern);

                @(posedge clk);
                #1;

                if (sample_we !== 1'b0 ||
                    samples_written !== i[8:0] ||
                    writes_seen != i)
                    $fatal(1, "Unexpected write during tick gap");
            end

            @(negedge clk);
            sample_tick = 1'b1;
            sample_data = pattern(i, invert_pattern);

            @(posedge clk);
            #1;

            if (samples_written !== (i + 1))
                $fatal(
                    1,
                    "Count mismatch after sample %0d: count=%0d",
                    i, samples_written
                );

            if (writes_seen != (i + 1))
                $fatal(1, "RAM write count mismatch");

            if (i < 255) begin
                if (state !== 2'd2)
                    $fatal(1, "Capture ended too early");
            end else begin
                if (state !== 2'd3 || done !== 1'b1)
                    $fatal(1, "Failed to enter DONE");
            end

            @(negedge clk);
            sample_tick = 1'b0;
        end

        $display("PASS: 256 writes, addresses 0 through 255");

        read_and_check();
        $display("PASS: all captured data matches sampled input");

        // Try more ticks, arm and trigger while DONE.
        @(negedge clk);
        sample_tick   = 1'b1;
        arm_pulse     = 1'b1;
        trigger_pulse = 1'b1;

        repeat (8) begin
            @(negedge clk);
            sample_data = ~sample_data;

            @(posedge clk);
            #1;

            if (state !== 2'd3 ||
                sample_we !== 1'b0 ||
                samples_written !== 9'd256 ||
                writes_seen != 256)
                $fatal(1, "DONE failed to block further capture");
        end

        @(negedge clk);
        sample_tick   = 1'b0;
        arm_pulse     = 1'b0;
        trigger_pulse = 1'b0;

        read_and_check();
        $display("PASS: DONE preserves captured RAM data");

    endtask

    initial begin
        rst_n         = 1'b1;
        arm_pulse     = 1'b0;
        trigger_pulse = 1'b0;
        sample_tick   = 1'b0;
        sample_data   = 1'b0;
        rd_addr       = '0;

        apply_reset();
        $display("PASS: initial reset");

        run_capture(1'b0);
        $display("PASS: capture session 1");

        apply_reset();
        $display("PASS: reset after DONE");

        run_capture(1'b1);
        $display("PASS: capture session 2 with inverted data");

        $display("ALL CAPTURE CORE TESTS PASSED");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "TIMEOUT");
    end

endmodule