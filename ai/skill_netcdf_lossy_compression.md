# Skill: Lossy Compression of NetCDF Files

Two battle-tested methods for compressing large scientific NetCDF4/HDF5 files
while preserving data fidelity to a configurable number of significant digits.
Both methods handle NaN/fill values correctly, produce CF-convention-compliant
output, and work with `netCDF4`, `xarray`, and `zarr` readers.

---

## Dependencies

```bash
pip install netCDF4 numpy hdf5plugin zarr
# hdf5plugin registers the Blosc and ZFP HDF5 filters automatically on import
# Must be imported BEFORE netCDF4 in any script that reads or writes these files
```

---

## When to Use Which Method

The choice is an **I/O bandwidth vs CPU decompression** tradeoff:

- **int16, no filter**: reads 2× less data than float32, with zero decompression overhead
  (unpack = one multiply + one add per value, SIMD-trivial, runs at memory bandwidth).
  On fast storage (NVMe SSD, RAM disk), decompression algorithms become the bottleneck —
  so removing the filter means I/O bandwidth is the *only* cost.
- **ZFP lossy**: reads 6–10× less data, but ZFP decompression runs on every chunk read.
  Worth it when I/O is slow (HDD, network, cloud object storage) so the reduced read
  size dominates. On fast storage, ZFP decompression CPU can exceed the I/O savings
  and make reads *slower* than int16 despite reading less data.

**Rough rule:**
- Fast storage (NVMe, RAM disk, frequent ML training reads) → **int16, no filter**
- Slow storage (HDD, NFS, cloud) or infrequent/archival access → **ZFP**

| | Method 1: int16 packing | Method 2: ZFP |
|---|---|---|
| **Compression** from | dtype change float32→int16 (always 2×) | ZFP lossy algorithm (6–10×) |
| **HDF5 filter** | none | ZFP lossy; Blosc lossless for coords |
| **Decompression cost** | near-zero (SIMD multiply+add) | moderate CPU per chunk — can dominate on fast storage |
| **Precision** | ~4.8 sig digits of range (or SIG_DIGITS if pre-quantized) | configurable (precision=12 ≈ 3.6 sig digits) |
| **Fill/NaN handling** | INT16_FILL sentinel, CF-transparent | data-relative float sentinel + valid_range attrs |
| **Reader requirement** | any CF reader (xarray/netCDF4) | `import hdf5plugin` required |
| **Best for** | NVMe/RAM disk, frequent reads (ML training) | HDD/network/cloud, archival, infrequent reads |

---

## Method 1 — int16 Quantization + CF Packing (no HDF5 filter)

### Concept
Pack each float variable into int16 using a linear CF-convention mapping
(`scale_factor` / `add_offset`). **No HDF5 compression filter is applied.**

Guaranteed **2× size reduction** (float32 = 4 bytes → int16 = 2 bytes).
Unpack cost is `float = int16 * scale + offset` — SIMD-trivial, runs at memory bandwidth.
Precision: ~4.8 range-relative sig digits (65534 levels); if SIG_DIGITS=4 pre-quantization
is applied, practical precision is 4 value-relative sig digits.
Fully CF-transparent: any CF-aware reader (`netCDF4`, `xarray`) auto-unpacks on load.

### Packing math

```python
INT16_FILL = np.int16(-32768)   # reserved _FillValue (NaN/masked)
INT16_MIN  = np.int16(-32767)   # min usable packed value
INT16_MAX  = np.int16( 32767)   # max usable packed value

def scale_offset_for(vmin, vmax):
    """CF scale_factor / add_offset for int16 packing.
    Unpack: physical = packed * scale_factor + add_offset
    """
    n_levels = int(INT16_MAX) - int(INT16_MIN)   # 65534 usable levels
    scale  = np.float32((vmax - vmin) / n_levels)
    offset = np.float32((vmax + vmin) / 2.0)
    return scale, offset

def pack_int16(data, scale, offset):
    """Pack float32 array → int16.  NaN/inf → INT16_FILL."""
    nan_mask = ~np.isfinite(data)
    safe = data.copy()
    safe[nan_mask] = np.float32(0.0)   # avoid cast warnings on NaN arithmetic
    raw  = np.clip(np.round((safe - offset) / scale),
                   int(INT16_MIN), int(INT16_MAX))
    packed = raw.astype(np.int16)
    packed[nan_mask] = INT16_FILL
    return packed
```

### Pre-quantization (optional)

Round to N significant digits before packing to control precision explicitly.
Without a lossless filter on top, quantization does **not** reduce file size
(no entropy coding is applied — size is determined solely by dtype). Its value
here is precision control: ensuring the stored error is bounded by a known
digit count rather than by arbitrary linear rounding:

```python
SIG_DIGITS = 4   # 4 sig digits → error ≤ 5×10⁻⁵ × |value|

def quantize(data, n_sig=SIG_DIGITS):
    """Round float32 to n significant digits. NaN/inf pass through."""
    finite = np.isfinite(data) & (data != 0)
    if not finite.any():
        return data
    out = data.copy()
    d   = data[finite]
    mag    = np.floor(np.log10(np.abs(d)))
    factor = 10.0 ** (n_sig - 1 - mag)
    out[finite] = (np.round(d * factor) / factor).astype(np.float32)
    return out
```

> If a lossless filter (Blosc, gzip) IS added on top, quantization also improves
> compression ratio because quantised values cluster into fewer unique codes.

### Range scan (first pass; shared by both methods)

Iterate over the variable once to find finite min/max. Add a 2 % margin so
extreme values never clip to INT16_MIN/MAX (int16), and to anchor the ZFP
sentinel and valid_range (Method 2):

```python
def scan_range(var, read_chunk_mb=1500):
    vmin, vmax = np.inf, -np.inf
    step = max(1, int(read_chunk_mb * 1e6 / (np.prod(var.shape[1:]) * var.dtype.itemsize)))
    for i in range(0, var.shape[0], step):
        chunk = var[i:min(i + step, var.shape[0])]
        if hasattr(chunk, "filled"):
            chunk = chunk.filled(np.nan)
        chunk = chunk.astype(np.float32)
        finite = chunk[np.isfinite(chunk)]
        if finite.size:
            vmin = min(vmin, float(finite.min()))
            vmax = max(vmax, float(finite.max()))
    if vmin == np.inf:          # all fill — return dummy range
        return 0.0, 1.0
    margin = max((vmax - vmin) * 0.02, 1e-6)
    return vmin - margin, vmax + margin
```

### Variable creation (NetCDF4 path, no filter)

```python
import hdf5plugin   # needed on reader side; not strictly required here for int16

dst_var = dst.createVariable(
    name, "int16", var.dimensions,
    chunksizes=chunksizes, fill_value=INT16_FILL,
    # No compression filter — 2× size reduction comes from dtype alone
)
dst_var.set_auto_scale(False)   # we write pre-packed int16 directly
```

> To optionally add Blosc on top: add `compression="blosc_zstd", complevel=6,
> blosc_shuffle=1` to the kwargs. This typically yields an additional 2–4×
> reduction at the cost of decompression CPU.

### Attribute handling for packed variables

```python
# Attributes whose meaning changes after packing — exclude and rewrite:
_ALWAYS_EXCLUDE = frozenset({"_FillValue"})
_PACK_EXCLUDE   = frozenset({"missing_value", "valid_min", "valid_max",
                              "valid_range", "actual_range",
                              "actual_min", "actual_max"})
exclude = _ALWAYS_EXCLUDE | _PACK_EXCLUDE
attrs = {k: var.getncattr(k) for k in var.ncattrs() if k not in exclude}
attrs["scale_factor"] = scale_f   # float32
attrs["add_offset"]   = offset_f  # float32
if "missing_value" in var.ncattrs():
    attrs["missing_value"] = INT16_FILL
dst_var.setncatts(attrs)
```

---

## Output File Setup + Variable Loop (both methods)

```python
with nc.Dataset(src_path, "r") as src, \
     nc.Dataset(out_path, "w", format="NETCDF4") as dst:

    dst.setncatts(src.__dict__)   # copy global attributes

    for dname, dim in src.dimensions.items():
        dst.createDimension(dname, None if dim.isunlimited() else len(dim))

    for name, var in src.variables.items():
        is_float = np.issubdtype(var.dtype, np.floating)
        lossy    = var.ndim >= 2 and is_float   # apply lossy to multidim float only
        # 1-D coords (lat/lon/time) and non-float → lossless copy (see lossless fallback)

        # ... create and write variable ...

        dst.sync()   # flush after each variable — avoids silent truncation on crash
```

On exception, remove the partial output immediately:

```python
except Exception:
    if os.path.exists(out_path):
        os.remove(out_path)   # or shutil.rmtree for zarr
    raise
```

---

## Method 2 — ZFP Direct Float Compression

### Concept
Direct lossy float compression — no int16 packing, 6–10× size reduction on smooth
geophysical fields. Decompression runs per HDF5 chunk read (see "When to Use" for
the I/O vs CPU tradeoff).

ZFP operates on 4×4 spatial blocks. NaN/fill values must be replaced with a
**data-relative sentinel** before writing — a fixed constant like `-9999` explodes
the block dynamic range and degrades both compression quality and accuracy.

Three sub-modes (choose one):

| Mode | Parameter | Meaning |
|------|-----------|---------|
| `accuracy` | absolute error per value | auto-computable from range × 10⁻ᴺ |
| `precision` | bit planes retained | 12 ≈ 3.6 sig digits; 14 ≈ 4; 17 ≈ 5 |
| `rate` | bits per value | 16 = 2 bytes (same as int16) |

### ZFP sub-modes — choosing precision

```python
ZFP_MODE      = "precision"   # recommended starting point
ZFP_PRECISION = 12            # bit planes: 10 ≈ 3 sig digits, 12 ≈ 3.6, 14 ≈ 4, 17 ≈ 5

# Alternative: auto-compute accuracy from range and desired sig digits:
# ZFP_ACCURACY = (vmax - vmin) / (10 ** SIG_DIGITS)   # e.g. SIG_DIGITS=4
# This gives ~4 range-relative sig digits — slightly less than int16's ~4.8,
# but comparable quality and useful when you want to match a specific digit count.
```

### Sentinel design for fill values

ZFP works in 4×4 spatial blocks. Boundary blocks mixing ocean fill values with
valid near-zero data produce huge dynamic range if the fill sentinel is a fixed
constant (e.g. −9999 or +1e20). Use a **data-relative sentinel** instead:

```python
ZFP_SENTINEL_FACTOR    = 1.5   # sentinel = −FACTOR × max(|vmin|, |vmax|)
ZFP_VALID_RANGE_MARGIN = 0.10  # valid_min/max expanded ± this fraction of range

r             = vmax - vmin
max_abs_valid = max(abs(vmin), abs(vmax))
# Cast to variable dtype so netCDF4 valid-range masking works on float32
fv            = var.dtype.type(-ZFP_SENTINEL_FACTOR * max_abs_valid)
zfp_valid_min = var.dtype.type(vmin - ZFP_VALID_RANGE_MARGIN * r)
zfp_valid_max = var.dtype.type(vmax + ZFP_VALID_RANGE_MARGIN * r)
```

**Why the factor matters:**
- ZFP `precision=12` quantises at `block_range / 4096 ≈ 0.025 %` of block range.
- The gap from the sentinel to `valid_min` must be >> ZFP error so fill values
  can never be mistaken for valid data after decompression.
- `FACTOR = 1.5` gives `gap = (FACTOR − 1 − 2×MARGIN) × max_abs = 0.3 × max_abs`
  for symmetric data → ~500× ZFP headroom (gap / ZFP_error, precision=12).
  Even `FACTOR = 1.1` is technically safe, but 1.5 is a clear round value.
- **Minimum safe value**: `FACTOR > 1 + 2 × MARGIN` (gap would otherwise be
  zero for perfectly symmetric data).

### Attribute handling for ZFP + fill variables

```python
# Exclude original range attrs; write recomputed ones cast to correct dtype:
_PACK_EXCLUDE = frozenset({"missing_value", "valid_min", "valid_max",
                            "valid_range", "actual_range",
                            "actual_min", "actual_max"})
exclude = frozenset({"_FillValue"}) | _PACK_EXCLUDE
attrs = {k: var.getncattr(k) for k in var.ncattrs() if k not in exclude}
attrs["valid_min"] = zfp_valid_min   # already cast to var.dtype above
attrs["valid_max"] = zfp_valid_max
if "missing_value" in var.ncattrs():
    attrs["missing_value"] = fv      # same dtype as _FillValue
dst_var.setncatts(attrs)
```

> **Critical**: Cast `valid_min`, `valid_max`, `_FillValue`, and `missing_value`
> to `var.dtype` (e.g. `np.float32`) **before** writing. If they are Python
> `float` (float64) and the variable is float32, netCDF4 silently disables
> valid-range masking on read with the warning
> `"cannot safely cast valid_min"`.

### Variable creation (ZFP cannot use createVariable kwargs)

ZFP requires calling `nc_def_var_filter` via the C API after `createVariable`:

```python
import ctypes, hdf5plugin

_libnetcdf = ctypes.CDLL("libnetcdf.so")
_libnetcdf.nc_def_var_filter.restype  = ctypes.c_int
_libnetcdf.nc_def_var_filter.argtypes = [
    ctypes.c_int, ctypes.c_int, ctypes.c_uint,
    ctypes.c_size_t, ctypes.POINTER(ctypes.c_uint),
]

def apply_zfp_filter(dst_grp, dst_var, mode="precision", precision=12,
                     accuracy=None, rate=16.0):
    """Call AFTER createVariable, BEFORE writing any data."""
    if mode == "precision":
        params_tuple = tuple(hdf5plugin.Zfp(precision=precision)["compression_opts"])
    elif mode == "accuracy":
        params_tuple = tuple(hdf5plugin.Zfp(accuracy=float(accuracy))["compression_opts"])
    elif mode == "rate":
        params_tuple = tuple(hdf5plugin.Zfp(rate=float(rate))["compression_opts"])
    else:
        raise ValueError(f"Unknown mode: {mode!r}")
    ParamsArray = ctypes.c_uint * len(params_tuple)
    params = ParamsArray(*params_tuple)
    ret = _libnetcdf.nc_def_var_filter(
        dst_grp._grpid, dst_var._varid,
        ctypes.c_uint(32013), ctypes.c_size_t(len(params_tuple)), params,
    )
    if ret != 0:
        raise RuntimeError(f"nc_def_var_filter returned error code {ret}")

# Create variable (no compression kwargs for ZFP)
dst_var = dst.createVariable(
    name, var.datatype, var.dimensions,
    chunksizes=chunksizes, fill_value=fv,
)
apply_zfp_filter(dst, dst_var)   # must be before first write

# Replace fill/masked → sentinel before writing
data = var[i:end]
if hasattr(data, "filled"):
    data = data.filled(fv)
dst_var[i:end] = data
```

### Blosc lossless fallback for coords and non-float variables (ZFP mode)

In ZFP mode, apply Blosc/zstd losslessly to coordinates and non-float variables.
This means a single ZFP-mode file uses **both** ZFP lossy (data vars) and
Blosc lossless (coords) within the same file — two different filters for two
different variable classes:

```python
is_float  = np.issubdtype(var.dtype, np.floating)
zfp_apply = var.ndim >= 2 and is_float   # ZFP for float data vars only

if not zfp_apply:
    dst_var = dst.createVariable(
        name, var.datatype, var.dimensions,
        compression="blosc_zstd", complevel=6, blosc_shuffle=1,
        chunksizes=chunksizes, fill_value=fv,
    )
    # Lossless copy: use raw .data to bypass mask from valid_min/valid_max metadata.
    # Converting a metadata-only mask to fill values on disk silently corrupts
    # coordinate variables (e.g. longitude stored as degrees_east [-80.5…359.75]
    # with valid_min=0 would lose negative values).
    raw  = var[i:end]
    data = raw.data if isinstance(raw, np.ma.MaskedArray) else raw
    dst_var[i:end] = data
```

### Blosc thread count (optional, for write speed)

```python
import ctypes, hdf5plugin
_blosc = ctypes.CDLL(
    os.path.join(os.path.dirname(hdf5plugin.__file__), "plugins", "libh5blosc.so")
)
_blosc.blosc_set_nthreads.restype  = ctypes.c_int
_blosc.blosc_set_nthreads.argtypes = [ctypes.c_int]
_blosc.blosc_set_nthreads(6)   # default is usually 1; set to n_cores for speed
```

---

## Chunking Strategy

Full spatial extent per chunk maximises compression of coherent spatial fields.
Adjust `t_tile` to hit a memory budget:

```python
TARGET_CHUNK_MB = 2.0   # target uncompressed chunk size

def optimal_chunksizes(var, out_itemsize=None):
    item_bytes = out_itemsize or var.dtype.itemsize
    if var.ndim == 3:
        T, Y, X       = var.shape
        spatial_bytes = Y * X * item_bytes
        target_bytes  = int(TARGET_CHUNK_MB * 1e6)
        if spatial_bytes <= target_bytes:
            t_tile = max(1, min(T, target_bytes // spatial_bytes))
            return [t_tile, Y, X]
        # Grid too large: tile spatially with t=1
        # (binary-search for tile size that fits budget)
        yt = min(Y, max(50, int((target_bytes / item_bytes) ** 0.5)))
        xt = min(X, max(50, int((target_bytes / item_bytes) ** 0.5)))
        return [1, yt, xt]
    src = var.chunking()
    return src if isinstance(src, list) else None
```

---

## Reading Data in Chunks (Memory Management)

```python
READ_CHUNK_MB = 1500   # RAM per read window

def read_steps(var, read_chunk_mb=READ_CHUNK_MB):
    if var.ndim < 2:
        return var.shape[0]
    bytes_per_slice = np.prod(var.shape[1:]) * var.dtype.itemsize
    return max(1, int(read_chunk_mb * 1e6 / bytes_per_slice))

def safe_read(var, i, end):
    """Read slice as float32 with NaN for masked/fill values."""
    chunk = var[i:end]
    if hasattr(chunk, "filled"):
        chunk = chunk.filled(np.nan)
    return chunk.astype(np.float32)
```

---

## Validation

Validate with range-normalised relative error (not value-magnitude-relative,
which inflates errors near zero):

```python
N_SAMPLES   = 10_000
N_T_SAMPLE  = 50       # max timesteps to sample (keeps I/O bounded)
MAX_REL_ERR = 0.025    # 2.5% of variable range — ZFP precision=12 gives ~0.03% mean

for name in src.variables:
    var_src  = src.variables[name]
    var_comp = comp.variables[name]
    if var_src.ndim < 2 or not np.issubdtype(var_src.dtype, np.floating):
        continue   # skip coords / non-float

    # Sample efficiently: pick timesteps first, then spatial points within each
    T    = var_src.shape[0]
    n_t  = min(N_T_SAMPLE, T)
    n_sp = max(1, N_SAMPLES // n_t)
    rng  = np.random.default_rng(42)
    t_idx = np.sort(rng.choice(T, size=n_t, replace=False))

    src_vals, comp_vals = [], []
    for t in t_idx:
        n_spatial = int(np.prod(var_src.shape[1:]))
        flat_sp   = rng.choice(n_spatial, size=min(n_sp, n_spatial), replace=False)
        sp_idx    = np.unravel_index(flat_sp, var_src.shape[1:])
        s = var_src[t];  s = s.filled(np.nan) if hasattr(s, "filled") else s
        c = var_comp[t]; c = c.filled(np.nan) if hasattr(c, "filled") else c
        src_vals.append(np.asarray(s)[sp_idx].astype(np.float64))
        comp_vals.append(np.asarray(c)[sp_idx].astype(np.float64))

    sv = np.concatenate(src_vals)
    cv = np.concatenate(comp_vals)

    # Check fill-value consistency
    fill_to_valid = ~np.isfinite(sv) &  np.isfinite(cv)   # FAIL: fill became data
    valid_to_fill =  np.isfinite(sv) & ~np.isfinite(cv)   # FAIL: valid became fill
    if fill_to_valid.any():
        print(f"[{name}] FAIL — {fill_to_valid.sum()} fill values became valid data")
        continue
    if valid_to_fill.any():
        print(f"[{name}] FAIL — {valid_to_fill.sum()} valid values became fill")

    both_valid = np.isfinite(sv) & np.isfinite(cv)
    sv, cv = sv[both_valid], cv[both_valid]

    val_range = float(sv.max() - sv.min()) if sv.size > 1 else float(np.abs(sv).mean())
    denom     = max(val_range, 1e-10)
    rel_err   = np.abs(sv - cv) / denom
    print(f"[{name}]  mean={rel_err.mean():.2e}  max={rel_err.max():.2e}"
          f"  {'OK' if rel_err.max() <= MAX_REL_ERR else 'FAIL'}")
```

---

## Pitfalls and Notes

| Issue | Resolution |
|-------|-----------|
| `valid_min`/`valid_max` dtype mismatch | Cast to `var.dtype` before `setncatts`; otherwise netCDF4 silently disables masking on float32 |
| Fixed fill sentinel (−9999) degrades ZFP | Use data-relative sentinel: `−FACTOR × max(|vmin|, |vmax|)` |
| Lossless coords masked by metadata | Read `.data` (not the MaskedArray) to bypass metadata-driven masking |
| `set_auto_scale(False)` forgotten | Without it, netCDF4 double-unpacks int16 and silently corrupts data |
| `hdf5plugin` not imported on reader side | Always `import hdf5plugin` before opening files with Blosc or ZFP filters |
| ZFP `createVariable` compression kwargs ignored | Must call `nc_def_var_filter` via ctypes after variable creation |
| ZFP `precision=12` max error at land/sea boundary | Boundary 4×4 blocks mix sentinel and near-zero valid values; the sentinel controls this — see sentinel design above |
| Pre-quantization without a filter | Does NOT reduce file size; useful only for precision control or when a lossless filter is also applied |
| Partial output on crash | Remove partial file/directory in `except` block before re-raising |
| `dst.sync()` not called | Data may be lost if the process crashes mid-write; sync after each variable |
| ZFP + Blosc stacked on same variable | Gives negligible extra benefit — ZFP output is pseudo-random and incompressible by lossless methods |

---

## Typical Compression Ratios and Throughput

The effective read throughput depends on both size reduction and decompression cost.
On fast storage (NVMe, RAM disk), decompression CPU can dominate:

| Method | Size ratio | Read speed (NVMe) | Read speed (HDD/network) |
|--------|-----------|-------------------|--------------------------|
| int16, no filter | **~2×** | ✅ fastest (no decomp) | moderate |
| int16 + Blosc/zstd | 4–8× | ⚠ decomp overhead | good |
| ZFP precision=12 | 6–10× | ⚠ decomp may dominate | ✅ fastest (less I/O) |
| ZFP rate=16 | ~4× | ⚠ decomp overhead | moderate |

> On NVMe (3 GB/s), reading 100 MB of float32 data compressed 6× means ~17 MB I/O (~6 ms)
> but ZFP decompression of the equivalent 100 MB can take 50–200 ms depending on CPU.
> int16 reads 50 MB (~17 ms) + ~1 ms unpack = 18 ms total — potentially faster.
> On HDD (100 MB/s): int16 = 500 ms, ZFP = ~17 ms I/O + 50 ms decomp = ~67 ms → ZFP wins.
