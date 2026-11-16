module capture_ram #(
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 8
) (
    input  logic                  clk,

    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,

    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    localparam int DEPTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;

        rd_data <= mem[rd_addr];
    end

endmodule