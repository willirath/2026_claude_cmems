# Project guidelines for agent-assisted CMEMS ocean-data analysis

These are working conventions for this project. Follow them unless the user asks
for something different.

## Python environment & packages

- Use **`uv`** for all Python environment and dependency management.
- Add dependencies with `uv add <package>` and run code with `uv run`.
- Do not use `pip`, `conda`, `mamba`, or manually created virtualenvs.

## Plotting

- **Don't actively style plots** unless it's obviously necessary or the user
  asks for it. The library defaults are fine most of the time — no custom
  colors, sizes, fonts, or themes by default.
- Prefer the **built-in plotting methods** of the data libraries (e.g.
  `xarray`'s `.plot()`, `pandas`' `.plot()`) over building `matplotlib` figures
  and axes by hand.
- Use **`cmocean` colormaps** where they make sense — i.e. for oceanographic
  fields that have a natural perceptual match (e.g. `thermal` for temperature,
  `haline` for salinity, `deep` for depth/bathymetry, `balance` for anomalies
  and other diverging quantities). Pass them via `cmap=cmocean.cm.<name>`. This
  is the one place we deliberately override matplotlib's default colormap;
  otherwise the "don't actively style" rule above still holds.

## Analysis code

- Keep analysis code **simple and idiomatic** to the PyData stack.
- Use `xarray` and `pandas` the way they are meant to be used — label-based
  selection, vectorized operations, and built-in reductions rather than manual
  loops.

## Script & notebook style

- Write analyses as **flat, linear scripts** that run top to bottom. Don't wrap
  logic in `main()`, `if __name__ == "__main__"`, functions, or classes unless
  there's a clear reason.
- Structure the code so it **maps cleanly onto notebook cells** — we will move
  these to Jupyter later. Use short comment-delimited blocks (e.g. open data →
  select → compute → plot); each block should read as a future cell.
- **Inline literal arguments** directly at the call site (`dataset_id`,
  variable names, bounding boxes, dates, etc.) rather than hoisting them into
  module-level constants or config indirection. Prefer the obvious, spelled-out
  call over premature parameterization.

## Naming scheme

When creating analyses or plots, use a consistent naming scheme so figures are
easy to associate with the analysis that produced them:

- Give each analysis a short slug, e.g. `sst_north_atlantic`.
- Name the script/notebook and its outputs with the same slug, e.g.
  `sst_north_atlantic.py` → `sst_north_atlantic_map.png`,
  `sst_north_atlantic_timeseries.png`.
- Keep figures in a predictable location (e.g. a `figures/` directory).

## Project layout

- Analysis scripts (and, later, notebooks) live in **`scripts/`**.
- Figures are written to the top-level **`figures/`** directory.
- Run scripts from the project root so relative paths like `figures/…`
  resolve, e.g. `uv run python scripts/sst_north_atlantic.py`.
