# Agent-assisted ocean-data analysis — getting started

A short guide to install the [Claude Code](https://docs.claude.com/en/docs/claude-code)
CLI on a fresh macOS machine and set up a first project for exploring
[Copernicus Marine (CMEMS)](https://marine.copernicus.eu/) ocean data with agent
assistance.

---

## 1. Install Claude Code on a vanilla macOS

You need a terminal (the built-in **Terminal.app** is fine) and an Anthropic
account with Claude Code access (Claude Pro/Max subscription or an API account).

### 1a. Install the CLI

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

---

## 2. Install VS Code

Download and install Visual Studio Code from the official page:

<https://code.visualstudio.com/download>

Open the downloaded app, then use **File → Open Folder…** and navigate to your
project directory (see below) to start working there.

---

## 3. Set up your first CMEMS project

Create a dedicated working directory and start Claude Code inside it. Claude Code
works best when launched from the root of the project it should reason about.

```bash
mkdir -p "$HOME/projects/cmems_claude_first_steps"
cd "$HOME/projects/cmems_claude_first_steps"

# launch the agent in this directory
claude
```

### Add the project guidelines

This repository includes an example [`CLAUDE.md`](CLAUDE.md) with working
conventions for the project (Python via `uv`, plotting and analysis style, a
figure-naming scheme). Claude Code loads a `CLAUDE.md` from the project root
automatically each session.

Download it into your project directory and open it in VS Code to read what the
agent will follow:

1. Open the [`CLAUDE.md`](CLAUDE.md) file, use **Download raw file**, and save it
   as `CLAUDE.md` in `$HOME/projects/cmems_claude_first_steps/`.
2. In VS Code, **File → Open Folder…** the project directory, then open
   `CLAUDE.md` and read through the guidelines.

### Suggested first steps inside the session

Once Claude Code is running in `cmems_claude_first_steps/`, try asking it in
plain language, for example:

- *"Set up a Python environment for CMEMS ocean-data analysis using
  `copernicusmarine`, `xarray`, and `matplotlib`."*
- *"Write a `CLAUDE.md` documenting how this project is organized so future
  sessions have context."*
- *"Download a small sea-surface-temperature subset from CMEMS and plot a map."*

The agent will propose commands and file edits and ask for your approval before
running them.

### A couple of tips

- **Run one project per directory.** Keep unrelated analyses in separate folders
  under `$HOME/projects/` so each has its own context.
- **Keep the `CLAUDE.md` up to date.** It's loaded automatically each session and
  is the best place to record conventions, data locations, and goals — edit it
  as the project grows.
- **You need CMEMS credentials** to download data. Register (free) at
  <https://marine.copernicus.eu/> and log in once with
  `copernicusmarine login` — the agent can walk you through this.

---

## Handy references

- Claude Code docs: <https://docs.claude.com/en/docs/claude-code>
- Copernicus Marine toolbox: <https://help.marine.copernicus.eu/en/collections/9080063-copernicus-marine-toolbox>
- `claude doctor` — diagnose a broken install
- `/help` inside a session — list all in-session commands
