////////////////////////////////////////////////////////////////////////////////
// File      : DataCache.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
// Description:
// 		Data Cache with store buffer, external SRAM and tree-PLRU.
////////////////////////////////////////////////////////////////////////////////
module data_cache #(
    parameter int CACHE_LINES     = 128,
    parameter int NUM_WAYS        = 4,
    parameter int WORD_PER_LINES  = 1,
    parameter int STORE_BUF_DEPTH = 2,
    parameter bit BYPASS_CACHE    = 0,

    parameter logic [31:0] MEM_BASE = 32'h8000_0000,
    parameter logic [31:0] MEM_END  = 32'h8F00_0000
)(
    input  wire                           clk,
    input  wire                           rst,

    input  wire                           readReq,
    input  wire                           writeReq,
    input  wire  [ 1:0]                   accessType,
    output logic                          waitReq,

    input  wire  [31:0]                   address,
    input  wire  [31:0]                   dataIn,
    output logic [31:0]                   dataOut,

    input  wire                           memWaitReq,
    output logic                          memReadReq,
    output logic                          memWriteReq,
    output logic [ 1:0]                   memAccessType,

    input  wire  [32*WORD_PER_LINES-1:0]  memDataIn,
    output logic [31:0]                   memAddress,
    output logic [32*WORD_PER_LINES-1:0]  memDataOut
);

    if (BYPASS_CACHE) begin : bypass

        assign memReadReq    = readReq;
        assign memWriteReq   = writeReq;
        assign memAddress    = address;
        assign memDataOut    = {{(32*WORD_PER_LINES-32){1'b0}}, dataIn};
        assign memAccessType = accessType;

        assign dataOut 		 = memDataIn[31:0];
        assign waitReq 		 = memWaitReq;

    end else begin : cache

        localparam int DATA_WIDTH = 32 * WORD_PER_LINES;

        localparam int ALIGN_BITS        = 2;
        localparam int WORD_OFFSET_BITS  = (WORD_PER_LINES == 1) ? 0 : $clog2(WORD_PER_LINES);
        localparam int INDEX_BITS        = $clog2(CACHE_LINES);
        localparam int TAG_BITS          = 32 - ALIGN_BITS - WORD_OFFSET_BITS - INDEX_BITS;
        localparam int WAY_BITS          = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;
        localparam int WORD_OFFSET_WIDTH = (WORD_OFFSET_BITS == 0) ? 1 : WORD_OFFSET_BITS;

        logic        isPeripheralAccess;
        logic        cacheReadReq;
        logic        cacheWriteReq;
        logic [31:0] cacheDataOut;
        logic        cacheWaitReq;

        assign isPeripheralAccess = (address < MEM_BASE) | (address > MEM_END);
        assign cacheReadReq       = readReq  & ~isPeripheralAccess;
        assign cacheWriteReq      = writeReq & ~isPeripheralAccess;

        // Address decode
        logic        curDrain;
        wire  [31:0] curAddress;

        wire [WORD_OFFSET_WIDTH-1:0] curWordOffset;

        if (WORD_PER_LINES == 1) begin : gen_word_offset_single
            assign curWordOffset = '0;
        end else begin : gen_word_offset_multi
            assign curWordOffset = curAddress[ALIGN_BITS +: WORD_OFFSET_BITS];
        end

        wire [INDEX_BITS-1:0] curIndex = curAddress[ALIGN_BITS + WORD_OFFSET_BITS +: INDEX_BITS];
        wire [TAG_BITS-1:0]   curTag   = curAddress[31 : ALIGN_BITS + WORD_OFFSET_BITS + INDEX_BITS];
        wire [1:0]            curOff   = address[1:0];


        // Store buffer and forwarding
        logic        storeBufEmpty;
        logic        storeBufFull;
        logic        storeBufPush;
        logic        storeBufPop;
        logic [31:0] storeBufHeadAddr;
        logic [31:0] storeBufHeadData;
        logic [ 1:0] storeBufHeadType;
        logic [31:0] fwdWord;

        assign storeBufPush = cacheWriteReq & ~storeBufFull;

        // Cache array signals
        logic                  	cacheWe;
        logic [WAY_BITS-1:0]   	cacheWrWay;
        logic                  	dirtyWe;
        logic                  	dirtyWrData;
        logic                  	lruWe;
        logic [WAY_BITS-1:0] 	lruWrWay;

        logic [NUM_WAYS-1:0][TAG_BITS-1:0]    readTag;
        logic [NUM_WAYS-1:0][DATA_WIDTH-1:0]  readData;
        logic [NUM_WAYS-1:0]                  readValid;
        logic [NUM_WAYS-1:0]                  readDirty;
        logic [WAY_BITS-1:0]                  victimWay;

        logic                  	hit;
        logic [WAY_BITS-1:0]   	accessedWay;
        logic [WAY_BITS-1:0]   	allocWay;

        logic                  	allocValid;
        logic                  	allocDirty;
        logic [TAG_BITS-1:0]   	allocTag;
        logic [DATA_WIDTH-1:0] 	allocData;

        assign allocValid = readValid[allocWay];
        assign allocDirty = readDirty[allocWay];
        assign allocTag   = readTag[allocWay];
        assign allocData  = readData[allocWay];


        // Datapath signals
        logic [31:0]           dataOutBase;
        logic [DATA_WIDTH-1:0] cacheWrData;

        logic                  selectCacheRd;
        logic                  selectMemRd;
        logic                  selectCacheWr;
        logic                  selectMemWr;

        // Controller signals
        logic                  memReadReqR;
        logic                  memWriteReqR;
        logic [31:0]           memAddrR;
        logic [DATA_WIDTH-1:0] memDataOutR;
        logic                  loadDone;
        logic                  storeDrainDone;
        logic                  controllerIdle;

        // Instantiations
        assign curAddress = curDrain ? storeBufHeadAddr : address;

        data_cache_store_buffer #(
            .DEPTH(STORE_BUF_DEPTH)
        ) dataCacheStoreBuffer (
            .clk(clk),
            .rst(rst),
            .push(storeBufPush),
            .pushAddr(address),
            .pushData(dataIn),
            .pushType(accessType),
            .pop(storeBufPop),
            .empty(storeBufEmpty),
            .full(storeBufFull),
            .headAddr(storeBufHeadAddr),
            .headData(storeBufHeadData),
            .headType(storeBufHeadType),
            .fwdAddr(address),
            .fwdBase(dataOutBase),
            .fwdWord(fwdWord)
        );

        data_cache_array #(
            .CACHE_LINES(CACHE_LINES),
            .NUM_WAYS(NUM_WAYS),
            .TAG_BITS(TAG_BITS),
            .DATA_WIDTH(DATA_WIDTH)
        ) dataCacheArray (
            .clk(clk),
            .rst(rst),
            .sramAddr(curIndex),
            .curTag(curTag),
            .cacheWe(cacheWe),
            .cacheWrWay(cacheWrWay),
            .cacheWrTag(curTag),
            .cacheWrData(cacheWrData),
            .dirtyWe(dirtyWe),
            .dirtyWrData(dirtyWrData),
            .lruWe(lruWe),
            .lruWrWay(lruWrWay),
            .readTag(readTag),
            .readData(readData),
            .readValid(readValid),
            .readDirty(readDirty),
            .victimWay(victimWay),
            .hit(hit),
            .accessedWay(accessedWay),
            .allocWay(allocWay)
        );

        data_cache_data_path #(
            .DATA_WIDTH(DATA_WIDTH),
            .WORD_OFFSET_WIDTH(WORD_OFFSET_WIDTH)
        ) dataCacheDataPath (
            .readDataSel(readData[accessedWay]),
            .memDataIn(memDataIn),
            .curWordOffset(curWordOffset),
            .selectCacheRd(selectCacheRd),
            .selectMemRd(selectMemRd),
            .selectCacheWr(selectCacheWr),
            .selectMemWr(selectMemWr),
            .fwdWord(fwdWord),
            .storeBufHeadAddr(storeBufHeadAddr),
            .storeBufHeadData(storeBufHeadData),
            .storeBufHeadType(storeBufHeadType),
            .accessType(accessType),
            .curOff(curOff),
            .dataOutBase(dataOutBase),
            .cacheDataOut(cacheDataOut),
            .cacheWrData(cacheWrData)
        );

        data_cache_controller #(
            .CACHE_LINES(CACHE_LINES),
            .TAG_BITS(TAG_BITS),
            .DATA_WIDTH(DATA_WIDTH),
            .WAY_BITS(WAY_BITS),
            .ALIGN_BITS(ALIGN_BITS),
            .WORD_OFFSET_BITS(WORD_OFFSET_BITS)
        ) dataCacheController (
            .clk(clk),
            .rst(rst),
            .cacheReadReq(cacheReadReq),
            .storeBufEmpty(storeBufEmpty),
            .memWaitReq(memWaitReq),
            .hit(hit),
            .accessedWay(accessedWay),
            .allocWay(allocWay),
            .allocValid(allocValid),
            .allocDirty(allocDirty),
            .allocTag(allocTag),
            .allocData(allocData),
            .curIndex(curIndex),
            .curTag(curTag),
            .cacheWe(cacheWe),
            .cacheWrWay(cacheWrWay),
            .dirtyWe(dirtyWe),
            .dirtyWrData(dirtyWrData),
            .lruWe(lruWe),
            .lruWrWay(lruWrWay),
            .memReadReqR(memReadReqR),
            .memWriteReqR(memWriteReqR),
            .memAddrR(memAddrR),
            .memDataOutR(memDataOutR),
            .selectCacheRd(selectCacheRd),
            .selectMemRd(selectMemRd),
            .selectCacheWr(selectCacheWr),
            .selectMemWr(selectMemWr),
            .loadDone(loadDone),
            .storeDrainDone(storeDrainDone),
            .curDrain(curDrain),
            .controllerIdle(controllerIdle)
        );

        assign storeBufPop 		= storeDrainDone;
        assign cacheWaitReq 	= cacheReadReq & ~loadDone;

        logic periphPass;
        assign periphPass 		= isPeripheralAccess && storeBufEmpty && controllerIdle;

        assign memReadReq    	= periphPass ? readReq  : memReadReqR;
        assign memWriteReq   	= periphPass ? writeReq : memWriteReqR;
        assign memAddress    	= periphPass ? address  : memAddrR;
        assign memDataOut    	= periphPass ? {{(DATA_WIDTH-32){1'b0}}, dataIn} : memDataOutR;
        assign memAccessType 	= periphPass ? accessType : 2'b10;

        assign dataOut 			= isPeripheralAccess ? memDataIn[31:0] : cacheDataOut;

        assign waitReq 			= periphPass         ? memWaitReq :
                         		  isPeripheralAccess ? (readReq | writeReq) :
                         		  cacheWriteReq      ? storeBufFull :
	                                           		   cacheWaitReq;
    end
endmodule


