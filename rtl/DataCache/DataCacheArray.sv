////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheArray.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
////////////////////////////////////////////////////////////////////////////////
module data_cache_array #(
    parameter int CACHE_LINES = 128,
    parameter int NUM_WAYS    = 4,
    parameter int TAG_BITS    = 25,
    parameter int DATA_WIDTH  = 32,
    parameter int INDEX_BITS  = $clog2(CACHE_LINES),
    parameter int WAY_BITS    = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1
)(
    input  wire                                 clk,
    input  wire                                 rst,

    input  wire [INDEX_BITS-1:0]                sramAddr,
    input  wire [TAG_BITS-1:0]                  curTag,

    input  wire                                 cacheWe,
    input  wire [WAY_BITS-1:0]                  cacheWrWay,
    input  wire [TAG_BITS-1:0]                  cacheWrTag,
    input  wire [DATA_WIDTH-1:0]                cacheWrData,

    input  wire                                 dirtyWe,
    input  wire                                 dirtyWrData,

    input  wire                                 lruWe,
    input  wire [WAY_BITS-1:0]                  lruWrWay,

    output logic [NUM_WAYS-1:0][TAG_BITS-1:0]   readTag,
    output logic [NUM_WAYS-1:0][DATA_WIDTH-1:0] readData,
    output logic [NUM_WAYS-1:0]                 readValid,
    output logic [NUM_WAYS-1:0]                 readDirty,
    output logic [WAY_BITS-1:0]                 victimWay,

    output logic                                hit,
    output logic [WAY_BITS-1:0]                 accessedWay,
    output logic [WAY_BITS-1:0]                 allocWay
);

    logic validMem [NUM_WAYS-1:0][CACHE_LINES];
    logic dirtyMem [NUM_WAYS-1:0][CACHE_LINES];

    for (genvar w = 0; w < NUM_WAYS; w++) begin : cache_ways
        logic sramWe;
        assign sramWe = cacheWe && (cacheWrWay == WAY_BITS'(w));

        data_cache_sram #(
            .DATA_WIDTH(TAG_BITS),
            .DEPTH(CACHE_LINES)
        ) tagSram (
            .clk (clk),
            .we  (sramWe),
            .addr(sramAddr),
            .din (cacheWrTag),
            .dout(readTag[w])
        );

        data_cache_sram #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH(CACHE_LINES)
        ) dataSram (
            .clk (clk),
            .we  (sramWe),
            .addr(sramAddr),
            .din (cacheWrData),
            .dout(readData[w])
        );
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int w = 0; w < NUM_WAYS; w++) begin
                for (int i = 0; i < CACHE_LINES; i++) begin
                    validMem[w][i] <= 1'b0;
                    dirtyMem[w][i] <= 1'b0;
                end
            end
        end else begin
            if (cacheWe)
                validMem[cacheWrWay][sramAddr] <= 1'b1;

            if (dirtyWe)
                dirtyMem[cacheWrWay][sramAddr] <= dirtyWrData;
        end
    end

    always_comb begin
        readValid = '0;
        readDirty = '0;

        for (int i = 0; i < NUM_WAYS; i++) begin
            readValid[i] = validMem[i][sramAddr];
            readDirty[i] = dirtyMem[i][sramAddr];
        end
    end

    always_comb begin
        hit         = 1'b0;
        accessedWay = '0;

        for (int i = 0; i < NUM_WAYS; i++) begin
            if (readValid[i] && (readTag[i] == curTag)) begin
                hit         = 1'b1;
                accessedWay = WAY_BITS'(i);
                break;
            end
        end
    end

    always_comb begin
        allocWay = (NUM_WAYS == 1) ? '0 : victimWay;

        for (int i = 0; i < NUM_WAYS; i++) begin
            if (!readValid[i]) begin
                allocWay = WAY_BITS'(i);
                break;
            end
        end
    end

    data_cache_plru_tree #(
        .NUM_WAYS(NUM_WAYS),
        .CACHE_LINES(CACHE_LINES)
    ) dataCachePlruTree (
        .clk(clk),
        .rst(rst),
        .victimIndex(sramAddr),
        .victimWay(victimWay),
        .accessWe(lruWe),
        .accessIndex(sramAddr),
        .accessWay(lruWrWay)
    );

endmodule

