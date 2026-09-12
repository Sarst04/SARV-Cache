////////////////////////////////////////////////////////////////////////////////
// File      : dataCache.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-11 (last modified)
// Description: Data Cache modularized with external SRAM instantiation.
////////////////////////////////////////////////////////////////////////////////
module dataCache #(
    parameter int CACHE_LINES    = 128,
    parameter int NUM_WAYS       = 4,
    parameter int WORD_PER_LINES = 1,
    parameter bit BYPASS_CACHE   = 0,

    parameter logic [31:0] MEM_BASE = 32'h8000_0000,
    parameter logic [31:0] MEM_END  = 32'h8F00_0000
)(
    input  wire          clk,
    input  wire          rst,

    // Core Side
    input  wire          					readReq,
    input  wire          					writeReq,
    input  wire  [ 1:0] 					accessType,
    output logic        					waitReq,

    input  wire  [31:0] 					address,
    input  wire  [31:0] 					dataIn,
    output logic [31:0] 					dataOut,

    // Memory Side
    input  wire          					memWaitReq,
    output logic        					memReadReq,
    output logic        					memWriteReq,
    output logic [ 1:0] 					memAccessType,

    input  wire  [32*WORD_PER_LINES-1:0]	memDataIn,
    output logic [31:0]                  	memAddress,
    output logic [32*WORD_PER_LINES-1:0] 	memDataOut
);

    if (BYPASS_CACHE) begin : bypass
        
        assign memReadReq    = readReq;
        assign memWriteReq   = writeReq;
        assign memAddress    = address;
        assign memDataOut    = {{(32*WORD_PER_LINES-32){1'b0}}, dataIn};
        assign memAccessType = accessType;
        
        assign dataOut = memDataIn[31:0];
        assign waitReq = memWaitReq;
        
    end else begin : cache
    
        localparam int DATA_WIDTH = 32 * WORD_PER_LINES;

        logic 	isPeripheralAccess;
        assign 	isPeripheralAccess = (address < MEM_BASE) | (address > MEM_END);

        logic        cacheReadReq;
        logic        cacheWriteReq;
        logic [31:0] cacheDataOut;
        logic        cacheWaitReq;

        assign cacheReadReq  = readReq  & ~isPeripheralAccess;
        assign cacheWriteReq = writeReq & ~isPeripheralAccess;

        localparam int ALIGN_BITS       = 2;
        localparam int WORD_OFFSET_BITS = (WORD_PER_LINES == 1) ? 0 : $clog2(WORD_PER_LINES);
        localparam int INDEX_BITS       = $clog2(CACHE_LINES);
        localparam int TAG_BITS         = 32 - ALIGN_BITS - WORD_OFFSET_BITS - INDEX_BITS;
        localparam int WAY_BITS         = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;

        localparam int WORD_OFFSET_WIDTH = (WORD_OFFSET_BITS == 0) ? 1 : WORD_OFFSET_BITS;

        wire [WORD_OFFSET_WIDTH-1:0] curWordOffset;
        if (WORD_PER_LINES == 1) begin : gen_word_offset_single
            assign curWordOffset = '0;
        end else begin : gen_word_offset_multi
            assign curWordOffset = address[ALIGN_BITS +: WORD_OFFSET_BITS];
        end

        wire [INDEX_BITS-1:0] curIndex = address[ALIGN_BITS + WORD_OFFSET_BITS +: INDEX_BITS];
        wire [TAG_BITS-1:0]   curTag   = address[31 : ALIGN_BITS + WORD_OFFSET_BITS + INDEX_BITS];
        wire [1:0]            curOff   = address[1:0];


        logic 					validMem [NUM_WAYS-1:0][CACHE_LINES];
        logic 					dirtyMem [NUM_WAYS-1:0][CACHE_LINES];
        logic [WAY_BITS-1:0] 	lruPtr [CACHE_LINES];


        logic [NUM_WAYS-1:0]                 readValid;
        logic [NUM_WAYS-1:0][TAG_BITS-1:0]   readTag;
        logic [NUM_WAYS-1:0][DATA_WIDTH-1:0] readData;
        logic [NUM_WAYS-1:0]                 readDirty;
        logic [WAY_BITS-1:0]                 readLru;

        logic                	cacheWe;
        logic [WAY_BITS-1:0] 	cacheWrWay;
        logic [INDEX_BITS-1:0] 	cacheWrIndex;
        logic [TAG_BITS-1:0] 	cacheWrTag;
        logic [DATA_WIDTH-1:0] 	cacheWrData;

        for (genvar w = 0; w < NUM_WAYS; w++) begin : cache_ways
            logic 	sramWe;
            assign 	sramWe = cacheWe && (cacheWrWay == WAY_BITS'(w));

            sram #(
                .DATA_WIDTH(TAG_BITS),
                .DEPTH(CACHE_LINES)
            ) tagSram (
                .clk (clk),
                .we  (sramWe),
                .addr(cacheWrIndex),
                .din (cacheWrTag),
                .dout(readTag[w])
            );

            sram #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(CACHE_LINES)
            ) dataSram (
                .clk (clk),
                .we  (sramWe),
                .addr(cacheWrIndex),
                .din (cacheWrData),
                .dout(readData[w])
            );
        end

        always_comb begin
            readValid = '0;
            readDirty = '0;
            readLru   = '0;
            
            if (cacheReadReq || cacheWriteReq) begin
                for (int i = 0; i < NUM_WAYS; i++) begin
                    readValid[i] = validMem[i][curIndex];
                    readDirty[i] = dirtyMem[i][curIndex];
                end
                readLru = lruPtr[curIndex];
            end
        end

        logic                hit;
        logic [WAY_BITS-1:0] accessedWay;
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

        logic [WAY_BITS-1:0] allocWay;
        always_comb begin
            allocWay = (NUM_WAYS == 1) ? '0 : readLru;
            for (int i = 0; i < NUM_WAYS; i++) begin
                if (!readValid[i]) begin
                    allocWay = WAY_BITS'(i);
                    break;
                end
            end
        end

        logic selectCacheRd;
        logic selectMemRd;
        logic selectCacheWr;
        logic selectMemWr;

        logic [31:0] dataOutBase;
        logic [31:0] mergeBaseData;
        logic [31:0] mergedWrData;

        always_comb begin
            dataOutBase   = 32'b0;
            mergeBaseData = 32'b0;

            if (selectCacheRd)      
                dataOutBase = readData[accessedWay][curWordOffset*32 +: 32];
            else if (selectMemRd)   
                dataOutBase = memDataIn[curWordOffset*32 +: 32];

            if (selectCacheWr)      
                mergeBaseData = readData[accessedWay][curWordOffset*32 +: 32];
            else if (selectMemWr)   
                mergeBaseData = memDataIn[curWordOffset*32 +: 32];
        end

        always_comb begin
            cacheDataOut = 32'b0;
            case (accessType)
                2'b00: cacheDataOut = {24'b0, dataOutBase[curOff*8 +: 8]};
                2'b01: cacheDataOut = {16'b0, dataOutBase[curOff*8 +: 16]};
                2'b10: cacheDataOut = dataOutBase;
                default: cacheDataOut = 32'b0;
            endcase
        end

        always_comb begin
            mergedWrData = mergeBaseData;
            case (accessType)
                2'b00: mergedWrData[curOff*8 +: 8]  = dataIn[7:0];
                2'b01: mergedWrData[curOff*8 +: 16] = dataIn[15:0];
                2'b10: mergedWrData                 = dataIn;
                default: ;
            endcase
        end

        logic                	memReadReqR;
        logic                 	memWriteReqR;
        logic [31:0]          	memAddrR;
        logic [DATA_WIDTH-1:0] 	memDataOutR;

        logic [WAY_BITS-1:0]  	savedAllocWay;
        logic [TAG_BITS-1:0]  	savedEvictTag;
        logic [DATA_WIDTH-1:0] 	savedEvictData;

        logic                 	dirtyWe;
        logic                 	dirtyWrData;
        logic                 	lruWe;
        logic [WAY_BITS-1:0]  	lruWrData;

        logic                 	memReadReqNext;
        logic                 	memWriteReqNext;
        logic [31:0]          	memAddrNext;
        logic [DATA_WIDTH-1:0] 	memDataOutNext;
        logic                 	saveMissInfoWe;
        logic [WAY_BITS-1:0]  	saveAllocWay;
        logic [TAG_BITS-1:0]  	saveEvictTag;
        logic [DATA_WIDTH-1:0] 	saveEvictData;

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                for (int i = 0; i < CACHE_LINES; i++) begin
                    lruPtr[i] <= '0;
                end
                for (int w = 0; w < NUM_WAYS; w++) begin
                    for (int i = 0; i < CACHE_LINES; i++) begin
                        validMem[w][i] <= 1'b0;
                        dirtyMem[w][i] <= 1'b0;
                    end
                end
            end else begin
                if (cacheWe) begin
                    validMem[cacheWrWay][cacheWrIndex] <= 1'b1;
                end
                if (dirtyWe) begin
                    dirtyMem[cacheWrWay][cacheWrIndex] <= dirtyWrData;
                end
                if (lruWe) begin
                    lruPtr[cacheWrIndex] <= lruWrData;
                end
            end
        end

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                memReadReqR    <= 1'b0;
                memWriteReqR   <= 1'b0;
                memAddrR       <= 32'b0;
                memDataOutR    <= {DATA_WIDTH{1'b0}};
                savedAllocWay  <= '0;
                savedEvictTag  <= '0;
                savedEvictData <= {DATA_WIDTH{1'b0}};
            end else begin
                memReadReqR   <= memReadReqNext;
                memWriteReqR  <= memWriteReqNext;
                memAddrR      <= memAddrNext;
                memDataOutR   <= memDataOutNext;
                if (saveMissInfoWe) begin
                    savedAllocWay  <= saveAllocWay;
                    savedEvictTag  <= saveEvictTag;
                    savedEvictData <= saveEvictData;
                end
            end
        end

        typedef enum logic [1:0] {
            IDLE,
            WRITEBACK,
            FETCH
        } state_e;

        state_e currentState, nextState;

        always_ff @(posedge clk or posedge rst) begin
            if (rst)
                currentState <= IDLE;
            else
                currentState <= nextState;
        end

        always_comb begin
            nextState = currentState;
            unique case (currentState)
                IDLE: begin
                    if (cacheReadReq || cacheWriteReq) begin
                        if (hit) begin
                            nextState = IDLE;
                        end else begin
                            if (readValid[allocWay] && readDirty[allocWay])
                                nextState = WRITEBACK;
                            else
                                nextState = FETCH;
                        end
                    end else begin
                        nextState = IDLE;
                    end
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
            endcase
        end

        always_comb begin
            cacheWe         = 1'b0;
            cacheWrWay      = '0;
            cacheWrIndex    = curIndex;
            cacheWrTag      = curTag;
            cacheWrData     = {DATA_WIDTH{1'b0}};
            dirtyWe         = 1'b0;
            dirtyWrData     = 1'b0;
            lruWe           = 1'b0;
            lruWrData       = '0;

            memReadReqNext  = 1'b0;
            memWriteReqNext = 1'b0;
            memAddrNext     = memAddrR;
            memDataOutNext  = memDataOutR;

            saveMissInfoWe = 1'b0;
            saveAllocWay   = allocWay;
            saveEvictTag   = readTag[allocWay];
            saveEvictData  = readData[allocWay];

            selectCacheRd = 1'b0;
            selectMemRd   = 1'b0;
            selectCacheWr = 1'b0;
            selectMemWr   = 1'b0;

            cacheWaitReq = 1'b0;

            unique case (currentState)
                IDLE: begin
                    if (cacheReadReq || cacheWriteReq) begin
                        if (hit) begin
                            lruWe      = 1'b1;
                            lruWrData  = (accessedWay == WAY_BITS'(NUM_WAYS-1)) ? '0 : accessedWay + 1'b1;
                            if (cacheReadReq) begin
                                selectCacheRd = 1'b1;
                            end
                            if (cacheWriteReq) begin
                                selectCacheWr = 1'b1;
                                cacheWe       = 1'b1;
                                cacheWrWay    = accessedWay;
                                cacheWrIndex  = curIndex;
                                cacheWrTag    = curTag;
                                cacheWrData   = readData[accessedWay];
                                cacheWrData[curWordOffset*32 +: 32] = mergedWrData;
                                dirtyWe       = 1'b1;
                                dirtyWrData   = 1'b1;
                            end
                        end else begin
                            cacheWaitReq = 1'b1;
                            saveMissInfoWe = 1'b1;
                            saveAllocWay   = allocWay;
                            saveEvictTag   = readTag[allocWay];
                            saveEvictData  = readData[allocWay];

                            if (readValid[allocWay] && readDirty[allocWay]) begin
                                memWriteReqNext = 1'b1;
                                memAddrNext     = {readTag[allocWay], curIndex, {(WORD_OFFSET_BITS+ALIGN_BITS){1'b0}}};
                                memDataOutNext  = readData[allocWay];
                            end else begin
                                memReadReqNext = 1'b1;
                                memAddrNext    = {address[31 : ALIGN_BITS + WORD_OFFSET_BITS], {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                            end
                        end
                    end
                end

                WRITEBACK: begin
                    cacheWaitReq = 1'b1;
                    if (!memWaitReq) begin
                        memReadReqNext 	= 1'b1;
                        memAddrNext    	= {address[31 : ALIGN_BITS + WORD_OFFSET_BITS], {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                    end else begin
                        memWriteReqNext = 1'b1;
                        memAddrNext     = {savedEvictTag, curIndex, {(WORD_OFFSET_BITS+ALIGN_BITS){1'b0}}};
                        memDataOutNext  = savedEvictData;
                    end
                end

                FETCH: begin
                    cacheWaitReq = 1'b1;
                    if (!memWaitReq) begin
                        cacheWe      = 1'b1;
                        cacheWrWay   = savedAllocWay;
                        cacheWrIndex = curIndex;
                        cacheWrTag   = curTag;
                        
                        if (cacheWriteReq) begin
                            selectMemWr = 1'b1;
                            cacheWrData = memDataIn;
                            cacheWrData[curWordOffset*32 +: 32] = mergedWrData;
                            dirtyWe     = 1'b1;
                            dirtyWrData = 1'b1;
                        end else begin
                            selectMemRd = 1'b1;
                            cacheWrData = memDataIn;
                            dirtyWe     = 1'b1;
                            dirtyWrData = 1'b0;
                        end
                        
                        lruWe      = 1'b1;
                        lruWrData  = (savedAllocWay == WAY_BITS'(NUM_WAYS-1)) ? '0 : savedAllocWay + 1'b1;
                    end else begin
                        memReadReqNext = 1'b1;
                        memAddrNext    = {address[31 : ALIGN_BITS + WORD_OFFSET_BITS], {(ALIGN_BITS+WORD_OFFSET_BITS){1'b0}}};
                    end
                end
            endcase
        end

        assign memReadReq    = isPeripheralAccess ? readReq         : memReadReqR;
        assign memWriteReq   = isPeripheralAccess ? writeReq   		: memWriteReqR;
        assign memAddress    = isPeripheralAccess ? address        	: memAddrR;
        assign memDataOut    = isPeripheralAccess ? {{(DATA_WIDTH-32){1'b0}}, dataIn } : memDataOutR;
        assign memAccessType = isPeripheralAccess ? accessType     	: 2'b10;

        assign dataOut       = isPeripheralAccess ? memDataIn[31:0] : cacheDataOut;
        assign waitReq       = isPeripheralAccess ? memWaitReq      : cacheWaitReq;
    end 
endmodule
