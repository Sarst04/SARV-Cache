////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheArbiter.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-27
//
// Description:
//   Two-master arbiter for the shared data cache.
//
////////////////////////////////////////////////////////////////////////////////

module data_cache_arbiter (
    input  wire         clk,
    input  wire         rst,

    // Master 0
    input  wire         readReq0,
    input  wire         writeReq0,
    input  wire [1:0]   accessType0,
    input  wire [31:0]  address0,
    input  wire [31:0]  dataIn0,

    output logic        waitReq0,
    output logic [31:0] dataOut0,

    // Master 1
    input  wire         readReq1,
    input  wire         writeReq1,
    input  wire [1:0]   accessType1,
    input  wire [31:0]  address1,
    input  wire [31:0]  dataIn1,

    output logic        waitReq1,
    output logic [31:0] dataOut1,

    // Shared cache side
    output logic        readReq,
    output logic        writeReq,
    output logic [1:0]  accessType,
    output logic [31:0] address,
    output logic [31:0] dataIn,

    input  wire         waitReq,
    input  wire [31:0]  dataOut
);

    logic req0;
    logic req1;

    assign req0 = readReq0 | writeReq0;
    assign req1 = readReq1 | writeReq1;

    logic sel; 		// Who is selected right now ?
    logic locked;	// IS arbiter free to choose ?
    logic lockedSel;// Which master owns the locked transaction ?
    logic lastGrant;// Who is last selected master ?

    always_comb begin
        if (locked) begin
            sel = lockedSel;
        end else if (req0 && req1) begin
            sel = ~lastGrant;
        end else begin
            sel = req1;
        end
    end

    always_comb begin
        if (sel) begin
            readReq    = readReq1;
            writeReq   = writeReq1;
            accessType = accessType1;
            address    = address1;
            dataIn     = dataIn1;
        end else begin
            readReq    = readReq0;
            writeReq   = writeReq0;
            accessType = accessType0;
            address    = address0;
            dataIn     = dataIn0;
        end
    end

    always_comb begin
        if (!req0) begin
            waitReq0 = 1'b0;
        end else if (sel == 1'b0) begin
            waitReq0 = waitReq;
        end else begin
            waitReq0 = 1'b1;
        end

        if (!req1) begin
            waitReq1 = 1'b0;
        end else if (sel == 1'b1) begin
            waitReq1 = waitReq;
        end else begin
            waitReq1 = 1'b1;
        end
    end

    assign dataOut0 = dataOut;
    assign dataOut1 = dataOut;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            locked    <= 1'b0;
            lockedSel <= 1'b0;
            lastGrant <= 1'b1;
        end else begin
            if (readReq | writeReq) begin
                if (waitReq) begin
                    locked    <= 1'b1;
                    lockedSel <= sel;
                end else begin
                    locked    <= 1'b0;
                    lastGrant <= sel;
                end
            end else begin
                locked <= 1'b0;
            end
        end
    end
endmodule
