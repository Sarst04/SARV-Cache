# SARV-Cache

Configurable instruction and data cache subsystem for RISC-V processors.

SARV-Cache provides separate instruction and data caches. The design is written in SystemVerilog and is parameterized for different cache sizes, associativities, and line organizations.

## Instruction Cache

The instruction cache provides a read-only cache interface between the processor and instruction memory.

### Main Features

- Set-associative cache
- Configurable number of cache lines
- Configurable number of words per line
- Configurable number of ways
- LRU replacement
- Optional cache bypass

### Parameters

| Parameter | Description |
|---|---|
| `CACHE_LINES` | Number of cache lines |
| `WORD_PER_LINE` | Number of words in each cache line |
| `NUM_WAYS` | Cache associativity |
| `BYPASS_CACHE` | Bypass instruction cache |

## Data Cache

The data cache provides read and write access between the processor and data memory.

### Main Features

- Set-associative cache
- Configurable number of cache lines
- Configurable number of words per line
- Configurable number of ways
- LRU replacement
- Write-back cache
- Write allocation
- Peripheral access bypass
- Optional cache bypass


### Parameters

| Parameter | Description |
|---|---|
| `CACHE_LINES` | Number of cache lines |
| `WORD_PER_LINE` | Number of words in each cache line |
| `NUM_WAYS` | Cache associativity |
| `BYPASS_CACHE` | Bypass data cache |
| `MEM_BASE` | Start of cached memory region |
| `MEM_END` | End of cached memory region |


---

## Cache Organization

Both caches are configurable through SystemVerilog parameters.

The cache capacity is determined by the number of cache lines, number of words per line, and word size.

For a cache with `CACHE_LINES` total lines:

```text
Cache Capacity = CACHE_LINES * WORD_PER_LINES * 4 bytes
```

The number of sets is:

```text
Number of Sets = CACHE_LINES / NUM_WAYS
```

## Instruction Cache Operation

The instruction cache checks the requested address against the tags stored in each way.

On a hit, the requested instruction is returned directly from the cache.

On a miss, the required cache line is requested from instruction memory and stored in the selected cache way.

The instruction cache also handles instruction accesses that are not aligned to a 32-bit word boundary. This is required for RISC-V compressed instructions. In this case, the cache only sets a flag so that the unaligned access can be handled by the core.

## Data Cache Operation

The data cache supports both load and store operations.

On a read hit, data is returned directly from the cache.

On a read miss, the required cache line is fetched from memory.

For a write hit, the cache is updated and the corresponding line is marked dirty.

When a dirty cache line is selected for replacement, the line is written back to memory before the new cache line is fetched.

## Peripheral Access

The data cache supports bypassing accesses outside the configured cached memory range.

This allows memory-mapped peripherals to be accessed without storing their data in the cache.

The cached memory region can be configured using:

- `MEM_BASE`
- `MEM_END`

Addresses outside the configured range can bypass the data cache.

# RISC-V Integration

SARV-Cache is designed primarily for RISC-V processors.

It is particularly intended for use with the [SARV RISC-V processor](https://github.com/Sarst04/SARV).

SARV-Cache is independent from the processor implementation and can also be adapted for other RISC-V cores with compatible memory interfaces.



## License

This project is licensed under the CERN Open Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S-2.0).