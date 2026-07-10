#!/usr/bin/env bash
# remote_tunnel_chrome.sh — reach a compute-node JupyterLab through the nesh login node.
#
#   ./remote_tunnel_chrome.sh <user>@nesh-login.rz.uni-kiel.de 'http://nesh-clk399:8888/?token=abc123…'
#
# Opens a dynamic SOCKS proxy through the login node, then launches an isolated
# Chrome/Chromium routed through it, pointed at the token URL from the Jupyter
# job output file. Works on macOS, Linux, and Windows (run it in Git Bash). The
# same script is inlined in docs/factsheets/remote-work.md — keep the two in sync.
set -euo pipefail

LOGIN="${1:?pass the login node, e.g. jdoe@nesh-login.rz.uni-kiel.de (an ssh-config alias works too)}"
URL="${2:?pass the compute-node token URL from the Jupyter job output file}"

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; *) WINDOWS=0 ;; esac

# SOCKS port: $SOCKS_PORT if set, else ask python for a free ephemeral port,
# else fall back to a fixed default and hope it is free. On Windows, skip the
# python probe (the python on PATH is often the Microsoft Store stub, and the
# bind can trip the firewall dialog) and go straight to the default.
PY_FREE_PORT='import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1])'
if [ "${WINDOWS}" = 1 ]; then
  PORT="${SOCKS_PORT:-54321}"
else
  PORT="${SOCKS_PORT:-$( { python3 -c "${PY_FREE_PORT}" || python -c "${PY_FREE_PORT}"; } 2>/dev/null || echo 54321)}"
fi

# Chrome/Chromium binary: $BROWSER_BIN if set, else the first one found
# (Linux package names, then macOS app paths, then Windows installs as Git
# Bash sees them).
if [ -z "${BROWSER_BIN:-}" ]; then
  for candidate in chromium chromium-browser google-chrome google-chrome-stable \
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      "/Applications/Chromium.app/Contents/MacOS/Chromium" \
      "/c/Program Files/Google/Chrome/Application/chrome.exe" \
      "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
      "/c/Users/${USERNAME:-}/AppData/Local/Google/Chrome/Application/chrome.exe"; do
    if command -v "${candidate}" >/dev/null 2>&1; then BROWSER_BIN="${candidate}"; break; fi
  done
fi
: "${BROWSER_BIN:?no Chrome/Chromium found — set BROWSER_BIN to your browser binary}"

# Chrome on Windows is a native app: hand it a Windows-style profile path — it
# does not understand Git Bash's /tmp. Elsewhere a throwaway tmpdir is fine.
if [ "${WINDOWS}" = 1 ]; then
  USER_DATA_DIR="${USERPROFILE}\\Chrome-Proxy-${PORT}"
else
  USER_DATA_DIR="$(mktemp -d)"
fi

echo "SOCKS proxy localhost:${PORT} via ${LOGIN}; browser: ${BROWSER_BIN}" >&2

# -f backgrounds ssh after auth; `sleep 60` holds the tunnel open long enough
# for the browser to start and connect (cold starts on Windows are slow), after
# which ssh stays up while that connection is live.
ssh -f -D "localhost:${PORT}" "${LOGIN}" sleep 60

# Chrome's own phone-home traffic (Google endpoints) goes direct to the open
# internet instead of through the HPC login node.
GOOGLE_BYPASS='google.com;*.google.com;google.de;*.google.de;google.fr;*.google.fr;googleapis.com;*.googleapis.com;googleapis.de;*.googleapis.de;googleapis.fr;*.googleapis.fr;*.gvt1.com;*.gstatic.com'

# Isolated browser through the proxy. --proxy-bypass-list="<-loopback>" re-enables
# SOCKS for loopback/internal hosts, which Chrome blocks by default.
"${BROWSER_BIN}" \
  --new-window --no-first-run \
  --proxy-server="socks5://localhost:${PORT}" \
  --proxy-bypass-list="<-loopback>;${GOOGLE_BYPASS}" \
  --user-data-dir="${USER_DATA_DIR}" \
  "${URL}"
