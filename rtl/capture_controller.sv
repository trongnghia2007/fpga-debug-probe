module capture_controller (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       arm_pulse,
    input  logic       trigger_pulse,
    input  logic       sample_tick,

    output logic [1:0] state,
    output logic       armed,
    output logic       capturing,
    output logic       done,

    output logic       sample_we,
    output logic [7:0] write_addr,
    output logic [8:0] samples_written
);

    typedef enum logic [1:0] {
        IDLE      = 2'd0,
        ARMED     = 2'd1,
        CAPTURING = 2'd2,
        DONE      = 2'd3
    } state_t;

    state_t current_state;

    assign state     = current_state;
    assign armed     = (current_state == ARMED);
    assign capturing = (current_state == CAPTURING);
    assign done      = (current_state == DONE);

    // Write one sample on each enabled capture cycle.
    assign sample_we =
        capturing && sample_tick && rst_n;

    // Valid as a RAM write address when sample_we is HIGH.
    assign write_addr = samples_written[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state   <= IDLE;
            samples_written <= 9'd0;
        end else begin
            case (current_state)

                IDLE: begin
                    samples_written <= 9'd0;

                    if (arm_pulse)
                        current_state <= ARMED;
                end

                ARMED: begin
                    if (trigger_pulse)
                        current_state <= CAPTURING;
                end

                CAPTURING: begin
                    if (sample_we) begin
                        samples_written <=
                            samples_written + 9'd1;

                        if (samples_written == 9'd255)
                            current_state <= DONE;
                    end
                end

                DONE: begin
                    // Hold results until reset.
                    current_state <= DONE;
                end

                default: begin
                    current_state   <= IDLE;
                    samples_written <= 9'd0;
                end

            endcase
        end
    end

endmodule