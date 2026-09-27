////////////////////////////////////////////////////////////////////////////////
// File      : DataCachePlruTree.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
////////////////////////////////////////////////////////////////////////////////
module data_cache_plru_tree #(
    parameter int NUM_WAYS    = 4,
    parameter int CACHE_LINES = 128,
    parameter int INDEX_BITS  = $clog2(CACHE_LINES),
    parameter int WAY_BITS    = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire [INDEX_BITS-1:0] victimIndex,
    output logic [WAY_BITS-1:0]  victimWay,

    input  wire                  accessWe,
    input  wire [INDEX_BITS-1:0] accessIndex,
    input  wire [WAY_BITS-1:0]   accessWay
);

    localparam int PLRU_WIDTH  = (NUM_WAYS > 1) ? (NUM_WAYS - 1) : 1;

	
    logic [PLRU_WIDTH-1:0] plruMem [CACHE_LINES];


	// Victim selection
    integer victimNode;
    always_comb begin
        victimWay  = '0;
        victimNode = 0;
        if (NUM_WAYS > 1) begin
            for (int level = 0; level < WAY_BITS; level++) begin
                if (plruMem[victimIndex][victimNode]) begin
                    victimNode = 2 * victimNode + 2;
                end
                else begin
                    victimNode = 2 * victimNode + 1;
                end
            end
            victimWay = WAY_BITS'(victimNode - (NUM_WAYS - 1));
        end
    end

	// PLRU update
    integer accessNode;
    logic [PLRU_WIDTH-1:0] plruNext;
    always_comb begin
        plruNext   = plruMem[accessIndex];
        accessNode = 0;
        if (NUM_WAYS > 1) begin
            for (int level = 0; level < WAY_BITS; level++) begin
                if (accessWay[WAY_BITS-1-level]) begin
                    // Accessed right subtree -> next victim should prefer left subtree
                    plruNext[accessNode] = 1'b0;
                    accessNode = 2 * accessNode + 2;
                end else begin 
					// Accessed left  subtree -> next victim should prefer right subtree
                    plruNext[accessNode] = 1'b1;
                    accessNode = 2 * accessNode + 1;
                end
            end
        end
    end

    // PLRU memory
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < CACHE_LINES; i++)
                plruMem[i] <= '0;
        end
        else if (accessWe && (NUM_WAYS > 1)) begin
            plruMem[accessIndex] <= plruNext;
        end
    end

endmodule

