# Troubleshooting

Errors and fixes from the real install (UGREEN home server, OpenClaw 2026.10.5) and the OpenClaw docs. Commands are written for a server; drop `sudo` on a local install. Step numbers match [setup.md](setup.md).

## 1.1 Inspect and back up the current container

* `permission denied … docker.sock`: put `sudo` in front of that docker command. Don't add yourself to the `docker` group, because that is root-equivalent.
* `python3: not found`: drop the pipe; the raw JSON is fine.

## 1.2 Create the folder layout and permissions

The docs' fix for `EACCES` errors after first start is `sudo chown -R 1000:1000 config workspace` ([compose operations](https://docs.openclaw.ai/install/docker/compose-operations)). That also gives the hub's instruction files back to uid 1000, so run `host.sh workspace main` afterwards.

## 1.3 Write the `.env` secrets file and the `openclaw` aliases

Never paste keys into Telegram or into an agent chat. If a key leaks, go to [Panic button](security.md#panic-button).

## 1.4 docker-compose.yaml

* **`sudo docker port openclaw-gateway` prints nothing.** The port binding uses an address the host doesn't have, e.g. a `100.x` IP. Change it to `127.0.0.1:18789:18789`.
* **Telegram answers "This agent's workspace is missing on the gateway host…"**, or a command fails with "No such file or directory". Usually a `config/workspace-<name>` mount point was deleted. Check it with `sudo docker exec openclaw-gateway ls /home/node/.openclaw/workspace-<name>`, then recreate the mounts: `sudo docker compose -p openclaw-agents up -d --force-recreate openclaw-gateway`.
* **"container name already in use".** You ran compose without `-p openclaw-agents`, or from another folder. Run it again from `$JUNIPER_DIR` with the project name.
* **The Mac can't reach `100.x:18789`, but `127.0.0.1` works on the host.** UGOS: check that the Tailscale app is running. Linux: run `host.sh expose` and check `tailscale serve status`. Both: your Tailscale access controls must allow `tcp:18789` (step 1.5). Don't test the `100.x` address from the host itself; on UGOS that always fails.
* **Exit code 78, or a restart loop.** In `sudo docker ps` a restart loop shows as an uptime that keeps resetting ("Up 36 seconds" → "Up 2 seconds"), not as "stuck starting". Read the reason:

  ```
  sudo docker logs --tail 80 openclaw-gateway | grep -iE "blocked|missing|error"
  ```

  "Gateway start blocked: existing config is missing gateway.mode" means `gateway.mode: "local"` is missing (step 1.6).
* **"Unknown key" or the gateway refuses to start.** Stop the gateway, run `openclaw-offline doctor --fix`, then `sudo docker compose -p openclaw-agents up -d openclaw-gateway`.
* **(UGOS) The Docker UI rewrote your compose file.** Some users report this. This repo holds the real copy: re-run `host.sh compose`.

## 1.5 Reach the Control UI only through Tailscale

The docs call plain HTTP over a tailnet IP "a downgraded transport". The traffic is still encrypted by WireGuard between your devices. On UGOS it works without `tailscale serve`; on Linux, `host.sh expose` forwards raw TCP, so the URL stays `http://<tailscale ip>:18789`.

## 1.6 openclaw.json

* **An agent lists `exec`/`wait` although exec is denied.** That's OpenClaw Code Mode, which `tools.deny` doesn't block. Set `"codeMode": false` in the global `tools` block, run `sudo docker compose -p openclaw-agents up -d openclaw-gateway`, then `/new` in the topic and run the tool check again.
* **Config rejected with "mixed policy".** Don't combine `exec.mode` with the legacy `exec.security` or `exec.ask`. `mode` is the current key ([exec approvals](https://docs.openclaw.ai/tools/exec-approvals)).
* **The model picker or `/model` refuses a model** with "not allowed by agents.defaults.modelPolicy.allow". Add its exact ref to `modelPolicy.allow`. An allowlist that holds only Sonnet would block switching to Haiku and Flash-Lite, so list every model you use ([models docs](https://docs.openclaw.ai/concepts/models)).
* **An old config has `agents.list`.** `openclaw-offline doctor --fix` migrates it to `agents.entries`.
* **An old guide says to create `TOOLS.md` or `HEARTBEAT.md`.** Both are retired. Notes go in the `## Tools` section of `AGENTS.md`.

## 1.7 Model keys and hard spend caps

A 402 from Google means the prepaid credits ran out. A 429 from Anthropic with "spend limit" means the cap was hit, which is the cap doing its job. Check `/usage cost` to see which agent burned the money.

## 1.8 Telegram DM allowlist

* **Config validation fails.** `dmPolicy: "allowlist"` with an empty `allowFrom` is rejected on purpose.
* **409 conflict in the logs.** Another process is polling the same bot token. That is usually the old container still running.

## 1.9 Create the private forum group with one topic per agent

* **"thread not found".** The General topic (id 1) is special: replies there omit the thread id, and OpenClaw handles that. Don't use topic `0`.
* **The bot ignores plain messages.** Privacy mode is still on. Make it an admin, or disable privacy and re-add it.
* **Negative IDs.** They belong under `groups`, never in `groupAllowFrom`.

## 2.1 Apple Account: two app-specific passwords and an "Agent" calendar

Changing your main Apple Account password **revokes all app-specific passwords automatically**. After a password change, create new ones and update `.env`.

## 2.2 Apple Calendar via CalDAV

* **401 or 403.** Usually `ICLOUD_USER` isn't your **primary Apple ID**, for example an iCloud+ custom-domain address or an alias. Use the email shown on the iPhone under *Settings → [your name]*, and create the app-specific password under that same Apple ID. Otherwise it's a typo in the app password, or the password was revoked.
* **Hangs on first start.** `npx` is downloading the package. Raise `requestTimeoutMs` for the first run.

## 2.4 Hub → Calendar handoff

If `sessions_send` is "not available", the caller's tool policy blocks it. The `messaging` profile includes `sessions_send`, so check that no deny list (for example `group:sessions`) removed it.

## 2.5 Morning calendar overview (cron) and reminders via Apple Calendar

Jobs that never fire: the CLI needs a running gateway, and scheduled runs need `cron.enabled`. Check that it is on in the cron docs. Natural-language schedules like "every morning" aren't supported, so use cron syntax.

## 2.6 Events agent

* **Feeds get cut off.** From step 4.1, `tools.web.fetch.maxChars` is 10,000 for all agents, which is roughly 10–15 events per ICS feed. The Discover feed holds about 50. Prefer the specific Berlin AI calendars over Discover, or raise `maxChars` and accept that big runs may fall back to Haiku.
* **Residual risk.** The Events agent reads untrusted feeds and can message Calendar. The handoff now only happens after you reply "registered N", and Calendar only accepts handoffs that contain "CONFIRMED BY USER" and an event URL. A manipulated Events agent could still fake that line; the worst case is an extra entry in the Agent calendar, never in your other calendars.

## 3.1 iCloud Mail via IMAP

* **"No accounts configured".** The `imap-mcp` mount is still commented out, or the container wasn't recreated. Check that `docker-compose.yaml` has the `./imap-mcp` line (`host.sh compose` installs it), then `sudo docker exec openclaw-gateway ls -la /home/node/.imap-mcp` must show `accounts.json` and `.key`.
* **"has IMAP credentials marked as environment-managed, but this variable was not set".** `ICLOUD_MAIL_APP_PASSWORD` is missing from `.env`, or the gateway wasn't restarted with `up -d`.
* **The test connection fails with an authentication error.** A wrong address (use the `@icloud.com` address from the iPhone's Mail settings) or a wrong or revoked mail app password.

## 3.3 Email summaries

The fixed windows and the cap of 30 mails keep input small. A full inbox dump can go over Haiku's 100k-token threshold, and above it everything costs 5×.

## 4.1 News agent

12 fetches × 10,000 characters is about 30k tokens. Even over 4 model calls, that stays under the free tier's 250K tokens per minute, and under Haiku's 100k surcharge if the run falls back to Haiku. If you add sources, reduce `maxChars`. If it gets rate-limited anyway, the Haiku fallback takes over for that run.

## 4.5 Syncthing

Files named `*.sync-conflict-*.md` appear when the same note changed in two places at once. Merge them by hand. The agent is told to leave them alone.

## The helper scripts

* **`render.py` says "skipped … no value for X".** That file needs `X` in `juniper.local.env`. Files for later phases are skipped until their values exist; that's expected.
* **`host.sh config N` says "no …/openclaw.phaseN.json".** It wasn't rendered (missing values) or wasn't copied. Re-render and rsync.
* **`host.sh config N` says "gateway not live".** It prints the log lines and the restore command for the backup it just made. Run that command, then `sudo docker compose -p openclaw-agents up -d openclaw-gateway`.
* **`host.sh agent <id>` fails with a shared-state error.** Stop the gateway, run `openclaw-offline agents add <id> --workspace '~/.openclaw/workspace-<id>' --model <model> --non-interactive`, start it again, then `host.sh workspace <id>`.
* **`host.sh ids` says "Conflict".** Something else polls the bot (the gateway or an old container). Stop it, or read the IDs from `openclaw logs --follow` instead.
* **`host.sh` says "run with sudo" or "a local install runs without sudo".** `HOST_TYPE` in `juniper.local.env` decides: servers need `sudo`, `local` must run as you. Fix the value, re-render.

## Host types

* **`exec format error` on a Raspberry Pi.** The OS is 32-bit. Install Raspberry Pi OS (64-bit).
* **`tailscale serve` fails or isn't found.** Install Tailscale on the host and log in with `sudo tailscale up` first. `sudo tailscale serve reset` clears all forwards.
* **Local install, Linux or WSL: `EACCES` in the logs.** Your user isn't uid 1000, so the container can't write the folders. Use `HOST_TYPE=linux` with `sudo`, which sets the owners.
* **Local install: scheduled jobs didn't run.** The computer was asleep. That's the main reason to move to an always-on host ([hosts.md](hosts.md#local-this-computer)).
