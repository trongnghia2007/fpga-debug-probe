module edge_detect (
    input  logic clk,
    input  logic rst_n,
    input  logic level_in,
    output logic pulse_out
);

    logic level_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level_d   <= 1'b0;
            pulse_out <= 1'b0;
        end else begin
            pulse_out <= level_in & ~level_d;
            level_d   <= level_in;
        end
    end

endmodule