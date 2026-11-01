////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheAtomicAlu.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-29
//
// Description:
//      AMO ALU. operandA is the value read from memory, operandB is the
//      value supplied by the master (rs2).
////////////////////////////////////////////////////////////////////////////////
module data_cache_atomic_alu (
	input  wire  		atomicALUEn,
    input  wire  [ 4:0] atomicOpcode,

    input  wire  [31:0] operandA,
    input  wire  [31:0] operandB,
    output logic [31:0] result
);
    localparam logic [4:0] OP_AMOADD  = 5'b00000;
    localparam logic [4:0] OP_AMOSWAP = 5'b00001;
    localparam logic [4:0] OP_AMOXOR  = 5'b00100;
    localparam logic [4:0] OP_AMOOR   = 5'b01000;
    localparam logic [4:0] OP_AMOAND  = 5'b01100;
    localparam logic [4:0] OP_AMOMIN  = 5'b10000;
    localparam logic [4:0] OP_AMOMAX  = 5'b10100;
    localparam logic [4:0] OP_AMOMINU = 5'b11000;
    localparam logic [4:0] OP_AMOMAXU = 5'b11100;

    always_comb begin
		result	=	32'b0;
		if (atomicALUEn) begin
        	case (atomicOpcode)
            	OP_AMOSWAP: result = 													operandB;
            	OP_AMOADD : result = 										operandA + 	operandB;
            	OP_AMOXOR : result = 										operandA ^ 	operandB;
            	OP_AMOAND : result = 										operandA & 	operandB;
            	OP_AMOOR  : result = 										operandA | 	operandB;
            	OP_AMOMIN : result = $signed(operandA) < $signed(operandB)? operandA : 	operandB;
            	OP_AMOMAX : result = $signed(operandA) > $signed(operandB)? operandA : 	operandB;
            	OP_AMOMINU: result = operandA < operandB ? 					operandA : 	operandB;
            	OP_AMOMAXU: result = operandA > operandB ? 					operandA : 	operandB;
            	default   : result = 													operandB;
        	endcase
		end
    end
endmodule
