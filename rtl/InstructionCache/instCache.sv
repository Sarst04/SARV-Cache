////////////////////////////////////////////////////////////////////////////////
// File      : instCache.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-11 (last modified)
// Description: 
// 		Instruction Cache modularized with external SRAM instantiation.
////////////////////////////////////////////////////////////////////////////////
module instCache #(
    parameter int CACHE_LINES    = 128,
    parameter int WORD_PER_LINES = 1,
    parameter int NUM_WAYS       = 2,
    parameter bit BYPASS_CACHE   = 0
)(
    input  wire        		clk,
    input  wire        		rst,

    // Core Side
    input  wire        					readReq,
    input  wire [31:0] 					address,

    output wire        					unalignedAccess,
    output logic       					waitReq,
    output logic [31:0] 				dataOut,

    // Memory Side
    input  wire        					memWaitReq,
    input  wire [32*WORD_PER_LINES-1:0] memData,

    output logic       					memReadReq,
    output logic [31:0] 				memAddress
);
    if (BYPASS_CACHE) begin

        assign memAddress      = address;
        assign memReadReq      = readReq;
        assign waitReq         = memWaitReq;
        assign dataOut         = memData[31:0];
        assign unalignedAccess = 1'b0;

    end else begin

        localparam int ALIGN_BITS       = 2;
        localparam int WORD_OFFSET_BITS = (WORD_PER_LINES == 1) ? 0 : $clog2(WORD_PER_LINES);
        localparam int HALF_WORD_WIDTH  = WORD_OFFSET_BITS + 1;
        localparam int INDEX_BITS       = $clog2(CACHE_LINES);
        localparam int TAG_BITS         = 32 - ALIGN_BITS - WORD_OFFSET_BITS - INDEX_BITS;
        localparam int WAY_BITS         = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;
        localparam int LINE_DATA_WIDTH  = 32 * WORD_PER_LINES;

        wire [HALF_WORD_WIDTH-1:0] curWord;
        assign curWord = address[1 +: HALF_WORD_WIDTH];

        if (WORD_PER_LINES == 1)
            assign unalignedAccess = (address[1:0] == 2'b10);
        else
            assign unalignedAccess = (curWord == {HALF_WORD_WIDTH{1'b1}});

        wire [INDEX_BITS-1:0] curIndex;
        assign curIndex = address[ALIGN_BITS + WORD_OFFSET_BITS +: INDEX_BITS];

        wire [TAG_BITS-1:0] curTag;
        assign curTag = address[31 : ALIGN_BITS + WORD_OFFSET_BITS + INDEX_BITS];

        logic [NUM_WAYS-1:0] 		validMem [CACHE_LINES];
        logic [WAY_BITS-1:0] 		lruPtr   [CACHE_LINES];

        logic [LINE_DATA_WIDTH-1:0] readData [0:NUM_WAYS-1];
        logic [TAG_BITS-1:0]        readTag  [0:NUM_WAYS-1];
        logic                       sramWe   [0:NUM_WAYS-1];

        logic [WAY_BITS-1:0] 		allocWay;
        logic 						storeNewData;


        for (genvar w = 0; w < NUM_WAYS; w++) begin : g_cache_ways
            
            assign sramWe[w] = storeNewData && (allocWay == WAY_BITS'(w));

            sram #(
                .DATA_WIDTH(TAG_BITS),
                .DEPTH(CACHE_LINES)
            ) tagSram (
                .clk (clk),
                .we  (sramWe[w]),
                .addr(curIndex),
                .din (curTag),
                .dout(readTag[w])
            );

            sram #(
                .DATA_WIDTH(LINE_DATA_WIDTH),
                .DEPTH(CACHE_LINES)
            ) dataSram (
                .clk (clk),
                .we  (sramWe[w]),
                .addr(curIndex),
                .din (memData),
                .dout(readData[w])
            );
        end

        logic                hit;
        logic [31:0]         hitDataOut;
        logic [WAY_BITS-1:0] accessedWay;

        always_comb begin
            hit         = 1'b0;
            hitDataOut  = 32'b0;
            accessedWay = '0;

            for (int i = 0; i < NUM_WAYS; i++) begin
                if (validMem[curIndex][i] && (readTag[i] == curTag)) begin
                    hit = 1'b1;
                    if (unalignedAccess)
                        hitDataOut = {16'b0, readData[i][curWord*16 +: 16]};
                    else
                        hitDataOut = readData[i][curWord*16 +: 32];
                    
                    accessedWay = WAY_BITS'(i);
                    break;
                end
            end
        end

        always_comb begin
            allocWay = (NUM_WAYS == 1) ? '0 : lruPtr[curIndex];

            for (int i = 0; i < NUM_WAYS; i++) begin
                if (!validMem[curIndex][i]) begin
                    allocWay = WAY_BITS'(i);
                    break;
                end
            end
        end

        logic updateLruPtr;

        always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
                for (int i = 0; i < CACHE_LINES; i++) begin
                    lruPtr[i] <= '0;
                    for (int w = 0; w < NUM_WAYS; w++) begin
                        validMem[i][w] <= 1'b0;
                    end
                end
            end else begin
                if (updateLruPtr) begin
                    lruPtr[curIndex] <= (accessedWay == WAY_BITS'(NUM_WAYS-1)) ? '0 : accessedWay + 1'b1;
                end else if (storeNewData) begin
                    validMem[curIndex][allocWay] <= 1'b1;
                    lruPtr[curIndex]             <= (allocWay == WAY_BITS'(NUM_WAYS-1)) ? '0 : allocWay + 1'b1;
                end
            end
        end

        typedef enum logic { 
            IDLE, 
            MISS_REQ 
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
            case (currentState)
                IDLE:     nextState = (readReq && !hit && memWaitReq) ? MISS_REQ : IDLE;
                MISS_REQ: nextState = (memWaitReq)                   ? MISS_REQ : IDLE;
                default:  nextState = IDLE;
            endcase
        end

        assign memAddress = {address[31 : ALIGN_BITS + WORD_OFFSET_BITS], {WORD_OFFSET_BITS{1'b0}}, {ALIGN_BITS{1'b0}}};
        
        assign dataOut = hit             ? hitDataOut :
                         unalignedAccess ? {16'b0, memData[curWord*16 +: 16]} : 
                                           memData[curWord*16 +: 32];

        always_comb begin
            waitReq      = 1'b0;
            memReadReq   = 1'b0;
            updateLruPtr = 1'b0;
            storeNewData = 1'b0;

            case (currentState)
                IDLE: begin
                    if (readReq) begin
                        if (hit) begin
                            updateLruPtr = 1'b1;
                        end else begin
                            waitReq    = memWaitReq;
                            memReadReq = 1'b1;
                        end
                    end
                end
                MISS_REQ: begin
                    waitReq    = 1'b1;
                    memReadReq = 1'b1;
                    if (!memWaitReq) begin
                        storeNewData = 1'b1;
                        waitReq      = 1'b0;
                        memReadReq   = 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
