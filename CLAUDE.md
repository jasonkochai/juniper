# Juniper: instructions for Claude Code

This repo sets up Juniper, a multi-agent OpenClaw assistant, in Docker on a host the user picks: a UGREEN home server, any always-on Linux box (Raspberry Pi, mini PC, server), or their own computer. Your job is to take the user from wherever they are to a working, locked-down system by following [docs/setup.md](docs/setup.md) phase by phase. The user wants you to do the work, not hand them a guide: run every step you can yourself, and give them only what needs a human.

## First: the host

Read [docs/hosts.md](docs/hosts.md). If `juniper.local.env` has no `HOST_TYPE` yet, ask the user what they have and recommend one:

- UGREEN home server → `ugos`.
- Any other device that is on all the time → `linux`. Check it's 64-bit with 4 GB+ RAM (`uname -m`, `free -h`), has Docker with compose (`docker compose version`) and Tailscale.
- Nothing always-on, or just trying it → `local`. Say the trade-offs out loud: agents stop when the computer sleeps, scheduled jobs are missed, and it runs on their daily machine.

Then set `HOST_TYPE`, `JUNIPER_DIR`, `HOST_SSH` (empty for local) and `CONTROL_UI_ORIGIN`.

## Then: the models

Ask which setup they want (README "Ways to run it"): fully local on one device, fully local on two devices (always-on box plus a model machine on the LAN), hybrid (cloud models, optionally some agents local), or fully cloud (VPS plus cloud models). The default is cloud models (Claude Haiku plus Gemini Flash-Lite, cheap, best quality). For local or mixed, follow [docs/local-llm.md](docs/local-llm.md): apply its changes to the phase configs in their clone before Phase 1, run `host.sh agent` with `JUNIPER_AGENT_MODEL`, and skip the Anthropic and Google accounts in step 1.7. Voice and image generation are off in that mode.

## How work is split

| Host type | Host commands | You can run |
| --- | --- | --- |
| `local` | `bash build/host/host.sh <command>`, no `sudo` | everything, including the host steps, yourself |
| `linux`, `ugos` | `sudo bash ~/juniper/host.sh <command>` in the user's own SSH session; `sudo` asks for a password you must never see | render, `rsync -a --delete build/host/ "$HOST_SSH":juniper/`, non-sudo checks over SSH, reading `~/juniper-report.txt` |

Always the user's: accounts, spend caps, BotFather, Apple app passwords, Tailscale ACLs, Telegram tests, and typing secrets into `.env`.

On a server, give the user one short block of host commands at a time, say what each should print, and wait for the result (or for `host.sh check`) before moving on.

## Hard rules

- **Secrets never pass through you.** Don't read `.env` (not even on a local install), don't ask the user to paste a key, token or password, and never run or request `openclaw mcp show` output (it prints resolved secrets). Let the user edit `.env` in their own editor. `juniper.local.env` holds IDs only, never secrets.
- **Never weaken the security model.** No `docker.sock`, no mounts outside `$JUNIPER_DIR` (except the vault's `Assistant/` folder on a local install), no port on `0.0.0.0` or a `100.x` IP, no `tools.codeMode` other than `false`, no `exec` or `group:runtime` for any agent, no `openclaw security audit --fix`, no ClawHub skills, no unpinned images or MCP servers. Don't suggest passwordless sudo or adding the user to the `docker` group.
- **Never run `openclaw mcp tools <server>`.** It edits the tool filter; `--clear` brings back delete tools.
- **Change agent behaviour in this repo,** in `host/workspaces/<agent>/AGENTS.md`, then render, copy and `host.sh workspace <agent>`. Never through chat with the agents.
- **Templates stay strict JSON** (no comments, no trailing commas). `{{NAME}}` placeholders are filled by `render.py` from `juniper.local.env`; `${NAME}` placeholders are resolved by OpenClaw or compose from `.env` at runtime and must stay as they are.
- Every `curl` gets `-m 5` or more. Compose always gets `-p openclaw-agents`. After compose or `.env` changes, `up -d`, never `restart`.
- Never commit `juniper.local.env` or `build/`.

## Personalise for a new user

The templates carry the author's defaults. For anyone else, before Phase 1:

- `host/workspaces/shared/USER.md`: rewrite it with the user (who they are, languages, interests, busy times).
- `TIMEZONE` in `juniper.local.env`.
- Events: the feeds in `host/workspaces/events/AGENTS.md` and `host/cron/jobs.sh` are Berlin Luma calendars. Find the user's city feeds (Luma city/calendar ICS, Meetup group iCal) and replace them in both files, and the city name.
- News feeds: in `host/workspaces/news/AGENTS.md` and `host/cron/jobs.sh`.
- More tools (another chat app, search provider, Home Assistant, any MCP server): follow [docs/integrations.md](docs/integrations.md), one owning agent, everyone else denies it.
- An agent they don't want: skip its `host.sh agent` and `cron` steps, and remove it from the later phase configs (its `agents.entries` block, its topic in `channels.telegram.groups`, and its name in `tools.agentToAgent.allow`). Keep other agents' `deny` entries for its MCP server; they do no harm.
- Mail and calendar are iCloud. Another provider needs a different MCP server with the same limits (pinned, `toolFilter`, no delete or send).

## Starting a session

1. If `juniper.local.env` is missing, copy `juniper.env.example`, settle the host (above), fill what the user knows.
2. Server: check `ssh -o BatchMode=yes "$HOST_SSH" true`. You can't type an SSH password, so if it asks for one, have the user set up key login (docs/setup.md, Phase 0). If it times out, Tailscale on this computer is probably off. Your shell doesn't keep variables between commands: source `juniper.local.env` in the same command that uses `$HOST_SSH`.
3. Find out where the system stands: run (local) or ask the user to run (server) `host.sh check`, then read `~/juniper-report.txt` on the host. Agents, cron jobs and MCP servers in it show which phase is done.
4. Continue at the first unfinished step in [docs/setup.md](docs/setup.md). Each phase ends with `host.sh check`, a Telegram tool check per new agent, and the audit target (0 critical, only the three known warnings).

## Files

| Path | Lands on the host as |
| --- | --- |
| `host/docker-compose.yaml` | `$JUNIPER_DIR/docker-compose.yaml` (via `host.sh compose`) |
| `host/env.example` | `$JUNIPER_DIR/.env`, created once by `host.sh env`, then edited by the user |
| `host/config/openclaw.phaseN.json` | merged into `config/openclaw.json` by `host.sh config N` (OpenClaw's own `plugins`, `skills`, `meta`, `wizard`, `talk` are kept) |
| `host/workspaces/<agent>/` | `workspace/` (main, read-only) or `workspace-<agent>/` (via `host.sh workspace` / `host.sh agent`) |
| `host/cron/jobs.sh` | the scheduled jobs per agent (via `host.sh cron <agent>`) |
| `scripts/host.sh` | the host helper; with no argument it lists its commands. Reads `host.env` (written by `render.py`) for `HOST_TYPE` and `JUNIPER_DIR` |
| `scripts/merge_config.py` | used by `host.sh config` |
| `scripts/render.py` | `host/` + `juniper.local.env` → `build/host/` |

`docs/security.md` has the panic button and the full checklist; `docs/troubleshooting.md` has every error seen on the real install.

## State of the author's live system

UGREEN home server (`ugos`). Phases 1 to 3 (hub, Calendar, Events, Email) run there. Phase 4 is optional and experimental: the author hasn't set up News or the Obsidian notes on their own system. The author has also run Juniper fully locally with a local LLM ([docs/local-llm.md](docs/local-llm.md)). The `local` path was run end to end in Docker Desktop with dummy keys (every host.sh step, all four phase configs through `config validate`, the Obsidian mount, Syncthing, the read-only rule files); model calls weren't tested. The `linux` path hasn't run on real hardware yet.
