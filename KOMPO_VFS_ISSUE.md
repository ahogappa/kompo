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

## Proposed Changes

### 1. New external symbols in `kompo_fs/src/lib.rs`

```rust
unsafe extern "C" {
    // Existing
    static FILES: libc::c_char;
    static FILES_SIZE: libc::c_int;
    static FILES_SIZES: libc::c_ulonglong;
    static PATHS: libc::c_char;
    static PATHS_SIZE: libc::c_int;
    static WD: libc::c_char;

    // New for compression support
    static COMPRESSION_ENABLED: libc::c_int;      // 0 = disabled, 1 = enabled
    static ORIGINAL_SIZES: libc::c_ulonglong;     // Original file sizes (for decompression)
    static COMPRESSION_FLAGS: libc::c_uchar;      // Per-file: 0 = uncompressed, 1 = zstd
}
```

### 2. Update `initialize_fs()` to handle decompression

```rust
pub fn initialize_fs() -> kompo_storage::Fs<'static> {
    let compression_enabled = unsafe { COMPRESSION_ENABLED } != 0;

    for (i, path_byte) in splited_path_array.into_iter().enumerate() {
        let range: Range<usize> = files_sizes[i] as usize..files_sizes[i + 1] as usize;
        let raw_data = &file_slice[range];

        let file_data: &'static [u8] = if compression_enabled && compression_flags[i] != 0 {
            let original_size = original_sizes[i] as usize;
            let decompressed = zstd::bulk::decompress(raw_data, original_size)
                .expect("decompression failed");
            Box::leak(decompressed.into_boxed_slice())
        } else {
            raw_data
        };

        builder.push(path, file_data);
    }
}
```

### 3. Add dependency

```toml
# kompo_fs/Cargo.toml
[dependencies]
zstd = "0.13"
```

## Backward Compatibility

- When `COMPRESSION_ENABLED = 0`, behavior is identical to current implementation
- kompo will generate the new symbols with compression disabled by default
- Users can opt-in with `--compress` flag

## Expected Size Reduction

For a typical 10MB Ruby project:
- Without compression: 10 MB
- With Zstd -3: ~3.8 MB (**62% reduction**)
- With Zstd -10: ~3.0 MB (**70% reduction**)

## Related

- kompo side implementation will be done in a separate PR after this is merged
