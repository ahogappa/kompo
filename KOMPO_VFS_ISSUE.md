# GitHub Issue for kompo-vfs

**Repository:** https://github.com/ahogappa/kompo-vfs
**Title:** Add zstd compression support for embedded files

---

## Summary

Add support for zstd-compressed file data to reduce binary size. This would allow kompo to embed files in compressed form, with kompo-vfs decompressing them at runtime.

## Background

Currently, files are embedded uncompressed in the binary. For typical Ruby projects, this results in larger binaries than necessary. Text-based files (`.rb`, `.erb`, `.yml`, `.json`) compress very well with modern algorithms.

### Compression Algorithm Comparison

| Algorithm | Compression Ratio | Decompress Speed | Recommendation |
|-----------|------------------|------------------|----------------|
| LZ4 | 45-50% | ~2000 MB/s | Fast builds |
| **Zstd -3** | **60-65%** | **~1000 MB/s** | **Recommended** |
| Zlib -6 | 65-70% | ~300 MB/s | Compatible |
| Zstd -19 | 72-76% | ~1000 MB/s | Max compression |
| LZMA | 75-80% | ~100 MB/s | Too slow |

**Zstd is recommended** because:
- Decompression speed is consistent regardless of compression level
- Good compression ratio (can use high level at build time)
- Mature Rust crate (`zstd`)

## Memory-Efficient Design

### Problem with naive implementation

A naive implementation would allocate new heap memory for decompressed data (`Box::leak`), resulting in both compressed and decompressed data residing in memory.

### Solution: Use .bss section for decompression buffer

```
ELF File Structure:
┌─────────────────────────┐
│ .rodata                 │  ← COMPRESSED_FILES (file size = compressed size)
├─────────────────────────┤
│ .bss                    │  ← FILES_BUFFER (file size = 0, runtime = original size)
└─────────────────────────┘
```

**Key insight**: The `.bss` section stores only size information in the ELF file (practically 0 bytes), but the OS allocates the full memory at runtime.

### Data flow

```
Build time:
  [Ruby files 10MB] → zstd compress → [COMPRESSED_FILES 3MB in .rodata]
                                      [FILES_BUFFER 10MB in .bss (0 bytes on disk)]

Runtime:
  1. OS loads binary (3MB from disk)
  2. OS allocates .bss zero-filled memory (10MB)
  3. Decompress: COMPRESSED_FILES → FILES_BUFFER
  4. COMPRESSED_FILES pages become unused → OS can page out

Final memory: ~10MB (decompressed data only)
```

## Proposed Changes

### 1. New external symbols in `kompo_fs/src/lib.rs`

```rust
unsafe extern "C" {
    // Existing (when compression disabled)
    static FILES: libc::c_char;
    static FILES_SIZE: libc::c_int;
    static FILES_SIZES: libc::c_ulonglong;
    static PATHS: libc::c_char;
    static PATHS_SIZE: libc::c_int;
    static WD: libc::c_char;

    // New for compression support
    static COMPRESSION_ENABLED: libc::c_int;       // 0 = disabled, 1 = enabled

    // When compression enabled:
    static COMPRESSED_FILES: libc::c_char;         // Compressed data (.rodata)
    static COMPRESSED_FILES_SIZE: libc::c_int;     // Total compressed size
    static COMPRESSED_SIZES: libc::c_ulonglong;    // Per-file compressed sizes (cumulative)
    static mut FILES_BUFFER: libc::c_char;         // Decompression target (.bss, mutable)
    static FILES_BUFFER_SIZE: libc::c_int;         // Total original size
    static ORIGINAL_SIZES: libc::c_ulonglong;      // Per-file original sizes (cumulative)
}
```

### 2. Update `initialize_fs()` to handle decompression

```rust
pub fn initialize_fs() -> kompo_storage::Fs<'static> {
    let compression_enabled = unsafe { COMPRESSION_ENABLED } != 0;

    if compression_enabled {
        // Decompress all files into .bss buffer at startup
        decompress_all_files();

        // Use FILES_BUFFER as the file data source
        let file_slice = unsafe {
            std::slice::from_raw_parts(
                &FILES_BUFFER as *const _ as *const u8,
                FILES_BUFFER_SIZE as usize
            )
        };
        let files_sizes = unsafe {
            std::slice::from_raw_parts(
                &ORIGINAL_SIZES as *const _ as *const u64,
                // ... count
            )
        };
        // ... build trie using decompressed data
    } else {
        // Existing logic: use FILES directly
    }
}

fn decompress_all_files() {
    let compressed_slice = unsafe {
        std::slice::from_raw_parts(
            &COMPRESSED_FILES as *const _ as *const u8,
            COMPRESSED_FILES_SIZE as usize
        )
    };
    let buffer_slice = unsafe {
        std::slice::from_raw_parts_mut(
            &mut FILES_BUFFER as *mut _ as *mut u8,
            FILES_BUFFER_SIZE as usize
        )
    };

    // Decompress entire buffer at once (more efficient)
    zstd::bulk::decompress_to_buffer(compressed_slice, buffer_slice)
        .expect("decompression failed");
}
```

### 3. Add dependency

```toml
# kompo_fs/Cargo.toml
[dependencies]
zstd = "0.13"
```

### 4. Changes in kompo (fs.c generation)

```c
// When compression enabled:
const unsigned char COMPRESSED_FILES[] = { /* zstd compressed data */ };
const int COMPRESSED_FILES_SIZE = /* total compressed size */;
const unsigned long long COMPRESSED_SIZES[] = { /* cumulative compressed sizes */ };

unsigned char FILES_BUFFER[TOTAL_ORIGINAL_SIZE];  // .bss - no disk space!
const int FILES_BUFFER_SIZE = TOTAL_ORIGINAL_SIZE;
const unsigned long long ORIGINAL_SIZES[] = { /* cumulative original sizes */ };

const int COMPRESSION_ENABLED = 1;

// PATHS, WD remain the same
```

## Size Analysis

| Component | Disk Size | Runtime Memory |
|-----------|-----------|----------------|
| COMPRESSED_FILES (.rodata) | 3 MB | 3 MB (pages out after decompression) |
| FILES_BUFFER (.bss) | **0 bytes** | 10 MB |
| **Total** | **3 MB** | ~10 MB |

vs. without compression:

| Component | Disk Size | Runtime Memory |
|-----------|-----------|----------------|
| FILES (.rodata) | 10 MB | 10 MB |
| **Total** | **10 MB** | 10 MB |

**Result: 70% reduction in binary size with same runtime memory usage**

## Backward Compatibility

- When `COMPRESSION_ENABLED = 0`, behavior is identical to current implementation
- kompo will generate the new symbols with compression disabled by default
- Users can opt-in with `--compress` flag

## Expected Size Reduction

For a typical 10MB Ruby project:
- Without compression: 10 MB binary
- With Zstd -3: ~3.8 MB binary (**62% reduction**)
- With Zstd -10: ~3.0 MB binary (**70% reduction**)

## Alternative: Per-file decompression

Instead of decompressing everything at startup, we could decompress files on-demand. However, this adds complexity and the startup cost of bulk decompression is negligible for typical project sizes.

## Related

- kompo side implementation will be done in a separate PR after this is merged
