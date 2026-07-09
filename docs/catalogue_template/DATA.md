# Data catalogue

> This is the agent's map of the available data. It exists so the agent (and you)
> never have to walk the shared filesystem to find out what's where — see
> [`../hpc_nesh.md`](../hpc_nesh.md) §6. Keep it current: when new data appears,
> add an entry and a `.cdl` header dump (`./regenerate.sh` helps). Draft entries
> with the agent, then **you** run the bounded commands and commit the result.

**Do not `find`/`grep -r`/`ls -R` the paths below.** They point at large trees on
a shared parallel filesystem. Read this file and the `*.cdl` dumps instead; open
data files by explicit path only.

Layout snapshot (regenerate deliberately, shallow depth): [`tree.txt`](tree.txt).

---

## Datasets

### `<dataset-slug>` — <one-line description>

- **Path (do not walk):** `<stable/root/path>`
- **Model / product:** `<e.g. NEMO ORCA025 hindcast, run XYZ>` /
  `<e.g. CMEMS GLOBAL_ANALYSISFORECAST_PHY_001_024>`
- **Grid:** `<ORCA025 (1/4°) tripolar | eORCA025 | AGRIF nest 1_ over parent … | CMEMS regular 1/12° lon-lat>`
- **Grid/mesh files:** `<path to mesh_mask.nc / domain_cfg.nc / coordinates.nc>`
- **File naming:** `<e.g. NEMO_ORCA025_1m_YYYYMM_grid_{T,U,V,W}.nc>`
- **Rebuilt?** `<already single-file | per-processor tiles, needs rebuild_nemo>`
- **Time coverage / per-file period:** `<e.g. 1990–2019, one file per month>`
- **Approx. size:** `<e.g. ~40 GB per grid_T year>`
- **Key variables:** `<e.g. thetao (T), so (S), zos (SSH) in grid_T; uo/vo in grid_U/V>`
- **On-disk chunking / deflation:** `<summary; full detail in the .cdl>` →
  header dump: [`<dataset-slug>_grid_T.cdl`](<dataset-slug>_grid_T.cdl)
- **Gotchas:** `<2-D nav_lon/nav_lat → use .isel; north-fold rows; masks in mesh_mask; …>`

<!-- Copy the block above for each additional dataset. -->

---

## Worked example (delete once you have real entries)

### `orca025_hindcast` — global ¼° NEMO temperature/salinity/SSH

- **Path (do not walk):** `/gxfs_work/geomar/<user>/data/ORCA025/hindcast/`
- **Model / product:** NEMO ORCA025 hindcast, run `2020-ref`
- **Grid:** ORCA025 (1/4°) tripolar; north fold at the top rows
- **Grid/mesh files:** `/gxfs_work/geomar/<user>/data/ORCA025/mesh_mask.nc`
- **File naming:** `ORCA025-2020ref_1m_<YYYY>0101_<YYYY>1231_grid_{T,U,V,W}.nc`
- **Rebuilt?** already single-file (rebuilt at run time)
- **Time coverage / per-file period:** 1958–2019, one file per year, monthly means
- **Approx. size:** ~12 GB per `grid_T` year
- **Key variables:** `grid_T`: `thetao`, `so`, `zos`; `grid_U`/`grid_V`: `uo`/`vo`
- **On-disk chunking / deflation:** chunked `(time=1, deptht=75, y=300, x=400)`,
  deflate level 1, shuffle on → full header:
  [`example_orca025_grid_T.cdl`](example_orca025_grid_T.cdl)
- **Gotchas:** `nav_lon`/`nav_lat` are 2-D `(y, x)` → select with `.isel`, not
  `.sel(lon, lat)`; land is masked via `tmask` in `mesh_mask.nc`; dask chunks must
  be multiples of `(1, 75, 300, 400)`.
