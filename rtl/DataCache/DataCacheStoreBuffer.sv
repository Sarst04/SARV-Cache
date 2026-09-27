////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheStoreBuffer.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-24 (last modified)
// Description:
// 		
////////////////////////////////////////////////////////////////////////////////
module data_cache_store_buffer #(
    parameter int DEPTH       = 8
)(
    input  wire         clk,
    input  wire         rst,

    input  wire         push,
    input  wire [31:0]  pushAddr,
    input  wire [31:0]  pushData,
    input  wire [ 1:0]  pushType,

    input  wire         pop,

    output wire         empty,
    output wire         full,
    output wire  [31:0]	headAddr,
    output wire  [31:0]	headData,
    output wire  [ 1:0]	headType,

    input  wire  [31:0]	fwdAddr,
    input  wire  [31:0]	fwdBase,
    output logic [31:0]	fwdWord
);
	localparam int  		PTR_WIDTH   = (DEPTH > 1) ? $clog2(DEPTH) : 1 ;
	localparam int			COUNT_WIDTH = $clog2(DEPTH + 1);

	localparam logic [1:0] 	BYTE = 2'b00;
	localparam logic [1:0] 	HALF = 2'b01;
	localparam logic [1:0] 	WORD = 2'b10;

    logic [31:0] bufAddr [DEPTH];
    logic [31:0] bufData [DEPTH];
    logic [ 1:0] bufType [DEPTH];

    logic [PTR_WIDTH-1:0]   head;
    logic [PTR_WIDTH-1:0]   tail;
    logic [COUNT_WIDTH-1:0]count;

    assign empty = (count == '0);
    assign full  = (count == COUNT_WIDTH'(DEPTH));

    assign headAddr = bufAddr[head];
    assign headData = bufData[head];
    assign headType = bufType[head];

	always_ff @(posedge clk or posedge rst) begin
    	if (rst) begin
        	for (int i = 0; i < DEPTH; i++) begin
            	bufAddr[i] <= '0;
            	bufData[i] <= '0;
            	bufType[i] <= '0;
        	end
    	end else if (push) begin
        	bufAddr[tail] <= pushAddr;
        	bufData[tail] <= pushData;
        	bufType[tail] <= pushType;
    	end
	end
    
	always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
        end else begin
            if (push)
                tail <= (tail == PTR_WIDTH'(DEPTH-1)) ? '0 : tail + 1'b1;

            if (pop)
                head <= (head == PTR_WIDTH'(DEPTH-1)) ? '0 : head + 1'b1;

            case ({push, pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
            endcase
        end
    end
	
	always_comb begin
    	fwdWord = fwdBase;

    	for (int i = 0; i < DEPTH; i++) begin
        	int idx;

        	idx = head + i;
        	if (idx >= DEPTH)
            	idx = idx - DEPTH;

        	if ((i < count) && (bufAddr[idx][31:2] == fwdAddr[31:2])) begin
            	case (bufType[idx])
                	BYTE: fwdWord[bufAddr[idx][1:0]*8 +: 8] =  bufData[idx][7:0];
                	HALF: fwdWord[bufAddr[idx][1:0]*8 +: 16] = bufData[idx][15:0];
                	WORD: fwdWord = bufData[idx];
            	endcase
        	end
   		end
	end

endmodule

