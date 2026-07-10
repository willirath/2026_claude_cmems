# Model outputs — netCDF, chunking, staying lazy factsheet

Reference for the agent reading large ocean-model / CMEMS netCDF output efficiently
and without running out of memory. Applies to NEMO files and downloaded CMEMS
subsets alike; for NEMO grid semantics see the **NEMO** factsheet.

## Read the header first (CDL)

Before writing code for a big file or for multiple files, inspect their structure —
this reads **zero data**:

```bash
ncdump -h -s file.nc        # -h: header only   -s: show storage/chunking attrs
```

The full CDL gives dimensions, variables, and units, and — with `-s` — the on-disk
layout: `_ChunkSizes`, `_DeflateLevel`, `_Shuffle`, `_Storage`. The same appears in
Python as `ds[var].encoding` (`chunksizes`, `zlib`, `complevel`, `shuffle`). Reading
the header is enough to orient yourself — no need to build a catalogue system for it.

## netCDF-4 chunking & compression — and the read penalty

- A netCDF-4 file is an HDF5 file; each variable is stored as **fixed-shape chunks**
  (blocks), optionally **shuffle**-filtered and **DEFLATE**-compressed (level 0–9).
  The chunk shape is decided **when the file is written**.
- **The chunk is the smallest unit of I/O.** To return *any* element, the reader
  fetches the whole chunk containing it and decompresses it in full.
- So a slice **misaligned** with the chunk layout causes **read amplification**:
  every chunk the slice overlaps is read and decompressed whole to hand back a
  little data. Classic cases — a time series at one grid point when chunks span many
  time steps; a full 2-D map when chunks are small tiles. The same file can serve
  one access pattern in milliseconds and the other thousands of times slower
  (Unidata documents a ~14,000× gap on one file).
- This is a property of **how the file was written** — there's nothing to fix
  client-side short of rewriting/rechunking (`nccopy -c`). Knowing it explains slow
  reads and tells you how to chunk on the client.

## Reading without blowing up memory

- **Align dask chunks to the disk chunks when you can.** Dask chunks that are
  integer multiples of the on-disk `_ChunkSizes` let each stored chunk be read and
  decompressed once. `open_dataset(..., chunks={})` maps one dask chunk to one
  on-disk chunk; `chunks="auto"` picks multiples. This is a best-effort speed-up,
  not a hard rule: when the access pattern the analysis needs fights the on-disk
  layout (e.g. a long point time series from a map-chunked file), you can't align
  around it — you're forced to accept the read overhead, since the layout is fixed
  in the file.
- **Size chunks by the trade-off, not a magic number.** A dask chunk has to be
  small enough that the several a worker holds at once (a reduction can have a few
  in flight per worker) fit comfortably in its memory, but large enough that the
  task graph stays small — every extra task adds ~milliseconds of scheduler
  overhead, so millions of tiny chunks bog dask down before any data moves. Tens to
  a few hundred MB per chunk is the usual sweet spot; on a large-memory HPC
  allocation push toward the high end (or past it), on a laptop stay low. Fewer,
  bigger chunks trade memory headroom for a cheaper graph.
- **Chunk arrays you combine the same way.** dask can't recompute a task, so it
  keeps each chunk's output in memory until *every* task that consumes it has run.
  If two arrays you add or multiply are chunked on different axes, no chunk of
  either can be released until the whole result is done — so both arrays end up
  fully in memory at once:

  ```python
  a = a.chunk({"x": 1, "y": -1})   # striped in y
  b = b.chunk({"x": -1, "y": 1})   # striped in x — orthogonal to a
  c = a + b   # every chunk of a and b must stay live until all of c is computed
  ```

  Give co-combined arrays a common chunking along their shared dims instead.
- **Stay lazy.** `.values` / `.compute()` / `.load()` / `.plot()` pull data into
  memory *now* — on a global 3-D field that's tens of GB into one process. Reduce or
  subset **first** (`.isel`, `.mean`), then materialise only the small result. This
  is the single biggest OOM preventer.
- **Open many files lazily:** `xr.open_mfdataset(paths, data_vars="minimal",
  coords="minimal", compat="override")` so xarray doesn't re-read the big coords in
  every file; `engine="h5netcdf"` is often faster.
- **dask on HPC:** a single-node `LocalCluster` inside an allocation covers most
  work; spill to node-local scratch (`local_directory=os.environ["TMPDIR"]`), never
  a shared filesystem. Workers never run on the login node.

## Sources

- Unidata — [Chunking: why it matters](https://www.unidata.ucar.edu/blogs/developer/entry/chunking_data_why_it_matters)
  (per-chunk (de)compression; the access-pattern example) ·
  [ncdump `-s` special attributes](https://docs.unidata.ucar.edu/nug/current/netcdf_utilities_guide.html)
- HDF5 — [chunking](https://support.hdfgroup.org/documentation/hdf5/latest/hdf5_chunking.html)
- xarray — [dask / chunk alignment](https://docs.xarray.dev/en/stable/user-guide/dask.html)
