////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheAtomic.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-10-07
//
// Description:
//
////////////////////////////////////////////////////////////////////////////////
module data_cache_atomic (
    input  wire         clk,
    input  wire         rst,

    input  wire         core0ReadReq,
    input  wire         core0WriteReq,
    input  wire  [ 1:0] core0AccessType,
    input  wire         core0Atomic,
    input  wire  [ 4:0] core0AtomicOpcode,
    input  wire  [31:0] core0Address,
    input  wire  [31:0] core0WriteData,
    output logic        core0WaitReq,
    output logic [31:0] core0ReadData,

    input  wire         core1ReadReq,
    input  wire         core1WriteReq,
    input  wire  [ 1:0] core1AccessType,
    input  wire         core1Atomic,
    input  wire  [ 4:0] core1AtomicOpcode,
    input  wire  [31:0] core1Address,
    input  wire  [31:0] core1WriteData,
    output logic        core1WaitReq,
    output logic [31:0] core1ReadData,

    output logic        cacheReadReq0,
    output logic        cacheWriteReq0,
    output logic [ 1:0] cacheAccessType0,
    output logic [31:0] cacheAddress0,
    output logic [31:0] cacheWriteData0,
    input  wire         cacheWaitReq0,
    input  wire  [31:0] cacheReadData0,

    output logic        cacheReadReq1,
    output logic        cacheWriteReq1,
    output logic [ 1:0] cacheAccessType1,
    output logic [31:0] cacheAddress1,
    output logic [31:0] cacheWriteData1,
    input  wire         cacheWaitReq1,
    input  wire  [31:0] cacheReadData1
);

    localparam logic [1:0] ACCESS_WORD = 2'b10;

    localparam logic [4:0] OP_LR  	= 5'b00010;
    localparam logic [4:0] OP_SC  	= 5'b00011;

    localparam logic [31:0] SUCCESS = 32'b0; //success
    localparam logic [31:0] FAILURE	= 32'b1; // failure

    wire  normalReq0;
    wire  normalReq1;
    wire  canStart0;
    wire  canStart1;
    wire  grant0;
    wire  grant1;
    wire  atomicStart;
	logic atomicIdle;

    assign normalReq0 	= core0ReadReq | core0WriteReq;
    assign normalReq1 	= core1ReadReq | core1WriteReq;

    assign canStart0 	= atomicIdle & core0Atomic & ~cacheWaitReq0 & ~cacheWaitReq1 & ~normalReq1;
    assign canStart1 	= atomicIdle & core1Atomic & ~cacheWaitReq0 & ~cacheWaitReq1 & ~normalReq0;

    assign grant0 		= canStart0;
    assign grant1 		= canStart1 & ~canStart0;

    assign atomicStart 	= grant0 | grant1;

    logic        ownerR;
    logic [ 4:0] atomicOpcodeR;
    logic [31:0] addressR;
    logic [31:0] dataR;
    logic [31:0] atomicResult;

    logic        ownerWaitReq;

	wire [4:0] 	atomicStartOpcode;
    assign 		atomicStartOpcode =	grant0 ? core0AtomicOpcode : core1AtomicOpcode;


    logic 	scSuccessR;
    wire 	transactionLR;
    wire 	transactionSC;

    assign 	transactionLR = (atomicOpcodeR == OP_LR);
    assign	transactionSC = (atomicOpcodeR == OP_SC);

    logic 	atomicALUEn;
	logic 	storeReadData;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ownerR        <= 1'b0;
			atomicOpcodeR <= 5'b0;
            addressR      <= 32'b0;
            dataR         <= 32'b0;
        end else begin
            if (atomicStart) begin
				if (grant1)
                	ownerR <= 1'b1;
				else if (grant0)
                	ownerR <= 1'b0;

                if (grant0) begin
                	atomicOpcodeR <= core0AtomicOpcode;
                    addressR      <= core0Address;
                    dataR         <= core0WriteData;
                end else if (grant1) begin
                	atomicOpcodeR <= core1AtomicOpcode;
                    addressR      <= core1Address;
                    dataR         <= core1WriteData;
                end
            end
        end
    end
	
	assign 	ownerWaitReq = ownerR ? cacheWaitReq1 : cacheWaitReq0;

    logic [31:0] oldDataR;
	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
            oldDataR <= 32'b0;
		end else if (storeReadData) begin
			oldDataR <= ownerR ? cacheReadData1 : cacheReadData0;
		end
	end

	logic 			core0ResValid;
	logic			core1ResValid;
    logic [29:0]	core0ResAddr;
	logic [29:0]  	core1ResAddr;

    wire 	core0SCStart;
    wire 	core1SCStart;

    assign 	core0SCStart = atomicStart & grant0 & (atomicStartOpcode == OP_SC);

    assign 	core1SCStart = atomicStart & grant1 & (atomicStartOpcode == OP_SC);

	logic 	core0LRCommit;
	logic 	core1LRCommit;

	wire	cacheWriteComplete0;
	assign 	cacheWriteComplete0 = cacheWriteReq0 & ~cacheWaitReq0;

	wire	cacheWriteComplete1;
	assign 	cacheWriteComplete1 = cacheWriteReq1 & ~cacheWaitReq1;

    data_cache_atomic_lrsc lrsc (
        .clk                (clk),
        .rst                (rst),

        .core0LRCommit      (core0LRCommit),
        .core1LRCommit      (core1LRCommit),

        .core0SCStart       (core0SCStart),
        .core1SCStart       (core1SCStart),
        .core0SCAddress     (core0Address),
        .core1SCAddress     (core1Address),

        .lrAddressR         (addressR),

        .cacheWriteComplete0(cacheWriteComplete0),
        .cacheWriteComplete1(cacheWriteComplete1),
        .cacheAddress0      (cacheAddress0),
        .cacheAddress1      (cacheAddress1),

        .scSuccessR         (scSuccessR),

        .core0ResValid      (core0ResValid),
        .core0ResAddr       (core0ResAddr),
        .core1ResValid      (core1ResValid),
        .core1ResAddr       (core1ResAddr)
    );



    typedef enum logic [1:0] {
        IDLE,
        READ,
        WRITE
    } state;
    state currentState, nextState;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            currentState <= IDLE;
        else
            currentState <= nextState;
    end

    always_comb begin
        nextState = currentState;
        unique0 case (currentState)
            IDLE: begin
                if (atomicStart) begin
					if (atomicStartOpcode == OP_SC) begin
                    	nextState = WRITE;
					end else begin
                    	nextState = READ;
					end
				end
            end
            READ: begin
                if (~ownerWaitReq) begin
					if (transactionLR) begin
                    	nextState = IDLE;
					end else begin
                    	nextState = WRITE;
					end
				end
            end
            WRITE: begin
                if (~ownerWaitReq)
                    nextState = IDLE;
            end
        endcase
    end

    always_comb begin
		storeReadData	 = 1'b0;
		atomicALUEn		 = 1'b0;
		atomicIdle		 = 1'b0;
						
		core0LRCommit	 = 1'b0; 
		core1LRCommit	 = 1'b0; 

        cacheReadReq0    = core0ReadReq;
        cacheWriteReq0   = core0WriteReq;
        cacheAccessType0 = core0AccessType;
        cacheAddress0    = core0Address;
        cacheWriteData0  = core0WriteData;

        cacheReadReq1    = core1ReadReq;
        cacheWriteReq1   = core1WriteReq;
        cacheAccessType1 = core1AccessType;
        cacheAddress1    = core1Address;
        cacheWriteData1  = core1WriteData;

        core0WaitReq 	= cacheWaitReq0;
        core1WaitReq 	= cacheWaitReq1;

        core0ReadData 	= cacheReadData0;
        core1ReadData 	= cacheReadData1;

        unique0 case (currentState)
            IDLE: begin
				atomicIdle 		 = 1'b1;

                if (core0Atomic) begin
                    core0WaitReq = 1'b1;
					if (normalReq1) begin
                    	core0WaitReq = 1'b1;
					end
				end
                if (core1Atomic) begin
                    core1WaitReq = 1'b1;
					if (normalReq0) begin
                    	core1WaitReq = 1'b1;
					end
				end
            end

            READ: begin
                cacheReadReq0    = 1'b0;
                cacheWriteReq0   = 1'b0;

                cacheReadReq1    = 1'b0;
                cacheWriteReq1   = 1'b0;

                core0WaitReq 	 = core0ReadReq | core0WriteReq | core0Atomic;
                core1WaitReq  	 = core1ReadReq | core1WriteReq | core1Atomic;

                if (~ownerR) begin
                    cacheReadReq0    	= 1'b1;
                    cacheAccessType0 	= ACCESS_WORD;
                    cacheAddress0    	= addressR;
                end else begin
                    cacheReadReq1    	= 1'b1;
                    cacheAccessType1 	= ACCESS_WORD;
                    cacheAddress1    	= addressR;
                end
				if (~ownerWaitReq) begin
					if (transactionLR) begin
						if (~ownerR) begin
                    		core0WaitReq 	= ownerWaitReq;
							core0LRCommit	= 1'b1; 
						end else begin
                    		core1WaitReq 	= ownerWaitReq;
							core1LRCommit	= 1'b1; 
						end
					end else begin
						storeReadData = 1'b1; 
					end
				end
            end

            WRITE: begin
                if (~transactionSC)
                    atomicALUEn  = 1'b1;

                cacheReadReq0    = 1'b0;
                cacheWriteReq0   = 1'b0;

                cacheReadReq1    = 1'b0;
                cacheWriteReq1   = 1'b0;

                core0WaitReq 	 = core0ReadReq | core0WriteReq | core0Atomic;
                core1WaitReq 	 = core1ReadReq | core1WriteReq | core1Atomic;


                if (~ownerR) begin
                    if (transactionSC) begin
                        if (scSuccessR) begin
                            cacheWriteReq0   = 1'b1;
                            cacheAccessType0 = ACCESS_WORD;
                            cacheAddress0    = addressR;
                            cacheWriteData0  = dataR;
                            core0WaitReq  	 = ownerWaitReq;
                            core0ReadData 	 = 32'b0;       // SC success
                        end else begin
                            core0WaitReq  	 = 1'b0;
                            core0ReadData 	 = 32'b1;       // SC failure
                        end
                    end else begin
                        // AMO
                        cacheWriteReq0   = 1'b1;
                        cacheAccessType0 = ACCESS_WORD;
                        cacheAddress0    = addressR;
                        cacheWriteData0  = atomicResult;

                        core0WaitReq  	 = ownerWaitReq;
                        core0ReadData 	 = oldDataR;
                    end
                end
                else begin
                    if (transactionSC) begin
                        if (scSuccessR) begin
                            cacheWriteReq1   = 1'b1;
                            cacheAccessType1 = ACCESS_WORD;
                            cacheAddress1    = addressR;
                            cacheWriteData1  = dataR;

                            core1WaitReq  	 = ownerWaitReq;
                            core1ReadData 	 = SUCCESS;

                        end else begin
                            core1WaitReq  	 = 1'b0;
                            core1ReadData 	 = FAILURE;
                        end
                    end else begin
                        // AMO
                        cacheWriteReq1   = 1'b1;
                        cacheAccessType1 = ACCESS_WORD;
                        cacheAddress1    = addressR;
                        cacheWriteData1  = atomicResult;

                        core1WaitReq  	 = ownerWaitReq;
                        core1ReadData 	 = oldDataR;
                    end
                end
            end
        endcase
    end

    data_cache_atomic_alu atomic_alu (
        .atomicALUEn    (atomicALUEn),
        .atomicOpcode   (atomicOpcodeR),

        .operandA       (oldDataR),
        .operandB       (dataR),

        .result         (atomicResult)
    );

endmodule
