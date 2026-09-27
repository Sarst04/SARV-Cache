////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheController.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
////////////////////////////////////////////////////////////////////////////////
module data_cache_controller #(
    parameter int CACHE_LINES      = 128,
    parameter int TAG_BITS         = 25,
    parameter int DATA_WIDTH       = 32,
    parameter int INDEX_BITS       = $clog2(CACHE_LINES),
    parameter int WAY_BITS         = 2,
    parameter int ALIGN_BITS       = 2,
    parameter int WORD_OFFSET_BITS = 0
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire                   cacheReadReq,
    input  wire                   storeBufEmpty,
    input  wire                   memWaitReq,

    input  wire                   hit,
    input  wire [WAY_BITS-1:0]    accessedWay,
    input  wire [WAY_BITS-1:0]    allocWay,
    input  wire                   allocValid,
    input  wire                   allocDirty,
    input  wire [TAG_BITS-1:0]    allocTag,
    input  wire [DATA_WIDTH-1:0]  allocData,

    input  wire [INDEX_BITS-1:0]  curIndex,
    input  wire [TAG_BITS-1:0]    curTag,

    output logic                  cacheWe,
    output logic [WAY_BITS-1:0]   cacheWrWay,

    output logic                  dirtyWe,
    output logic                  dirtyWrData,

    output logic                  lruWe,
    output logic [WAY_BITS-1:0]   lruWrWay,

    output logic                  memReadReqR,
    output logic                  memWriteReqR,
    output logic [31:0]           memAddrR,
    output logic [DATA_WIDTH-1:0] memDataOutR,

    output logic                  selectCacheRd,
    output logic                  selectMemRd,
    output logic                  selectCacheWr,
    output logic                  selectMemWr,

    output logic                  loadDone,
    output logic                  storeDrainDone,
    output logic                  curDrain,
    output logic                  controllerIdle
);
    logic 					drainActive;

    logic [WAY_BITS-1:0]   	savedAllocWay;
    logic [TAG_BITS-1:0]   	savedEvictTag;
    logic [DATA_WIDTH-1:0] 	savedEvictData;

    logic                  	memReadReqNext;
    logic                  	memWriteReqNext;
    logic [31:0]           	memAddrNext;
    logic [DATA_WIDTH-1:0] 	memDataOutNext;

    logic                  	saveMissInfoWe;
    logic [WAY_BITS-1:0]   	saveAllocWay;
    logic [TAG_BITS-1:0]   	saveEvictTag;
    logic [DATA_WIDTH-1:0] 	saveEvictData;

    typedef enum logic [1:0] {
        IDLE,
        LOOKUP,
        WRITEBACK,
        FETCH
    } state;

    state currentState, nextState;


    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            currentState <= IDLE;
        end else begin
            currentState <= nextState;
        end
    end

    always_comb begin
        nextState = currentState;

        case (currentState)
            IDLE: begin
                if (cacheReadReq | !storeBufEmpty)
                    nextState = LOOKUP;
            end
            LOOKUP: begin
                if (!(drainActive | cacheReadReq) | hit)
                    nextState = IDLE;
                else if (allocValid & allocDirty)
                    nextState = WRITEBACK;
                else
                    nextState = FETCH;
            end

            WRITEBACK: begin
                if (!memWaitReq)
                    nextState = FETCH;
                else
                    nextState = WRITEBACK;
            end

            FETCH: begin
                if (!memWaitReq)
                    nextState = IDLE;
                else
                    nextState = FETCH;
            end

            default: nextState = IDLE;
        endcase
    end

    always_comb begin
        curDrain       = 1'b0;
        controllerIdle = 1'b0;

        selectCacheRd = 1'b0;
        selectMemRd   = 1'b0;
        selectCacheWr = 1'b0;
        selectMemWr   = 1'b0;

        cacheWe      = 1'b0;
        cacheWrWay   = '0;

        dirtyWe     = 1'b0;
        dirtyWrData = 1'b0;

        lruWe     = 1'b0;
        lruWrWay  = '0;

        memReadReqNext  = 1'b0;
        memWriteReqNext = 1'b0;
        memAddrNext     = memAddrR;
        memDataOutNext  = memDataOutR;

        saveMissInfoWe = 1'b0;
        saveAllocWay   = allocWay;
        saveEvictTag   = allocTag;
        saveEvictData  = allocData;

        loadDone       = 1'b0;
        storeDrainDone = 1'b0;

        case (currentState)
            IDLE: begin
                controllerIdle = 1'b1;

                if (cacheReadReq)
                    curDrain = 1'b0;
                else if (!storeBufEmpty)
                    curDrain = 1'b1;
            end

            LOOKUP: begin
                curDrain = drainActive;

                if (drainActive || cacheReadReq) begin
                    if (hit) begin
                        lruWe    = 1'b1;
                        lruWrWay = accessedWay;

                        if (!drainActive) begin
                            selectCacheRd = 1'b1;
                            loadDone      = 1'b1;
                        end else begin
                            selectCacheWr  = 1'b1;
                            cacheWe        = 1'b1;
                            cacheWrWay     = accessedWay;
                            dirtyWe        = 1'b1;
                            dirtyWrData    = 1'b1;
                            storeDrainDone = 1'b1;
                        end
                    end else begin
                        saveMissInfoWe = 1'b1;
                        saveAllocWay   = allocWay;
                        saveEvictTag   = allocTag;
                        saveEvictData  = allocData;

                        if (allocValid && allocDirty) begin
                            memWriteReqNext = 1'b1;
                            memAddrNext     = {allocTag, curIndex, {(WORD_OFFSET_BITS+ALIGN_BITS){1'b0}}};
                            memDataOutNext  = allocData;
                        end else begin
                            memReadReqNext = 1'b1;
                            memAddrNext    = {curTag, curIndex, {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                        end
                    end
                end
            end

            WRITEBACK: begin
                curDrain = drainActive;

                if (!memWaitReq) begin
                    memReadReqNext = 1'b1;
                    memAddrNext    = {curTag, curIndex, {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                end else begin
                    memWriteReqNext = 1'b1;
                    memAddrNext     = {savedEvictTag, curIndex, {(WORD_OFFSET_BITS+ALIGN_BITS){1'b0}}};
                    memDataOutNext  = savedEvictData;
                end
            end

            FETCH: begin
                curDrain = drainActive;

                if (!memWaitReq) begin
                    cacheWe    = 1'b1;
                    cacheWrWay = savedAllocWay;

                    if (drainActive) begin
                        selectMemWr    = 1'b1;
                        dirtyWe        = 1'b1;
                        dirtyWrData    = 1'b1;
                        storeDrainDone = 1'b1;
                    end else begin
                        selectMemRd = 1'b1;
                        dirtyWe     = 1'b1;
                        dirtyWrData = 1'b0;
                        loadDone    = 1'b1;
                    end

                    lruWe    = 1'b1;
                    lruWrWay = savedAllocWay;
                end else begin
                    memReadReqNext = 1'b1;
                    memAddrNext    = {curTag, curIndex, {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                end
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            drainActive  	<= 1'b0;
            memReadReqR    	<= 1'b0;
            memWriteReqR   	<= 1'b0;
            memAddrR       	<= 32'b0;
            memDataOutR    	<= {DATA_WIDTH{1'b0}};

            savedAllocWay  	<= '0;
            savedEvictTag  	<= '0;
            savedEvictData 	<= {DATA_WIDTH{1'b0}};
        end else begin
            memReadReqR  	<= memReadReqNext;
            memWriteReqR 	<= memWriteReqNext;
            memAddrR     	<= memAddrNext;
            memDataOutR  	<= memDataOutNext;

            if (saveMissInfoWe) begin
                savedAllocWay  	<= saveAllocWay;
                savedEvictTag  	<= saveEvictTag;
                savedEvictData 	<= saveEvictData;
            end
            if (controllerIdle)
                drainActive 	<= ~cacheReadReq & ~storeBufEmpty;
        end
    end

endmodule