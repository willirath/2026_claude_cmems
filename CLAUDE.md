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

## Analysis code

- Keep analysis code **simple and idiomatic** to the PyData stack.
- Use `xarray` and `pandas` the way they are meant to be used — label-based
  selection, vectorized operations, and built-in reductions rather than manual
  loops.

## Naming scheme

When creating analyses or plots, use a consistent naming scheme so figures are
easy to associate with the analysis that produced them:

- Give each analysis a short slug, e.g. `sst_north_atlantic`.
- Name the script/notebook and its outputs with the same slug, e.g.
  `sst_north_atlantic.py` → `sst_north_atlantic_map.png`,
  `sst_north_atlantic_timeseries.png`.
- Keep figures in a predictable location (e.g. a `figures/` directory).
