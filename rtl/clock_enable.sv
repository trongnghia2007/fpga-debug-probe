module clock_enable #(
    parameter int CLK_HZ  = 50_000_000,
    parameter int TICK_HZ = 1_000
) (
    input  logic clk,
    input  logic rst_n,
    output logic tick
);

    localparam int COUNT_MAX = CLK_HZ / TICK_HZ - 1;
    localparam int COUNT_W   = $clog2(COUNT_MAX + 1);

    logic [COUNT_W-1:0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
            tick  <= 1'b0;
        end else if (count == COUNT_MAX) begin
            count <= '0;
            tick  <= 1'b1;
        end else begin
            count <= count + 1'b1;
            tick  <= 1'b0;
        end
    end

endmodule