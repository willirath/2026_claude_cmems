# Agent-assisted ocean-data analysis — getting started

A short guide to install the [Claude Code](https://docs.claude.com/en/docs/claude-code)
CLI on a fresh macOS machine and set up a first project for exploring
[Copernicus Marine (CMEMS)](https://marine.copernicus.eu/) ocean data with agent
assistance.

---

## 1. Install Claude Code on a fresh macOS

You need a terminal (the built-in **Terminal.app** is fine) and an Anthropic
account with Claude Code access (Claude Pro/Max subscription or an API account).

### 1a. Install the claude command-line interface

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Then restart your terminal so the `claude` command is on your `PATH`. Verify the
install:

```bash
claude --version
claude doctor      # checks your setup and reports any problems
```

### 1b. First launch & authentication

Start Claude Code from any directory and follow the login prompt:

```bash
claude
```

On first run it opens a browser to authenticate. Choose the option that matches
your account (Claude subscription or Anthropic API/Console). After login you drop
into an interactive session — type `/help` to see commands, and `/exit` to quit.

Keep it updated over time with:

```bash
claude update
```

### 1c. Install uv (Python package manager)

[`uv`](https://docs.astral.sh/uv/) is a simple package manager for python environments and dependencies.
Install it once:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart your terminal (or `source` your shell profile) so `uv` is on your
`PATH`, then verify:

```bash
uv --version
```

You don't need to create environments or install packages by hand — the agent
runs `uv init` and `uv add <package>` for you as the analysis grows (see the
example session below). You just need `uv` itself available.

---

## 2. Install VS Code

Download and install Visual Studio Code from the official page:

<https://code.visualstudio.com/download>

Open the downloaded app, then use **File → Open Folder…** and navigate to your
project directory (see below) to start working there.

---

## 3. Set up your first CMEMS project

First create a dedicated working directory for the project:

```bash
mkdir -p "$HOME/projects/cmems_claude_first_steps"
```

Then open that folder in VS Code (**File → Open Folder…**) so you can view and
edit its files as you go.

### Add the project guidelines

An example [`CLAUDE.md`](docs/CLAUDE.md) with working conventions for this kind of
project (Python via `uv`, plotting and analysis style, a figure-naming scheme)
lives alongside this guide. Claude Code loads a `CLAUDE.md` from the project
root automatically each session, so it will pick these up without you having to
repeat them.

Grab the contents of the example [`CLAUDE.md`](docs/CLAUDE.md) and save them as a
file named `CLAUDE.md` in your project directory, then read through it to see
what the agent will follow.

### Launch Claude Code

Claude Code works best when launched from the root of the project it should
reason about, so start it from inside the project directory:

```bash
cd "$HOME/projects/cmems_claude_first_steps"
claude
```

### Suggested first steps inside the session

Once Claude Code is running, drive the analysis by asking it in plain language.
These are the actual prompts that drove the example session:

- *"Create a plot of North Atlantic sea-surface temperature today from the
  Copernicus analysis/forecast product. Trim the color limits to the actual data
  range."*
- *"Now add a second plot with sea-surface salinity (SSS)."*
- *"Finally, create a T–S plot based on the same SSS and SST fields."*

The agent will propose commands and file edits and ask for your approval before
running them. For a walk-through of what it does with each prompt — from
environment setup through the rendered figures — see the annotated
[example session](docs/example_session.md).

### Turning scripts into notebooks (jupytext)

Start with the flat scripts above. When you want to work in a real Jupyter
notebook, just ask — the agent uses [jupytext](https://jupytext.readthedocs.io/)
so you get the best of both: it keeps a plain `.py` file as the source it edits
(clean, readable diffs) and pairs it with a `.ipynb` you open and run in Jupyter
or VS Code. You don't need to learn jupytext yourself; the conventions in
`CLAUDE.md` tell the agent how to keep the two in sync.

### Moving to an HPC cluster (nesh)

When you outgrow the laptop and want to work against **NEMO** model output on
**nesh** (the CAU Kiel / GEOMAR HPC system), keep this same project setup and add
the short on-ramp in **[docs/hpc_nesh.md](docs/hpc_nesh.md)**. It covers where to
run Claude (on the cluster, not the laptop), one-time SSH/tunnel setup, running
under SLURM instead of on the login node, reaching a compute-node Jupyter through
an SSH tunnel, keeping the agent from stressing the shared filesystem while
staying oriented via a small data catalogue, and the NEMO / dask specifics the
agent needs to stay correct and in memory. It ships an appendable
[`CLAUDE.md` snippet](docs/claude_md_nesh_snippet.md), an example
[`.claude/settings.json`](docs/settings_nesh_example.json), and a
[catalogue template](docs/catalogue_template/). The laptop path above stays your
day-one starting point — the aim of that doc is just to get you analysing on nesh
at all; you can tune the workflow later.

### A couple of tips

- **Run one project per directory.** Keep unrelated analyses in separate folders
  under `$HOME/projects/` so each has its own context.
- **Keep the `CLAUDE.md` up to date.** It's loaded automatically each session and
  is the best place to record conventions, data locations, and goals — edit it
  as the project grows.
- **You need CMEMS credentials** to download data. Register (free) at
  <https://marine.copernicus.eu/> and log in once with
  `copernicusmarine login` — the agent can walk you through this.
