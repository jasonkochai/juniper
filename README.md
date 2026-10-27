<div align="center">

# ⚡ Juniper

**A private team of AI assistants that lives in one Telegram group.**<br>
Calendar, email, events, news and notes, each handled by its own small agent,<br>
running on your own hardware and never acting without your "yes".

[Quick start](#-quick-start) · [How it works](#-how-it-works) · [What happens when you run it](#-what-happens-when-you-run-it) · [Security](#-security)

</div>

**What I learned:** Docker and container hardening · Linux users and permissions · network security (Tailscale, least privilege) · multi-agent system design · LLM tool permissions and prompt-injection defence · MCP integrations · CalDAV and IMAP · scheduled jobs · secrets management · API cost control

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/juniper-dark.svg">
  <img src="assets/juniper-light.svg" width="100%" alt="Juniper wiring: five Telegram topics reach one OpenClaw gateway in Docker on my home server; email and calendar go through read-only MCP servers, notes through an Obsidian folder.">
</picture>

## 🚀 Quick start

Open [Claude Code](https://claude.com/claude-code) in any folder and paste this:

```text
Clone https://github.com/jasonkochai/juniper and set up Juniper for me.
Read its CLAUDE.md first and follow it: help me choose where it runs,
then guide me through the setup phase by phase. Do every step you can
yourself, tell me exactly what I need to do, and never ask me for a
password, key or token.
```

That's it. Claude Code downloads the repo, asks you a few questions and builds the system with you. Read on if you want to know what it will do first.

## Contents

- [What you get](#-what-you-get)
- [How it works](#-how-it-works)
- [What happens when you run it](#-what-happens-when-you-run-it)
- [What you need](#-what-you-need)
- [Where it runs](#-where-it-runs)
- [What it costs](#-what-it-costs)
- [Security](#-security)
- [Set it up by hand](#-set-it-up-by-hand)
- [Repo layout](#-repo-layout)
- [FAQ](#-faq)
- [Credits and license](#-credits-and-license)

## ✨ What you get

One Telegram bot, one private group, one topic per agent. You talk to the main assistant in a direct message; the others post in their own topics.

| | Agent | What it does for you | What it can't do |
| --- | --- | --- | --- |
| ⚡ | **Juniper** (main) | chats, reads photos, understands voice memos, makes images, writes notes into one Obsidian folder, passes events to Calendar | run commands, browse, read your mail or calendar, delete notes |
| 📅 | **Calendar** | reads all your Apple calendars, adds events to an *Agent* calendar after you confirm | delete anything, change your other calendars |
| 🎟️ | **Events** | finds tech and AI events near you, checks if there's still space | sign you up (it sends the link) |
| 📧 | **Email** | summarises your inbox, flags what matters, drafts replies | send, move or delete a single email |
| 📰 | **News** | writes a short AI news digest every morning | anything except reading the web |
| 💬 | **Comments** *(planned)* | drafts replies to YouTube and Instagram comments | post anything |

**A normal day:**

| Time | Where | What arrives |
| --- | --- | --- |
| 07:25 | 📅 | today's events and tomorrow morning, with clashes flagged |
| 07:30 | 📰 | AI digest: video ideas and things worth learning, with links |
| 08:00 | 📧 | inbox summary since last night, with reply drafts |
| 12:00 | 🎟️ | up to 5 new events; reply "yes 2" to check one |
| 18:00 | 📧 | inbox summary since the morning |
| any time | DM | "Dinner with Alex Friday 7pm" → "Create this event?" → "yes" → it's in your calendar |

## 🧩 How it works

- **One container, many agents.** [OpenClaw](https://docs.openclaw.ai) runs in Docker on a machine you own. Each agent has its own instructions, memory, model and tool list.
- **Telegram is the only way in.** The bot answers only your Telegram account. Every reply starts with the agent's emoji, so you always know who is talking.
- **Small, separate permissions.** The agent that reads your email has no internet. The agent that reads the internet has no email. None of them can run commands.
- **Apple Mail and Calendar** connect through two small, pinned connectors (MCP servers) that can read but not delete or send.
- **Notes** are one folder of your Obsidian vault, synced to the server. The assistant can add and edit notes there, logs every change, and can't delete.
- **Two models.** Claude Haiku for the agents that need judgement, Gemini Flash-Lite (free tier) for the bulk reading. Each falls back to the other if one is down or out of credit.

## 🎬 What happens when you run it

This is the default path when you paste the prompt above. Claude Code does everything on your computer; you're only needed for accounts, passwords and, on a server, `sudo`.

**0. Get ready** · *about 10 minutes*
1. Claude Code clones the repo and reads `CLAUDE.md`, its rulebook for this setup.
2. It asks where Juniper should run and recommends one: your UGREEN NAS, a Raspberry Pi or other always-on Linux box, or this computer for trying it out. On a server it checks 64-bit, 4 GB RAM, Docker and Tailscale.
3. It asks about you (name, time zone, city, interests) and rewrites the agents' profile and event sources to fit.
4. It creates `juniper.local.env` with your settings (IDs only, never secrets) and renders the config files.

**1. Foundation** · *about an hour, mostly accounts*
1. **You** create the accounts: a Telegram bot via BotFather, an Anthropic key with a $10 cap, a Gemini key (free tier).
2. Juniper's data folder, the secrets file (with a random dashboard token) and the hardened Docker setup are created on the host.
3. **You** type your keys into the secrets file yourself. Claude never sees them.
4. **You** create the Telegram group with its topics; a helper reads the group and topic IDs for Claude.
5. The main assistant starts, locked to your Telegram account, with its rules installed read-only.
6. Claude reads a status report and walks you through a short test: "What are your rules?", "Run `ls /`" (it must refuse).

**2. Calendar and Events** · *about 30 minutes*
1. **You** create two Apple app-specific passwords and an *Agent* calendar.
2. Calendar and Events are created, the calendar connector is added without its delete tool, and the morning overview and daily event scan are scheduled.
3. You test: add an event, try to delete it (refused), ask the main assistant to book dinner.

**3. Email** · *about 20 minutes*
1. **You** connect iCloud Mail once through a small setup wizard on the host.
2. Email is created with read-only mail access and no internet; the two daily summaries are scheduled.
3. You send yourself a fake "ignore your instructions" email and check it gets flagged, not followed.

**4. News, voice, images, notes** · *about 30 minutes*
1. **You** get a free Brave Search key.
2. News is created and scheduled; voice memos and image generation are switched on for the main assistant.
3. Your Obsidian `Assistant/` folder is connected: synced with Syncthing on a server, mounted directly on a local install.

**After each phase** Claude runs (or asks you to run) a status check, reads the report and the security audit, and only moves on when everything passes. **Phase 5** (comment replies) is optional and not part of the default run.

On a **server**, you paste one `sudo` command per step into your own terminal; Claude tells you what it should print. On a **local** install, Claude runs every step itself.

## 🧰 What you need

- [Claude Code](https://claude.com/claude-code)
- A Telegram account
- An [Anthropic API](https://platform.claude.com) account (prepaid credit) and a [Google AI Studio](https://aistudio.google.com/apikey) key
- An Apple ID with two-factor authentication, for Mail and Calendar
- A [Brave Search API](https://brave.com/search/api/) key (Phase 4, free credit)
- [Tailscale](https://tailscale.com) if Juniper runs on a server
- Obsidian, if you want the notes feature

## 💻 Where it runs

Anything 64-bit with Docker and 4 GB of RAM.

| | Host | Best for | Notes |
| --- | --- | --- | --- |
| 🗄️ | **UGREEN NAS** | what I run it on | Tailscale forwards automatically |
| 🍓 | **Raspberry Pi 5, mini PC, any Linux server** | a new install: always on, cheap | 64-bit OS; an SSD beats an SD card |
| 💻 | **Your own computer** (Docker Desktop) | trying it out | agents pause when the computer sleeps |

Full comparison and requirements: [docs/hosts.md](docs/hosts.md).

## 💶 What it costs

| | Typical | Hard cap |
| --- | --- | --- |
| Anthropic (Haiku) | a few dollars a month | $10 a month, set in the console |
| Google (Gemini Flash-Lite) | free tier | $8 if you enable billing for images |
| Brave Search | free credit | the free credit |
| Images | about $0.07 each, only when you ask | — |
| Voice memos | about $0.001 a minute | — |

The hardware is whatever you already have, or a Raspberry Pi.

## 🔒 Security

Juniper reads your mail, calendar and notes, so it's built to fail safe:

- **Nothing happens without your "yes".** Sending, booking, buying, deleting: always asked first, and most of those tools don't even exist.
- **Locked container.** Runs as a normal user, all extra privileges dropped, memory limited, no access to Docker itself, only one data folder visible.
- **Not on the internet.** The dashboard listens on the machine itself and is reachable only through your private Tailscale network. Telegram needs no open port.
- **No commands, ever.** Shell access and OpenClaw's "Code Mode" are off for every agent.
- **Split permissions.** Agents that read untrusted text (emails, web pages, event feeds) can't send anything anywhere.
- **Secrets stay put.** Keys live in one file on the host. Claude Code never reads it.
- **Rules aren't changed through chat.** The main assistant's instructions are read-only to the container, and every agent refuses rule changes sent as messages; you change them in this repo.
- **Panic button.** Stop everything from your phone in under a minute: [docs/security.md](docs/security.md#panic-button).

## 🔧 Set it up by hand

Prefer to do it yourself? [docs/setup.md](docs/setup.md) is the same runbook Claude Code follows, step by step, with checks after each one. Stuck? [docs/troubleshooting.md](docs/troubleshooting.md) lists every error seen on the real install.

## 📁 Repo layout

```
CLAUDE.md                     rulebook for Claude Code
juniper.env.example           your settings (copied to juniper.local.env)
host/                         everything that ends up on the host
  docker-compose.yaml         hardened gateway, offline CLI, Syncthing
  env.example                 layout of the secrets file
  config/openclaw.phaseN.json the full config after each phase
  workspaces/<agent>/         each agent's instructions
  cron/jobs.sh                the scheduled jobs
scripts/
  render.py                   fills your settings into the templates
  host.sh                     one command per setup step
  merge_config.py             applies a config without losing OpenClaw's own settings
docs/
  hosts.md · setup.md · security.md · troubleshooting.md
```

## ❓ FAQ

**Do I need a NAS?**
No. A Raspberry Pi or any always-on Linux machine works, and you can try it on your own computer first.

**Can Claude Code see my passwords?**
No. You type every secret into the secrets file yourself, and its rules forbid reading it.

**Can an agent send an email or delete something by mistake?**
The tools for that aren't installed: no send, no delete, no shell. Calendar changes need your "yes".

**I don't use Apple Mail or Calendar.**
The mail and calendar connectors would need swapping for ones that speak your provider. The rest works as is.

**I'm not in Berlin.**
Claude Code replaces the event feeds and time zone with yours during setup.

**Can I leave out an agent?**
Yes. Tell Claude Code which ones you want; it skips the rest.

## 🙌 Credits and license

I designed the system, made the decisions and did the install on my own server, debugging it step by step. The setup guide, the helper scripts, these docs and the diagram were written with Claude Code.

Built on [OpenClaw](https://docs.openclaw.ai), [caldav-mcp](https://github.com/dominik1001/caldav-mcp), [imap-mcp-server](https://github.com/nikolausm/imap-mcp-server) and [Syncthing](https://syncthing.net).

[MIT](LICENSE)
