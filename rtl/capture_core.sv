module capture_core (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       arm_pulse,
    input  logic       trigger_pulse,
    input  logic       sample_tick,
    input  logic       sample_data,

    input  logic [7:0] rd_addr,
    output logic       rd_data,

    output logic [1:0] state,
    output logic       armed,
    output logic       capturing,
    output logic       done,

    output logic       sample_we,
    output logic [7:0] write_addr,
    output logic [8:0] samples_written
);

    capture_controller u_controller (
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

    capture_ram #(
        .DATA_WIDTH (1),
        .ADDR_WIDTH (8)
    ) u_ram (
        .clk     (clk),

        .wr_en   (sample_we),
        .wr_addr (write_addr),
        .wr_data (sample_data),

        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

endmodule