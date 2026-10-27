# Juniper: instructions for Claude Code

This repo sets up Juniper, a multi-agent OpenClaw assistant, on a UGREEN NAS (UGOS, Docker, userspace Tailscale). Your job is to take the user from wherever they are to a working, locked-down system by following [docs/setup.md](docs/setup.md) phase by phase. The user wants you to do the work, not hand them a guide: run every step you can yourself, and give them only what needs a human.

## How work is split

| Who | What |
| --- | --- |
| You (Mac) | Edit templates, fill `juniper.local.env`, `python3 scripts/render.py`, `rsync -a --delete build/nas/ "$NAS_SSH":juniper/`, non-sudo checks over SSH, read `~/juniper-report.txt`, Syncthing on the Mac, explain the next step |
| User on the NAS | Commands that need `sudo`, pasted into their own SSH session, almost always `sudo bash ~/juniper/nas.sh <command>`. `sudo` asks for a password you must never see |
| User elsewhere | Accounts, spend caps, BotFather, Apple app passwords, Tailscale ACLs, Telegram tests, typing secrets into `.env` with `sudo nano` |

Give the user one short block of NAS commands at a time, say what each should print, and wait for the result (or for `nas.sh check`) before moving on.

## Hard rules

- **Secrets never pass through you.** Don't read `.env`, don't ask the user to paste a key, token or password, and never run or request `openclaw mcp show` output (it prints resolved secrets). `juniper.local.env` holds IDs only, never secrets.
- **Never weaken the security model.** No `docker.sock`, no mounts outside `/volume1/docker/openclaw`, no port on `0.0.0.0` or a `100.x` IP, no `tools.codeMode` other than `false`, no `exec` or `group:runtime` for any agent, no `openclaw security audit --fix`, no ClawHub skills, no unpinned images or MCP servers. Don't suggest passwordless sudo or adding the user to the `docker` group.
- **Never run `openclaw mcp tools <server>`.** It edits the tool filter; `--clear` brings back delete tools.
- **Change agent behaviour in this repo,** in `nas/workspaces/<agent>/AGENTS.md`, then render, rsync and `nas.sh workspace <agent>`. Never through chat with the agents.
- **Templates stay strict JSON** (no comments, no trailing commas). `{{NAME}}` placeholders are filled by `render.py` from `juniper.local.env`; `${NAME}` placeholders are resolved by OpenClaw from `.env` at runtime and must stay as they are.
- Every `curl` gets `-m 5` or more. Compose always gets `-p openclaw-agents`. After compose or `.env` changes, `up -d`, never `restart`.
- Never commit `juniper.local.env` or `build/`.

## Starting a session

1. If `juniper.local.env` is missing, copy `juniper.env.example` and fill what the user knows. Ask for the SSH host alias first.
2. Check reachability: `ssh "$NAS_SSH" true`. If it fails, Tailscale on the Mac is probably off; ask the user to turn it on.
3. Find out where the system stands: ask the user to run `sudo bash ~/juniper/nas.sh check` (after a first rsync), then read it with `ssh "$NAS_SSH" cat juniper-report.txt`. Agents, cron jobs and MCP servers in the report tell you which phase is done.
4. Continue at the first unfinished step in [docs/setup.md](docs/setup.md). Each phase ends with `nas.sh check`, a Telegram tool check per new agent, and the audit target (0 critical, only the three known warnings).

## Files

| Path | Lands on the NAS as |
| --- | --- |
| `nas/docker-compose.yaml` | `/volume1/docker/openclaw/docker-compose.yaml` (via `nas.sh compose`) |
| `nas/env.example` | `/volume1/docker/openclaw/.env`, created once by `nas.sh env`, then edited by the user |
| `nas/config/openclaw.phaseN.json` | merged into `config/openclaw.json` by `nas.sh config N` (OpenClaw's own `plugins`, `skills`, `meta`, `wizard`, `talk` are kept) |
| `nas/workspaces/<agent>/` | `workspace/` (main, root-owned) or `workspace-<agent>/` (via `nas.sh workspace` / `nas.sh agent`) |
| `nas/cron/jobs.sh` | the scheduled jobs per agent (via `nas.sh cron <agent>`) |
| `scripts/nas.sh` | the NAS helper; `sudo bash ~/juniper/nas.sh` with no argument lists its commands |
| `scripts/merge_config.py` | used by `nas.sh config` |
| `scripts/render.py` | Mac side: `nas/` + `juniper.local.env` → `build/nas/` |

`docs/security.md` has the panic button and the full checklist; `docs/troubleshooting.md` has every error seen on the real install.

## State of the live system

Phases 1 to 3 (hub, Calendar, Events, Email) are tested on the real NAS. Phase 4 (News, voice, images, Obsidian via Syncthing) is being set up. Phase 5 (Comments via Composio) is planned, not live.
