////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheDual.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-09-27
//
// Description:
//   Shared dual master data cache.
////////////////////////////////////////////////////////////////////////////////
module data_cache_dual #(
    parameter int CACHE_LINES     = 128,
    parameter int NUM_WAYS        = 4,
    parameter int WORD_PER_LINES  = 1,
    parameter int STORE_BUF_DEPTH = 2,
    parameter bit BYPASS_CACHE    = 0,

    parameter logic [31:0] MEM_BASE = 32'h8000_0000,
    parameter logic [31:0] MEM_END  = 32'h8F00_0000
)(
    input wire clk,
    input wire rst,

    // Master 0
    input  wire         readReq0,
    input  wire         writeReq0,
    input  wire  [ 1:0] accessType0,
    output logic        waitReq0,
    input  wire         atomic0,
    input  wire  [ 4:0] atomicOpcode0,

    input  wire  [31:0] address0,
    input  wire  [31:0] writeData0,
    output logic [31:0] readData0,

    // Master 1
    input  wire         readReq1,
    input  wire         writeReq1,
    input  wire  [ 1:0] accessType1,
    output logic        waitReq1,
    input  wire         atomic1,
    input  wire  [ 4:0] atomicOpcode1,

    input  wire  [31:0] address1,
    input  wire  [31:0] writeData1,
    output logic [31:0] readData1,

    // Memory interface
    input  wire                          memWaitReq,

    output logic                         memReadReq,
    output logic                         memWriteReq,
    output logic [1:0]                   memAccessType,

    input  wire  [32*WORD_PER_LINES-1:0] memReadData,

    output logic [31:0]                  memAddress,
    output logic [32*WORD_PER_LINES-1:0] memWriteData
);

	wire         core0ReadReq;
	wire         core0WriteReq;
	wire [ 1:0]  core0AccessType;
	wire         core0Atomic;
	wire [ 4:0]  core0AtomicOpcode;
	wire [31:0]  core0Address;
	wire [31:0]  core0DataIn;
	wire         core0WaitReq;
	wire [31:0]  core0DataOut;

    wire         core1ReadReq;
    wire         core1WriteReq;
    wire  [ 1:0] core1AccessType;
    wire         core1Atomic;
    wire  [ 4:0] core1AtomicOpcode;
    wire  [31:0] core1Address;
    wire  [31:0] core1DataIn;
    wire         core1WaitReq;
    wire  [31:0] core1DataOut;

    wire         cacheReadReq;
    wire         cacheWriteReq;
    wire  [1:0]  cacheAccessType;
    wire  [31:0] cacheAddress;
    wire  [31:0] cacheDataIn;

    wire         cacheWaitReq;
    wire  [31:0] cacheDataOut;

    data_cache_atomic dataCacheAtomic (
        .clk(clk),
        .rst(rst),

        // Core 0
        .core0ReadReq     (readReq0),
        .core0WriteReq    (writeReq0),
        .core0AccessType  (accessType0),
        .core0Atomic      (atomic0),
        .core0AtomicOpcode(atomicOpcode0),
        .core0Address     (address0),
        .core0WriteData   (writeData0),
        .core0WaitReq     (waitReq0),
        .core0ReadData    (readData0),

        // Core 1
        .core1ReadReq     (readReq1),
        .core1WriteReq    (writeReq1),
        .core1AccessType  (accessType1),
        .core1Atomic      (atomic1),
        .core1AtomicOpcode(atomicOpcode1),
        .core1Address     (address1),
        .core1WriteData   (writeData1),
        .core1WaitReq     (waitReq1),
        .core1ReadData    (readData1),

        // Cache port 0 (arbiter)
        .cacheReadReq0    (core0ReadReq),
        .cacheWriteReq0   (core0WriteReq),
        .cacheAccessType0 (core0AccessType),
        .cacheAddress0    (core0Address),
        .cacheWriteData0  (core0DataIn),
        .cacheWaitReq0    (core0WaitReq),
        .cacheReadData0   (core0DataOut),

        // Cache port 1 (arbiter)
        .cacheReadReq1    (core1ReadReq),
        .cacheWriteReq1   (core1WriteReq),
        .cacheAccessType1 (core1AccessType),
        .cacheAddress1    (core1Address),
        .cacheWriteData1  (core1DataIn),
        .cacheWaitReq1    (core1WaitReq),
        .cacheReadData1   (core1DataOut)
    );


    data_cache_arbiter dataCacheArbiter (
        .clk(clk),
        .rst(rst),

        // Master 0
        .readReq0   (core0ReadReq),
        .writeReq0  (core0WriteReq),
        .accessType0(core0AccessType),
        .address0   (core0Address),
        .dataIn0    (core0DataIn),
        .waitReq0   (core0WaitReq),
        .dataOut0   (core0DataOut),

        // Master 1
        .readReq1   (core1ReadReq),
        .writeReq1  (core1WriteReq),
        .accessType1(core1AccessType),
        .address1   (core1Address),
        .dataIn1    (core1DataIn),
        .waitReq1   (core1WaitReq),
        .dataOut1   (core1DataOut),

        // Shared cache
        .readReq    (cacheReadReq),
        .writeReq   (cacheWriteReq),
        .accessType (cacheAccessType),
        .address    (cacheAddress),
        .dataIn     (cacheDataIn),

        .waitReq    (cacheWaitReq),
        .dataOut    (cacheDataOut)
    );

    data_cache #(
        .CACHE_LINES    (CACHE_LINES),
        .NUM_WAYS       (NUM_WAYS),
        .WORD_PER_LINES (WORD_PER_LINES),
        .STORE_BUF_DEPTH(STORE_BUF_DEPTH),
        .BYPASS_CACHE   (BYPASS_CACHE),
        .MEM_BASE       (MEM_BASE),
        .MEM_END        (MEM_END)
    ) dataCache (

        .clk(clk),
        .rst(rst),

        .readReq    (cacheReadReq),
        .writeReq   (cacheWriteReq),
        .accessType (cacheAccessType),

        .waitReq    (cacheWaitReq),

        .address    (cacheAddress),
        .dataIn     (cacheDataIn),
        .dataOut    (cacheDataOut),

        .memWaitReq (memWaitReq),

        .memReadReq (memReadReq),
        .memWriteReq(memWriteReq),
        .memAccessType(memAccessType),

        .memDataIn  (memReadData),
        .memAddress (memAddress),
        .memDataOut (memWriteData)
    );

endmodule