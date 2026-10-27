# Choosing a host

Juniper runs in Docker on any 64-bit machine. Pick one of three host types and set `HOST_TYPE` in `juniper.local.env`; the scripts adapt paths, permissions and Tailscale exposure to it.

| | `ugos` | `linux` | `local` |
| --- | --- | --- | --- |
| What | UGREEN NAS with UGOS | any always-on Linux box: Raspberry Pi, mini PC, other NAS, home server, VPS | this computer, with Docker Desktop |
| Good for | the setup this repo was built and tested on | the default for a new install | trying Juniper out |
| Always on | yes | yes | only while the computer is awake |
| Reached from your phone | Tailscale (UGOS forwards automatically) | Tailscale (`host.sh expose`) | no, only Telegram |
| `sudo` | yes, you run each host step | yes, you run each host step | no: Claude Code can run every step itself |
| Notes for Obsidian | Syncthing container | Syncthing container | mount the vault folder directly |
| `JUNIPER_DIR` | `/volume1/docker/openclaw` | `/opt/juniper` | `~/juniper-data` |

Telegram works the same on all three: the bot polls Telegram, so no host needs an open port.

## Requirements (all hosts)

- **64-bit CPU**, amd64 or arm64. The pinned image `ghcr.io/openclaw/openclaw:2026.10.5` is published for both (checked against the registry on 2026-10-27).
- **4 GB RAM or more.** The gateway used about 1.7 GB under load and was OOM-killed at a 2 GB limit, so the compose file sets 3 GB. Change it with `GATEWAY_MEM_LIMIT` in `.env` if you must.
- **Docker Engine with the compose plugin** (`docker compose version` works), plus `bash`, `curl`, `openssl` and `python3`.
- **Tailscale** for the server types, so the Control UI is reachable from your devices and nothing else.

## `ugos`: UGREEN NAS

- Install the Tailscale app from the UGOS app centre. It runs in **userspace mode**: the NAS has no `100.x` interface, and tailnet connections to the NAS are forwarded to `127.0.0.1`. That's why every port is published on `127.0.0.1` only and nothing more is needed.
- Enable SSH in *Control Panel → Terminal* while you configure; turn it off afterwards.
- Your user isn't in the `docker` group, so every docker command needs `sudo`. Keep it that way.
- If you use the UGOS *Docker → Project* screen, name the project `openclaw-agents`. Some users report that the UI rewrites compose files; re-run `host.sh compose` if it does.

## `linux`: Raspberry Pi or any Linux server

- **Raspberry Pi:** a Pi 5 (or Pi 4) with 4 GB or more; 8 GB is comfortable. Use **Raspberry Pi OS Lite (64-bit)**; a 32-bit OS can't run the image. Boot from an SSD if you can: SQLite state and logs wear out SD cards.
- **Docker:** install Docker Engine from [docs.docker.com/engine/install](https://docs.docker.com/engine/install/) (Debian instructions for Raspberry Pi OS). Don't add your user to the `docker` group, because that is root-equivalent; `host.sh` runs with `sudo`.
- **Tailscale:** `curl -fsSL https://tailscale.com/install.sh | sh`, then `sudo tailscale up`. Get the IP with `tailscale ip -4` and set `CONTROL_UI_ORIGIN=http://<that ip>:18789`.
- **Exposure:** a normal Tailscale install has a real `100.x` interface but doesn't forward to `127.0.0.1` by itself. `sudo bash ~/juniper/host.sh expose` runs `tailscale serve --bg --tcp=18789 tcp://localhost:18789`, which forwards that port from the tailnet only and survives reboots. `expose syncthing` does the same for 8384 and 22000 in Phase 4. Undo with `sudo tailscale serve reset`. Don't bind the container to the `100.x` IP instead: Docker fails at boot when Tailscale isn't up yet.
- **VPS:** works the same way, but your Apple app passwords and mail summaries then live at a hosting provider. A device at home is the better default.

## `local`: this computer

- Install **Docker Desktop**. On Windows, run Claude Code and this repo inside **WSL2** (Ubuntu) with Docker Desktop's WSL integration on, and keep `JUNIPER_DIR` inside the WSL filesystem (e.g. `/home/you/juniper-data`), not under `/mnt/c`.
- Set `HOST_SSH=` (empty), `JUNIPER_DIR=~/juniper-data`, `CONTROL_UI_ORIGIN=http://localhost:18789`. Run `host.sh` without `sudo`; it refuses to run as root in this mode.
- **Notes:** skip Syncthing. Set `OBSIDIAN_ASSISTANT_DIR=/path/to/your/vault/Assistant` in `.env`, and only that folder is mounted.
- **Trade-offs, in plain words:**
  - The agents stop when the computer sleeps, and scheduled jobs (morning overview, inbox summaries) are skipped.
  - The agents run on the machine you use every day. Docker Desktop's VM is the security boundary instead of a separate device.
  - Instruction files are made read-only with `chmod 444` instead of being root-owned, which is weaker.
- **Moving to a server later:** stop the gateway, `host.sh backup`, copy the archive to the server, unpack it to the server's `JUNIPER_DIR`, change `HOST_TYPE` and render again.

## How Claude Code picks

If the user hasn't decided, Claude Code asks two questions: is there a device that is on all the time (NAS, Raspberry Pi, mini PC)? Is it a UGREEN NAS? Then:

- UGREEN NAS → `ugos`.
- Any other always-on Linux device → `linux`. If there's none, a Raspberry Pi 5 with 8 GB is the cheapest good option.
- Nothing yet, or just trying → `local`, with the trade-offs above said out loud.
