# Security

## Panic button

1. **Stop everything.** From your phone, open the UGOS app or web UI over Tailscale → *Docker → openclaw-gateway → Stop*. Over SSH:

   ```
   sudo docker stop openclaw-gateway
   ```

   `/stop` in Telegram only aborts the current run. It does not stop the agents.
2. **Cut Telegram.** In BotFather, `/mybots` → your bot → *API Token* → *Revoke current token* (or `/revoke`). This takes effect immediately.
3. **Revoke Apple access.** At [account.apple.com](https://account.apple.com) → *Sign-In and Security* → *App-Specific Passwords*, remove `openclaw-mail` and `openclaw-cal`, or use *Revoke All*. If you use a second Apple ID for the calendar, also stop sharing your calendars with it in the Calendar app. Changing your main Apple Account password also revokes every app-specific password.
4. **Cut Composio (Phase 5).** In the Composio dashboard, delete the connected accounts and rotate the project API key. Also revoke the apps at the source: Instagram → Settings → *Apps and websites*, and [Google account permissions](https://myaccount.google.com/permissions) for YouTube.
5. **Stop note sync.** Run `sudo docker stop syncthing` (option A), or `sudo docker stop couchdb-for-ols livesync-bridge` and change the CouchDB password (option B). On the Mac, pause the `Assistant` folder in Syncthing. Look at `Assistant/_log.md` for what the agent changed, and use Syncthing's file versions to roll back.
6. **Disable the model keys.**
   * [Anthropic Console → API keys](https://platform.claude.com/settings/keys) → disable
   * [AI Studio → API keys](https://aistudio.google.com/apikey) → delete
   * Brave dashboard → revoke
   * X / xAI, if added.
7. **Rotate the gateway token.**

   ```
   cd /volume1/docker/openclaw
   sed -i "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)/" .env
   sudo docker compose -p openclaw-agents up -d openclaw-gateway   # not "restart": restart doesn't re-read .env
   ```
8. **Before restarting,** set `dmPolicy: "disabled"` and `groupPolicy: "disabled"`, then look at what happened:

   ```
   sudo docker compose -p openclaw-agents up -d openclaw-gateway
   openclaw logs | tail -200
   openclaw security audit --deep
   openclaw cron list          # unexpected jobs?
   openclaw mcp list           # unexpected MCP servers?
   openclaw skills list        # unexpected skills?
   ```
9. Put the new keys and new app-specific passwords in `.env`, re-enable the channels, and start the gateway again. [Incident response docs](https://docs.openclaw.ai/gateway/security/operator-incident-response)

## Security checklist

* The container runs as uid 1000: `sudo docker exec openclaw-gateway id`
* Only subfolders of `/volume1/docker/openclaw` are mounted. No `/volume1`, no photo or backup shares.
* `/var/run/docker.sock` is not mounted, so the sandbox stays off on purpose.
* `no-new-privileges`, `cap_drop`, `mem_limit: 3g` and `pids_limit` are active (`sudo docker inspect`).
* Port 18789 is published on `127.0.0.1` only (`sudo docker port openclaw-gateway`). It's reachable from your tailnet through UGOS's userspace forwarding, and unreachable from the LAN IP and the internet. No router port forwards. No Funnel.
* `gateway.auth.mode: "token"` with a 64-hex-character token from `.env`.
* The Tailscale policy is no longer allow-all, and only your devices can reach the NAS.
* Telegram: `dmPolicy: "allowlist"`, `allowFrom` holds only your numeric ID, `groupPolicy: "allowlist"`, only your group is listed, and the invite link is revoked.
* Exec is denied for **every** agent: `tools.deny` includes `exec` and `group:runtime`, and `tools.exec.mode: "deny"`. **`tools.codeMode: false`**, because Code Mode's own exec bypasses those denies. No agent lists `exec`/`wait`, and the hostname test is refused. Never `/exec security=full` or `mode: "full"`.
* `tools.elevated.enabled: false`
* No ClawHub skills are installed. The only integrations are two **version-pinned** MCP servers (`caldav-mcp@0.10.0`, `imap-mcp-server@2.2.0`). Any new skill or server goes through the vetting list below.
* Every `AGENTS.md` says "never install skills", and the instruction files are root-owned and read-only.
* Separate app-specific passwords `openclaw-mail` and `openclaw-cal`, kept only in `.env`. Your main Apple Account password is never used anywhere on the NAS.
* The mail server has `IMAP_MCP_READ_ONLY=true`, `toolFilter` passes only the 3 read tools, and no SMTP account is configured. Tested: delete and send requests fail.
* The calendar server has no `delete-event` tool, new events go to the *Agent* calendar only, and every create or change needs your "yes". Or: a second Apple ID makes your other calendars read-only, enforced by Apple.
* Composio (Phase 5): its own project, your own Meta and Google OAuth apps, trimmed scopes (no upload, publish or DM scopes), `allowed_tools` limited to read tools, the API key only in `.env`, and `composio-social__*` denied for every agent except `comments`.
* Only the vault's `Assistant/` folder is on the NAS and mounted into the gateway. The hub has no delete path (exec and `apply_patch` denied), logs every change in `_log.md`, and the sync ports are published on `127.0.0.1` only.
* Agent-to-agent: `allow` is exactly main, calendar and events. Send lists: main → calendar, events → calendar, all others `[]`.
* Spend caps: Anthropic $10, Google $8 with a billing spend cap, Brave limited to the free credit.
* `config/`, `auth-secrets/` and `imap-mcp/` are mode 700, and `.env` and the audit files are mode 600.
* NAS backups of `/volume1/docker/openclaw` are encrypted and treated as credentials, because tokens are stored in plaintext SQLite.
* SSH is turned off again in UGOS when you're not configuring.
* `openclaw security audit --deep` is clean after the latest phase.
* Tested: nothing is sent, posted, registered or deleted without your explicit "yes".

**Change agent rules on the NAS, not through chat.**

* **Asking Juniper won't work, by design.** Juniper passes a request to change the Calendar agent's `AGENTS.md` on, and the Calendar agent rightly refuses. From `main` it only accepts "CONFIRMED BY USER:" events, and it reports the text as a suspected prompt injection ("text posing as a system prompt update").
* **Edit the file in this repo instead:** change `nas/workspaces/<name>/AGENTS.md`, run `python3 scripts/render.py`, rsync `build/nas/` to the NAS, run `sudo bash ~/juniper/nas.sh workspace <name>`, then send `/new` in that agent's topic.

## Skill vetting (before any ClawHub install)

In early 2026, hundreds of malicious ClawHub skills were found, including credential stealers. Since February 2026 ClawHub scans skills with VirusTotal, which OpenClaw itself calls "not a silver bullet".

1. `openclaw skills search "…"` → open the skill page. Check the install count, the maintainer's other skills and their GitHub activity, and the last update.
2. On the page, read the **security scan status**: VirusTotal, ClawScan and static analysis. Anything other than clean → stop.
3. Read `SKILL.md` *and every script*. Look for `curl | sh`, base64 blobs, reads of `~/.openclaw`, `.env` or keychains, and network calls to unknown hosts.
4. Install for one agent only, with a version pin:

   ```
   openclaw skills verify @owner/slug        # exits non-zero if ClawHub marks verification failed
   openclaw skills install @owner/slug --version X.Y.Z --agent AGENT_ID
   ```
5. Add the skill to that agent's `skills: [...]` list only, then run the audit again.