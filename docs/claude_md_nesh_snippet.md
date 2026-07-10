# CLAUDE.md — nesh HPC snippet

Append this block to your project `CLAUDE.md` when the project runs on **nesh**
(CAU Kiel / GEOMAR HPC). It's the short version the agent honours by default; the
reasoning and setup are in [`hpc_nesh.md`](hpc_nesh.md). Copy everything below the
line, then fix the `<placeholders>` for your account.

> `CLAUDE.md` is a strong *nudge*, not enforcement. The filesystem rules below are
> backed by real deny rules in `.claude/settings.json` (see
> [`settings_nesh_example.json`](settings_nesh_example.json)) and by launching
> `claude` from this project directory. Keep all three in place.

---

## HPC environment (nesh)

- **Scheduler is SLURM** (`sbatch`, `srun`, `salloc`, `squeue`) — not PBS/NQSII.
  Ignore any `qsub`/`#PBS` advice.
- **Never run heavy compute on the login node.** Editing, reading the catalogue,
  and `ncdump -h` are fine there. Real computation goes in an allocation:
  `srun --pty --time=01:00:00 --mem=8000 --partition=base /bin/bash`, or a batch
  job on `base`. When memory is tight, raise `--mem` before tuning anything.
- **Storage** (`<inst>` = `cau` or `geomar`): code and this project in `$HOME`
  (`/gxfs_home/<inst>/<user>`, backed up, small). **All job/data I/O in `$WORK`**
  (`/gxfs_work/<inst>/<user>`, large, not backed up). dask spill and scratch go to
  node-local `$TMPDIR` (`/scratch/SlurmTMP/<user>.<jobid>`), never a shared FS.
- **Internet is behind a proxy on `base` compute nodes.** Before anything
  downloads (`copernicusmarine`, `uv`, `pip`, `git`) inside a `base` job/shell:
  ```bash
  export http_proxy=http://10.0.7.235:3128
  export https_proxy=http://10.0.7.235:3128
  ```
  Login / `interactive` nodes have direct networking. Confirm the exact proxy with
  the user if a download hangs.
- **Python via `uv` only** (`uv add`, `uv run`) — not conda (its file count
  exhausts the home inode quota).

## Filesystem discipline (shared parallel FS — this matters)

- **Do NOT run `find`, `grep -r`/`grep -R`, `ls -R`, `du`, or `tree` over the data
  tree, `$WORK`, `$HOME`, or any large directory.** It's a shared parallel
  filesystem; recursive walks cause metadata storms that slow the whole cluster.
  (These are also denied in `.claude/settings.json`.)
- **To learn what data exists and how it's shaped, read the catalogue** —
  `catalogue/DATA.md`, `catalogue/tree.txt`, and the `catalogue/*.cdl` header
  dumps. Treat it as the source of truth for paths and layout.
- **Reach data files by explicit path only** (paths come from the catalogue).
  Never scan for them. If you need a file that isn't catalogued, **ask the user to
  add it** — propose the exact `ncdump -h -s <file> > catalogue/<name>.cdl` command
  and let them run it.
- Searching this small project directory (your own code) with Grep/Glob is fine —
  it's local and cheap. The rule is about the *data* tree, not the project.

## NEMO / netCDF / xarray / dask conventions

- **Triage every file first.** Run `ncdump -h` (or check `ds.coords`). If
  `longitude`/`latitude` are **1-D** dimension coordinates (a regridded CMEMS
  product), `.sel(longitude=…, latitude=…)` works — the C-grid rules don't apply.
  If `nav_lon`/`nav_lat` are **2-D** over `(y, x)`, it's native NEMO/ORCA — apply
  the rules below.
- **Native ORCA is a staggered C-grid**, output split into `grid_T`/`grid_U`/
  `grid_V`/`grid_W` files. `nav_lon`/`nav_lat` are 2-D curvilinear over `(y, x)`,
  so `ds.sel(lon,lat)` fails — select with **`.isel`**, or use `cf-xarray` /
  `xgcm` / `xnemogcm` / `xESMF`.
- **The silent trap: never do arithmetic mixing `grid_T`/`grid_U`/`grid_V` by
  index.** They share the same `(y, x)` dims but sit half a cell apart, so xarray
  combines them with no error and the result is quietly wrong (e.g. current speed
  needs `u`, `v` moved to T-points first via `xgcm`/`xnemogcm`). Likewise weight
  spatial means by cell area `e1t*e2t` (and `e3t` for volumes) and apply `tmask` —
  an unweighted `.mean` over `(y, x)` is biased. Grid metrics/masks live in
  `mesh_mask.nc` / `domain_cfg.nc` (paths in `catalogue/DATA.md`).
- Be wary of the tripolar **north-fold** rows (duplicated cells in NEMO ≤4.0.x,
  vector sign flips). High-res (~1/100°) comes from AGRIF nests with `1_`/`2_`
  filename prefixes. Per-processor tiles need `rebuild_nemo` first — check the
  catalogue.
- **Stay lazy.** Never call `.values`/`.compute()`/`.load()`/`.plot()` on a full
  global 3-D field — reduce/subset (`.isel`, `.mean`) first, then materialise only
  the small result. This is the main OOM preventer.
- Open many files with `open_mfdataset(..., data_vars="minimal", coords="minimal",
  compat="override")` (avoids re-reading the big 2-D coords); `engine="h5netcdf"`
  is often faster. Aim for ~100 MB dask chunks; aligning to on-disk `_ChunkSizes`
  (from the `.cdl`) is a speed-up, not required to open the file.
- dask: single-node `LocalCluster` inside an allocation, with
  `local_directory=os.environ["TMPDIR"]`; workers never on the login node; use
  `SLURMCluster` only when one node isn't enough (specify `memory="…GiB"`).

## Working with the human

- The user handles SSH and the Jupyter SSH/SOCKS5 tunnel themselves. Assist by
  explaining, drafting job scripts, and troubleshooting — don't try to `ssh` or
  open tunnels on their behalf.
- Prefer proposing an `sbatch` script or `srun` command over running long computes
  yourself in the session.
