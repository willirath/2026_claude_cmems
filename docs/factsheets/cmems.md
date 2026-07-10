# CMEMS / Copernicus Marine — toolbox factsheet

Reference for the agent accessing Copernicus Marine (CMEMS) ocean data through the
official `copernicusmarine` toolbox. Read before pulling CMEMS data.

## The toolbox

- This factsheet is about **`copernicusmarine` v2.x** — one package that exposes
  both a CLI (`copernicusmarine <command>`) and a Python API
  (`import copernicusmarine`). Add it with `uv add copernicusmarine` (uv resolves a
  compatible Python itself; don't pin one here).
- **Log in once per system:** `copernicusmarine login` prompts for the Copernicus
  Marine account and caches encoded credentials at
  `~/.copernicusmarine/.copernicusmarine-credentials`. After that every call reads
  them automatically — **including batch and non-interactive jobs**, which pick up
  the cached file with no extra step; you do not log in again per session or per
  script. The env vars `COPERNICUSMARINE_SERVICE_USERNAME` /
  `COPERNICUSMARINE_SERVICE_PASSWORD` are an alternative only where no cached login
  exists (a fresh container, CI). A free account is required — register at
  <https://data.marine.copernicus.eu>.

## Four verbs

- **`describe`** — search the catalogue.
  `copernicusmarine.describe(contains=["sea surface temperature"], product_id=…, dataset_id=…)`
  returns catalogue metadata (products → datasets → variables). Use it to resolve a
  `dataset_id`; don't hard-code IDs, they drift as products are reprocessed.
- **`open_dataset`** — **lazy / live access, no download.** Returns a dask-backed
  `xarray.Dataset` over the ARCO store; only the chunks a computation touches cross
  the network, and nothing is written to disk. **Open, inspect, then slice in
  xarray** — with the lazy dataset in hand you read the real variable names,
  coordinate ranges, and chunking before selecting, instead of guessing them as call
  arguments. One catch: the ARCO **store is chosen at open time and the returned
  dataset is locked to it** — `.sel` / `.isel` slice that store but can't switch it
  (see *ARCO* below). So leave *variables and exact ranges* to xarray, but **steer
  the store to your access pattern at open** with `service=` — `"arco-geo-series"`
  for a map, `"arco-time-series"` for a point/area time series (you know which before
  you know the coords). A bare `open_dataset(dataset_id=…)` leaves it on the geoseries
  default, the slow layout for a long time series.
- **`subset`** — **server-side extraction** of a variable/space/time/depth box to
  one local NetCDF (or Zarr) file. Reproducible and usable offline. Here the box args
  *are* the interface: `variables=[…]`, `minimum/maximum_longitude`,
  `minimum/maximum_latitude`, `minimum/maximum_depth`, `start_datetime` /
  `end_datetime`. `subset` also has a matching **CLI** form for scripted / formalised
  workflows: `copernicusmarine subset --dataset-id … --variable … --minimum-longitude
  … --start-datetime …`.
- **`get`** — download the **original native provider files** as-is
  (`filter` / `regex` / `sync` select and mirror them).

Lazy path — open (steering the store to the access pattern), inspect, then slice with
xarray. Credentials come from the one-time `login`, so the script needs no `login()`
call:

```python
import copernicusmarine

# the access pattern here is a time series over a small area -> time-series store
ds = copernicusmarine.open_dataset(            # lazy, ARCO-backed, nothing downloaded
    dataset_id="cmems_mod_glo_phy_my_0.083deg_P1D-m",
    service="arco-time-series",
)
# inspect ds first — variables, coord ranges, chunk sizes — then slice in xarray:
sst = (
    ds["thetao"]
    .sel(longitude=slice(-10, 5), latitude=slice(45, 60),
         time=slice("2020-01-01", "2020-12-31"))
    .mean(("longitude", "latitude"))
    .compute()                                 # only the touched chunks transfer
)
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

All of these need outbound network access; in a proxied environment, export
`http_proxy` / `https_proxy` before calling the toolbox.

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

For a given request the toolbox **auto-selects the cheaper store** — for both
`open_dataset` and `subset` it counts how many Zarr chunks each layout would need for
the requested variables/box and picks the smaller (geoseries is the fallback on a
tie, when neither count can be computed, or when only one store is published).
Matching the store to the access pattern is the difference between reading a few
chunks and reading many — CMEMS quotes 5×–100× throughput differences. The rule of
thumb: **map → geoseries; time series at a location → timeseries.**

The store is fixed **at open** and scored from that call's arguments — so a bare
`open_dataset(dataset_id=…)` with no box has nothing to optimise against and defaults
to geoseries. When you mean to slice in xarray afterward, pass `service=` at open to
land on the right layout rather than relying on the auto-selection.

## Sources

- Toolbox docs — <https://toolbox-docs.marine.copernicus.eu/en/stable/> ·
  Python interface / signatures — <https://toolbox-docs.marine.copernicus.eu/en/stable/python-interface.html>
- Help Center: [open_dataset](https://help.marine.copernicus.eu/en/articles/8287609-copernicus-marine-toolbox-api-open-a-dataset-or-read-a-dataframe-remotely) ·
  [subset](https://help.marine.copernicus.eu/en/articles/8283072-copernicus-marine-toolbox-api-subset) ·
  [get](https://help.marine.copernicus.eu/en/articles/8286883-copernicus-marine-toolbox-api-get-original-files) ·
  [credentials](https://help.marine.copernicus.eu/en/articles/8185007-copernicus-marine-toolbox-credentials-configuration)
- ARCO format & services — [intro](https://help.marine.copernicus.eu/en/articles/12332770-introduction-to-the-arco-format) ·
  [services / geo-vs-time chunking](https://help.marine.copernicus.eu/en/articles/7969584-copernicus-marine-toolbox-services)
- Source & issues (definitive on behaviour, e.g. the store-selection logic above) —
  <https://github.com/mercator-ocean/copernicus-marine-toolbox>
- Data store / portal — <https://data.marine.copernicus.eu/products>
