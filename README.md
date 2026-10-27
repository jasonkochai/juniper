# Juniper

Multi-agent personal assistant on OpenClaw, self-hosted in Docker on my home server. One Telegram forum topic per agent: news, events, email, calendar, notes. Each agent gets only the tools and the model its job needs.

**What I learned:** Docker and container hardening · Linux users and permissions · network security (Tailscale, least privilege) · multi-agent system design · LLM tool permissions and prompt-injection defence · MCP integrations · CalDAV and IMAP · scheduled jobs · secrets management · API cost control

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/juniper-dark.svg">
  <img src="assets/juniper-light.svg" width="100%" alt="Juniper wiring: five Telegram topics reach one OpenClaw gateway in Docker on my home server; email and calendar go through read-only MCP servers, notes through an Obsidian folder.">
</picture>

## The agents

| Agent | Topic | Can | Can't | Model |
| --- | --- | --- | --- | --- |
| ⚡ Juniper (`main`) | DM + General | chat, photos, voice memos, images, notes in one Obsidian folder, hand events to Calendar | shell, web, mail, calendar, delete notes, install skills | Haiku 5.5 |
| 📅 Calendar | 📅 | read all Apple calendars, write to the *Agent* calendar after a "yes", 07:25 overview | delete events, touch other calendars | Haiku 5.5 |
| 🎟️ Events | 🎟️ | daily Luma/RSS scan, availability check, pass registered events to Calendar | register for me, mail, shell | Gemini 3.5 Flash-Lite |
| 📧 Email | 📧 | read iCloud Mail, 08:00 and 18:00 summaries, reply drafts | send, move, delete or flag mail, web | Haiku 5.5 |
| 📰 News | 📰 | web search and feeds, 07:30 AI digest | everything else | Gemini 3.5 Flash-Lite |
| 💬 Comments (planned) | 💬 | read YouTube and Instagram comments, draft replies | post anything | Gemini 3.5 Flash-Lite |

Every agent falls back to the other model on errors. Nothing is sent, posted, registered or deleted without my explicit "yes".

## Security model

- **Container:** non-root (uid 1000), all capabilities dropped, `no-new-privileges`, memory and process limits, no `docker.sock`, only `/volume1/docker/openclaw` subfolders mounted.
- **Network:** gateway published on `127.0.0.1` only, reached through Tailscale, token auth with rate limiting. Not on the LAN, not on the internet.
- **Tools:** shell and Code Mode off for every agent. Each specialist has an explicit allowlist and denies every other agent's MCP server. Agents that read untrusted text (mail, feeds, web) can't send anything anywhere.
- **Integrations:** two version-pinned MCP servers, both read-limited: CalDAV without a delete tool, IMAP in read-only mode with no SMTP. No ClawHub skills.
- **Secrets:** only in `.env` on the server. Instruction files are root-owned so a prompt injection can't rewrite an agent's rules.
- **Costs:** hard caps on every provider; the free Gemini tier covers most runs.

Details, the panic button and the full checklist: [docs/security.md](docs/security.md).

## Set it up with Claude Code

The repo is written so [Claude Code](https://claude.com/claude-code) can do the setup: it renders the configs, copies them to the server, reads the status reports and tells you the few things only a human can do (accounts, app passwords, `sudo`). Secrets never pass through it.

```sh
git clone https://github.com/jasonkochai/juniper.git
cd juniper
claude "Set up Juniper on my NAS"
```

[CLAUDE.md](CLAUDE.md) holds the rules it follows; [docs/setup.md](docs/setup.md) is the phase-by-phase runbook, readable without Claude too. Built for a UGREEN NAS (UGOS) with OpenClaw 2026.10.5; other Docker hosts need small path changes.

## Layout

```
nas/
  docker-compose.yaml         hardened gateway, offline CLI, Syncthing
  env.example                 the secrets file layout (values live only on the server)
  config/openclaw.phaseN.json the full config after each phase, strict JSON
  workspaces/<agent>/         AGENTS.md, IDENTITY.md; shared SOUL.md and USER.md
  cron/jobs.sh                scheduled jobs per agent
scripts/
  render.py                   fills {{PLACEHOLDERS}} from juniper.local.env into build/
  nas.sh                      server helper: layout, env, compose, config, agent, cron, ids, check
  merge_config.py             merges a phase config without losing OpenClaw's own blocks
docs/
  setup.md · security.md · troubleshooting.md
```

## Credits

I designed the system, made the decisions and did the install on my server, debugging it step by step. The setup guide, the helper scripts, these docs and the diagram were written with Claude Code.

## License

[MIT](LICENSE)
