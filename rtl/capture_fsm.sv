module capture_fsm (
    input  logic clk,
    input  logic rst_n,
    input  logic arm_pulse,
    input  logic trigger_pulse,
    input  logic clear_pulse,

    output logic [1:0] state,
    output logic       armed,
    output logic       done
);

    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        ARMED = 2'd1,
        DONE  = 2'd2
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        if (clear_pulse) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE: begin
                    if (arm_pulse)
                        next_state = ARMED;
                end

                ARMED: begin
                    if (trigger_pulse)
                        next_state = DONE;
                end

                DONE: begin
                    next_state = DONE;
                end

                default: begin
                    next_state = IDLE;
                end
            endcase
        end
    end

    always_comb begin
        state = current_state;
        armed = (current_state == ARMED);
        done  = (current_state == DONE);
    end

endmodule