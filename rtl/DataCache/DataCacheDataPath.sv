////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheDataPath.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
////////////////////////////////////////////////////////////////////////////////
module data_cache_data_path #(
    parameter int DATA_WIDTH        = 32,
    parameter int WORD_OFFSET_WIDTH = 1
)(
    input  wire [DATA_WIDTH-1:0]         readDataSel,
    input  wire [DATA_WIDTH-1:0]         memDataIn,
    input  wire [WORD_OFFSET_WIDTH-1:0]  curWordOffset,

    input  wire                          selectCacheRd,
    input  wire                          selectMemRd,
    input  wire                          selectCacheWr,
    input  wire                          selectMemWr,

    input  wire [31:0]                   fwdWord,
    input  wire [31:0]                   storeBufHeadAddr,
    input  wire [31:0]                   storeBufHeadData,
    input  wire [ 1:0]                   storeBufHeadType,

    input  wire [ 1:0]                   accessType,
    input  wire [ 1:0]                   curOff,

    output logic [31:0]                  dataOutBase,
    output logic [31:0]                  cacheDataOut,
    output logic [DATA_WIDTH-1:0]        cacheWrData
);

	localparam logic [1:0] 	BYTE = 2'b00;
	localparam logic [1:0] 	HALF = 2'b01;
	localparam logic [1:0] 	WORD = 2'b10;

    logic [31:0] mergeBaseData;
    logic [31:0] mergedWrData;

    always_comb begin
        dataOutBase   = 32'b0;
        mergeBaseData = 32'b0;

        if (selectCacheRd)
            dataOutBase = readDataSel[curWordOffset*32 +: 32];
        else if (selectMemRd)
            dataOutBase = memDataIn[curWordOffset*32 +: 32];

        if (selectCacheWr)
            mergeBaseData = readDataSel[curWordOffset*32 +: 32];
        else if (selectMemWr)
            mergeBaseData = memDataIn[curWordOffset*32 +: 32];
    end

    always_comb begin
        mergedWrData = mergeBaseData;
        case (storeBufHeadType)
            BYTE:   mergedWrData[storeBufHeadAddr[1:0]*8 +: 8]  = storeBufHeadData[7:0];
            HALF:   mergedWrData[storeBufHeadAddr[1:0]*8 +: 16] = storeBufHeadData[15:0];
            WORD:   mergedWrData = storeBufHeadData;
        endcase
    end

    always_comb begin
        cacheDataOut = 32'b0;
        case (accessType)
            BYTE:   cacheDataOut = {24'b0, fwdWord[curOff*8 +: 8]};
            HALF:   cacheDataOut = {16'b0, fwdWord[curOff*8 +: 16]};
            WORD:   cacheDataOut = fwdWord;
        endcase
    end

    always_comb begin
        if (selectCacheWr)
            cacheWrData = readDataSel;
        else
            cacheWrData = memDataIn;

        if (selectCacheWr || selectMemWr)
            cacheWrData[curWordOffset*32 +: 32] = mergedWrData;
    end

endmodule

