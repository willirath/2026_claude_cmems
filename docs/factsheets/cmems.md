# CMEMS / Copernicus Marine — toolbox factsheet

Reference for the agent accessing Copernicus Marine (CMEMS) ocean data through the
official `copernicusmarine` toolbox. Read before pulling CMEMS data.

## The toolbox

- One package, **`copernicusmarine`** (2.x), exposes both a CLI
  (`copernicusmarine <command>`) and a Python API (`import copernicusmarine`). Add
  it with `uv add copernicusmarine` (needs Python ≥ 3.10).
- **Log in once:** `copernicusmarine login` prompts for the Copernicus Marine
  account and caches encoded credentials at
  `~/.copernicusmarine/.copernicusmarine-credentials`; every later call reads them
  automatically. For non-interactive/batch use, set
  `COPERNICUSMARINE_SERVICE_USERNAME` / `COPERNICUSMARINE_SERVICE_PASSWORD` instead.
  A free account is required — register at <https://data.marine.copernicus.eu>.

## Four verbs

- **`describe`** — search the catalogue.
  `copernicusmarine.describe(contains=["sea surface temperature"], product_id=…, dataset_id=…)`
  returns catalogue metadata (products → datasets → variables). Use it to resolve a
  `dataset_id`; don't hard-code IDs, they drift as products are reprocessed.
- **`open_dataset`** — **lazy / live access, no download.** Returns a dask-backed
  `xarray.Dataset` over the ARCO store; only the chunks a computation touches cross
  the network, and nothing is written to disk.
- **`subset`** — **server-side extraction** of a variable/space/time/depth box to
  one local NetCDF (or Zarr) file. Reproducible and usable offline.
- **`get`** — download the **original native provider files** as-is
  (`filter` / `regex` / `sync` select and mirror them).

Shared selection args for `open_dataset` and `subset`: `dataset_id`,
`variables=[…]`, `minimum/maximum_longitude`, `minimum/maximum_latitude`,
`minimum/maximum_depth`, `start_datetime` / `end_datetime`.

```python
import copernicusmarine
copernicusmarine.login()                       # once; caches credentials

ds = copernicusmarine.open_dataset(            # lazy, ARCO-backed, nothing downloaded
    dataset_id="cmems_mod_glo_phy_my_0.083deg_P1D-m",
    variables=["thetao"],
    minimum_longitude=-10, maximum_longitude=5,
    minimum_latitude=45,   maximum_latitude=60,
    start_datetime="2020-01-01", end_datetime="2020-12-31",
)
sst = ds["thetao"].mean(("longitude", "latitude")).compute()   # only touched chunks transfer
```

## Lazy vs. download — when to use which

- **Open lazily (`open_dataset`)** for interactive exploration, checking a
  dataset's shape, and reductions that pull far less than the full array (a
  point/line time series, an area or depth mean). Only touched chunks transfer;
  nothing is stored.
- **Subset to a file (`subset`)** when the same box is read repeatedly, must be
  reproducible or available offline, or feeds a batch/HPC job that shouldn't hit
  the network per read.
- **Get original files (`get`)** when you need whole files or a full dataset in the
  producer's native format and layout.

On nesh compute nodes every one of these goes through the site proxy — export
`http_proxy` / `https_proxy` first (see the **nesh** factsheet).

## ARCO — and the two chunkings

CMEMS serves data as **ARCO** (Analysis-Ready, Cloud-Optimized): Zarr on object
storage, split into independently addressable chunks fetched by HTTP range request.
That is what makes `open_dataset` / `subset` lazy.

Each dataset is published as **two ARCO stores holding identical data with
different chunk layouts**:

- **geo-series** (`service="arco-geo-series"` / `"geoseries"`) — large lon/lat
  chunks, small time chunks. Fast for a **map / large area at one or a few time
  steps**.
- **time-series** (`service="arco-time-series"` / `"timeseries"`) — small lon/lat
  chunks, large time chunks. Fast for a **long time series at a point / small
  area**.

The toolbox **auto-selects** the better store for the request; pass `service=` only
to override. Matching the store to the access pattern is the difference between
reading a few chunks and reading many — CMEMS quotes 5×–100× throughput differences.
Rule of thumb: **map → geoseries; time series at a location → timeseries.**

## Sources

- Toolbox docs — <https://toolbox-docs.marine.copernicus.eu/en/stable/> ·
  Python interface / signatures — <https://toolbox-docs.marine.copernicus.eu/en/stable/python-interface.html>
- Help Center: [open_dataset](https://help.marine.copernicus.eu/en/articles/8287609-copernicus-marine-toolbox-api-open-a-dataset-or-read-a-dataframe-remotely) ·
  [subset](https://help.marine.copernicus.eu/en/articles/8283072-copernicus-marine-toolbox-api-subset) ·
  [get](https://help.marine.copernicus.eu/en/articles/8286883-copernicus-marine-toolbox-api-get-original-files) ·
  [credentials](https://help.marine.copernicus.eu/en/articles/8185007-copernicus-marine-toolbox-credentials-configuration)
- ARCO format & services — [intro](https://help.marine.copernicus.eu/en/articles/12332770-introduction-to-the-arco-format) ·
  [services / geo-vs-time chunking](https://help.marine.copernicus.eu/en/articles/7969584-copernicus-marine-toolbox-services)
- Data store / portal — <https://data.marine.copernicus.eu/products>
