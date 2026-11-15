module debounce #(
    parameter int STABLE_TICKS = 10
) (
    input  logic clk,
    input  logic rst_n,
    input  logic tick,
    input  logic noisy_in,
    output logic clean_out
);

    localparam int COUNT_W = $clog2(STABLE_TICKS + 1);

    logic [COUNT_W-1:0] stable_count;
    logic candidate;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clean_out    <= 1'b0;
            candidate    <= 1'b0;
            stable_count <= '0;
        end else if (tick) begin
            if (noisy_in == clean_out) begin
                stable_count <= '0;
                candidate    <= noisy_in;
            end else if (noisy_in != candidate) begin
                candidate    <= noisy_in;
                stable_count <= 1'd1;
            end else if (stable_count == STABLE_TICKS - 1) begin
                clean_out    <= candidate;
                stable_count <= '0;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end

endmodule