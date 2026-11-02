////////////////////////////////////////////////////////////////////////////////
// File      : DataCacheAtomicLrSc.sv
// Author(s) : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Date      : 2026-10-07
//
// Description:
//   LR/SC reservation tracking for data_cache_atomic.
//   Tracks per-core reservation validity and address, and kills reservations
//   when another write completes to the same word address.
//
////////////////////////////////////////////////////////////////////////////////
module data_cache_atomic_lrsc (
    input  wire         clk,
    input  wire         rst,

    input  wire         core0LRCommit,
    input  wire         core1LRCommit,

    input  wire         core0SCStart,
    input  wire         core1SCStart,
    input  wire  [31:0] core0SCAddress,
    input  wire  [31:0] core1SCAddress,

    input  wire  [31:0] lrAddressR,

    input  wire         cacheWriteComplete0,
    input  wire         cacheWriteComplete1,
    input  wire  [31:0] cacheAddress0,
    input  wire  [31:0] cacheAddress1,

    output logic        scSuccessR,

    output logic        core0ResValid,
    output logic [29:0] core0ResAddr,
    output logic        core1ResValid,
    output logic [29:0] core1ResAddr
);

    logic core0ResKill;
    logic core1ResKill;

    always_comb begin
        core0ResKill = 1'b0;
        core1ResKill = 1'b0;

        if (cacheWriteComplete0) begin
            if (core0ResValid & (core0ResAddr == cacheAddress0[31:2]))
                core0ResKill = 1'b1;
            if (core1ResValid & (core1ResAddr == cacheAddress0[31:2]))
                core1ResKill = 1'b1;
        end

        if (cacheWriteComplete1) begin
            if (core0ResValid & (core0ResAddr == cacheAddress1[31:2]))
                core0ResKill = 1'b1;
            if (core1ResValid & (core1ResAddr == cacheAddress1[31:2]))
                core1ResKill = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scSuccessR <= 1'b0;
        end else if (core0SCStart) begin
            scSuccessR <= core0ResValid & (core0ResAddr == core0SCAddress[31:2]);
        end else if (core1SCStart) begin
            scSuccessR <= core1ResValid & (core1ResAddr == core1SCAddress[31:2]);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            core0ResValid <= 1'b0;
            core0ResAddr  <= 30'b0;
        end else if (core0LRCommit) begin
            core0ResValid <= 1'b1;
            core0ResAddr  <= lrAddressR[31:2];
        end else if (core0SCStart) begin
            core0ResValid <= 1'b0;
        end else if (core0ResKill) begin
            core0ResValid <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            core1ResValid <= 1'b0;
            core1ResAddr  <= 30'b0;
        end else if (core1LRCommit) begin
            core1ResValid <= 1'b1;
            core1ResAddr  <= lrAddressR[31:2];
        end else if (core1SCStart) begin
            core1ResValid <= 1'b0;
        end else if (core1ResKill) begin
            core1ResValid <= 1'b0;
        end
    end

endmodule
