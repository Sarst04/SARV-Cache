
////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheSram.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
////////////////////////////////////////////////////////////////////////////////
module data_cache_sram #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 128,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                   clk,
    input  wire                   we,
    input  wire  [ADDR_WIDTH-1:0] addr,
    input  wire  [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];
    end

endmodule

