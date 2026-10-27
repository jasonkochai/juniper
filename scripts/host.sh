#!/usr/bin/env bash
# Juniper host helper. Runs on the host from the rendered bundle:
#   sudo bash ~/juniper/host.sh <command> [args]     (ugos, linux)
#   bash build/host/host.sh <command> [args]         (local, no sudo)
# Every command is safe to re-run. Nothing here prints a secret.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/host.env" ] || { echo "error: no host.env next to host.sh; run scripts/render.py" >&2; exit 1; }
# shellcheck source=/dev/null
. "$HERE/host.env"
OC_DIR="${OC_DIR:-$JUNIPER_DIR}"
AGENTS="calendar events email news"
SUDO="sudo "
[ "$HOST_TYPE" = "local" ] && SUDO=""

die() { echo "error: $*" >&2; exit 1; }
stamp() { date +%Y%m%d-%H%M%S; }
dc() { docker compose -p openclaw-agents "$@"; }
oc() { docker exec openclaw-gateway node dist/index.js "$@"; }
# a local install runs as you; Docker Desktop maps file ownership itself
own() { [ "$HOST_TYPE" = "local" ] || chown "$@"; }
# hide anything token-shaped before it reaches a terminal or the report
redact() {
    sed -E -e 's/([Aa]uthorization"?: *"?(Basic|Bearer|basic|bearer) )[^ "]+/\1[redacted]/g' \
        -e 's/bot[0-9]{6,}:[A-Za-z0-9_-]{30,}/bot[redacted]/g' \
        -e 's/(sk-ant-|AIza)[A-Za-z0-9_-]{10,}/\1[redacted]/g' \
        -e 's/[0-9a-f]{64}/[redacted]/g'
}

wait_live() {
    local i
    for i in $(seq 1 24); do
        if curl -m 5 -s http://127.0.0.1:18789/healthz | grep '"status":"live"' > /dev/null; then
            echo "healthz: live"
            return 0
        fi
        sleep 5
    done
    return 1
}

config_errors() {
    docker logs --tail 60 openclaw-gateway 2>&1 \
        | grep -iE "blocked|invalid|unknown key|error" | redact || echo "no config errors in the log"
}

cmd_backup() {
    # step 1.1: the archive holds tokens in plaintext, treat it like a password file
    [ -d "$OC_DIR" ] || { echo "nothing to back up: $OC_DIR doesn't exist yet"; return; }
    local parent name out
    parent="$(dirname "$OC_DIR")"
    name="$(basename "$OC_DIR")"
    out="$parent/$name-backup-$(stamp).tgz"
    tar czf "$out" -C "$parent" "$name"
    chmod 600 "$out"
    ls -l "$out"
}

cmd_layout() {
    # step 1.2: create every mount folder before the first start
    mkdir -p "$OC_DIR"
    cd "$OC_DIR"
    local dirs="config workspace auth-secrets imap-mcp obsidian-assistant syncthing"
    local a
    for a in $AGENTS; do dirs="$dirs workspace-$a"; done
    # shellcheck disable=SC2086
    mkdir -p $dirs
    # shellcheck disable=SC2086
    own 1000:1000 $dirs
    chmod 700 config auth-secrets imap-mcp
    chmod 750 workspace workspace-*
    ls -ln
}

cmd_env() {
    # step 1.3: never overwrites an existing .env
    cd "$OC_DIR"
    if [ -e .env ]; then
        echo ".env already exists, left as it is"
    else
        local token
        token="$(openssl rand -hex 32)"
        [ "${#token}" -eq 64 ] || die "openssl rand failed"
        (umask 077 && cp "$HERE/env.example" .env)
        sed -i.tmp "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$token/" .env
        rm -f .env.tmp
        chmod 600 .env
        echo "created .env with a fresh gateway token"
    fi
    echo "keys still holding example values (fill them with: ${SUDO}nano $OC_DIR/.env):"
    grep -nE 'REPLACE|123456|you@icloud.com' .env | cut -d= -f1 || echo "  none"
}

cmd_compose() {
    # step 1.4
    cd "$OC_DIR"
    if [ -e docker-compose.yaml ]; then
        cp -p docker-compose.yaml "docker-compose.yaml.bak-$(stamp)"
    fi
    cp "$HERE/docker-compose.yaml" docker-compose.yaml
    dc config --quiet || die "docker-compose.yaml is invalid (see above)"
    echo "compose file valid"
    if [ ! -e config/openclaw.json ]; then
        echo "no config/openclaw.json yet: run 'host.sh config 1' to start the gateway"
        return
    fi
    dc up -d openclaw-gateway
    wait_live || die "gateway not live; see: ${SUDO}docker logs --tail 80 openclaw-gateway"
    docker exec openclaw-gateway id
    docker port openclaw-gateway
}

cmd_expose() {
    # step 1.5: the ports stay on 127.0.0.1; only Tailscale reaches them
    local what="${1:-gateway}" ports p
    case "$what" in
        gateway) ports="18789" ;;
        syncthing) ports="8384 22000" ;;
        *) die "usage: host.sh expose <gateway|syncthing>" ;;
    esac
    case "$HOST_TYPE" in
        ugos)
            echo "nothing to do: UGOS runs Tailscale in userspace mode and forwards tailnet connections to 127.0.0.1" ;;
        local)
            echo "nothing to do: a local install is only reachable on this computer (http://localhost:18789)" ;;
        linux)
            command -v tailscale > /dev/null || die "install Tailscale first: https://tailscale.com/download/linux"
            for p in $ports; do
                tailscale serve --bg --tcp="$p" "tcp://127.0.0.1:$p"
            done
            tailscale serve status ;;
    esac
}

cmd_config() {
    # step 1.6 workflow: stop, back up, merge, check, start, check again
    local phase="${1:-}" mode="${2:-}"
    [ -n "$phase" ] || die "usage: host.sh config <1-4> [--dry-run]"
    local tpl="$HERE/config/openclaw.phase$phase.json"
    [ -f "$tpl" ] || die "no $tpl (render it first; it is skipped while values are missing)"
    python3 -m json.tool "$tpl" > /dev/null || die "template is not valid JSON"
    cd "$OC_DIR"
    local live=config/openclaw.json tmp
    tmp="$(mktemp)"
    python3 "$HERE/merge_config.py" "$live" "$tpl" > "$tmp"
    python3 -m json.tool "$tmp" > /dev/null || die "merged config is not valid JSON"
    if [ "$mode" = "--dry-run" ]; then
        diff <(python3 -m json.tool "$live" 2> /dev/null || true) <(python3 -m json.tool "$tmp") || true
        rm -f "$tmp"
        return
    fi
    dc stop openclaw-gateway || true
    local bak=""
    if [ -e "$live" ]; then
        bak="$live.bak-$(stamp)"
        cp -p "$live" "$bak"
    fi
    cp "$tmp" "$live"
    rm -f "$tmp"
    own 1000:1000 "$live"
    chmod 600 "$live"
    dc up -d openclaw-gateway
    if ! wait_live; then
        config_errors
        [ -n "$bak" ] && echo "restore with: ${SUDO}cp $OC_DIR/$bak $OC_DIR/$live"
        die "gateway not live after the config change"
    fi
    config_errors
    if grep -q '"icloud-cal"' "$live"; then
        grep -q 'CALDAV_PASSWORD": "${ICLOUD_CAL_APP_PASSWORD}"' "$live" \
            && echo "calendar password: placeholder only" \
            || echo "WARNING: calendar password is not the placeholder"
    fi
    if grep -q '"icloud-mail"' "$live"; then
        grep -q 'IMAP_PASSWORD": "${ICLOUD_MAIL_APP_PASSWORD}"' "$live" \
            && echo "mail password: placeholder only" \
            || echo "WARNING: mail password is not the placeholder"
    fi
}

model_for() {
    case "$1" in
        calendar|email) echo "anthropic/claude-haiku-5-5" ;;
        events|news) echo "google/gemini-3.5-flash-lite" ;;
        *) die "unknown agent: $1 (one of: $AGENTS)" ;;
    esac
}

cmd_workspace() {
    # steps 1.10 and 2.3: instruction files from the bundle, never edited through chat
    local id="${1:-}" src="$HERE/workspaces" f
    [ -n "$id" ] || die "usage: host.sh workspace <main|agent>"
    [ -f "$src/$id/AGENTS.md" ] || die "no rendered $src/$id/AGENTS.md (missing values?)"
    cd "$OC_DIR"
    if [ "$id" = "main" ]; then
        rm -f workspace/AGENTS.md workspace/SOUL.md workspace/USER.md   # may be read-only
        cp "$src/main/AGENTS.md" "$src/shared/SOUL.md" "$src/shared/USER.md" workspace/
        for f in AGENTS.md SOUL.md USER.md; do
            if [ "$HOST_TYPE" = "local" ]; then
                chmod 444 "workspace/$f"     # read-only for the container
            else
                chown root:root "workspace/$f"
                chmod 644 "workspace/$f"
            fi
        done
        ls -l workspace/*.md
        return
    fi
    local dir="workspace-$id"
    rm -f "$dir/BOOTSTRAP.md"
    cp "$src/$id/AGENTS.md" "$src/$id/IDENTITY.md" "$src/shared/SOUL.md" "$src/shared/USER.md" "$dir/"
    chmod 644 "$dir/AGENTS.md" "$dir/IDENTITY.md" "$dir/SOUL.md" "$dir/USER.md"
    own -R 1000:1000 "$dir"
    ls -ln "$dir"
}

cmd_agent() {
    # agents add first (it creates agentDir and default files), then our files
    local id="${1:-}" model agents
    model="$(model_for "$id")"
    agents="$(oc agents list)"
    if grep -qw "$id" <<< "$agents"; then
        echo "agent $id already exists"
    else
        oc agents add "$id" --workspace "~/.openclaw/workspace-$id" --model "$model" --non-interactive \
            || die "agents add failed; if it mentions shared state, stop the gateway and use openclaw-offline"
    fi
    cmd_workspace "$id"
    echo "next: 'host.sh config <phase>' replaces the generated entry with the full one"
}

cmd_cron() {
    bash "$HERE/cron/jobs.sh" "${1:-}"
}

cmd_ids() {
    # step 1.9: user, group and topic IDs from recent bot updates; the token is never printed
    local token script
    token="$(grep '^TELEGRAM_BOT_TOKEN=' "$OC_DIR/.env" | cut -d= -f2- | tr -d "\"' \r" || true)"
    [ -n "$token" ] || die "TELEGRAM_BOT_TOKEN is empty in .env"
    read -r -d '' script <<'PY' || true
import json, sys
data = json.load(sys.stdin)
if not data.get("ok"):
    sys.exit("telegram: %s" % data.get("description"))
print("from_id", "chat_id", "topic_id", "text", sep="\t")
for update in data["result"]:
    msg = update.get("message")
    if not msg:
        continue
    created = (msg.get("forum_topic_created") or {}).get("name")
    text = created or (msg.get("text") or "")[:30]
    print(msg.get("from", {}).get("id"), msg.get("chat", {}).get("id"),
          msg.get("message_thread_id", "-"), text, sep="\t")
PY
    curl -m 10 -s "https://api.telegram.org/bot$token/getUpdates" | python3 -c "$script"
}

cmd_check() {
    # a secret-free report Claude Code can read without sudo
    local owner home report
    if [ "$HOST_TYPE" = "local" ]; then
        owner="$(id -un)"
        home="$HOME"
    else
        owner="${SUDO_USER:-root}"
        home="$(getent passwd "$owner" | cut -d: -f6)"
    fi
    report="$home/juniper-report.txt"
    {
        set +e  # a failing probe belongs in the report, it must not end it
        echo "== $(date '+%F %T') host=$HOST_TYPE dir=$OC_DIR"
        echo "== container"
        docker ps -a --filter name=openclaw-gateway --filter name=syncthing --format '{{.Names}}\t{{.Status}}'
        docker exec openclaw-gateway id
        docker port openclaw-gateway
        docker inspect openclaw-gateway --format 'nnp={{.HostConfig.SecurityOpt}} mem={{.HostConfig.Memory}} caps_drop={{.HostConfig.CapDrop}}'
        docker inspect openclaw-gateway --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
        curl -m 5 -s http://127.0.0.1:18789/healthz; echo
        if [ "$HOST_TYPE" = "linux" ]; then
            echo "== tailscale serve"; tailscale serve status
        fi
        echo "== agents";   oc agents list --bindings
        echo "== cron";     oc cron list
        echo "== mcp";      oc mcp list
        echo "== audit";    oc security audit --deep
        echo "== log (last hour, errors and code mode)"
        docker logs --since 1h openclaw-gateway 2>&1 | grep -iE "error|blocked|invalid|code-mode" | tail -30
    } 2>&1 | redact > "$report"
    own "$owner" "$report"
    chmod 600 "$report"
    echo "report written to $report"
}

usage() {
    cat <<USAGE
usage: ${SUDO}bash host.sh <command>      (host type: $HOST_TYPE, data: $OC_DIR)
  backup                 tar the current data folder (step 1.1)
  layout                 create folders and permissions (1.2)
  env                    create .env with a gateway token, list unfilled keys (1.3)
  compose                install docker-compose.yaml, start if configured (1.4)
  expose [syncthing]     make the gateway (or Syncthing) reachable over Tailscale (1.5)
  config <1-4> [--dry-run]  merge openclaw.phaseN.json into the live config (1.6 workflow)
  workspace <main|agent> install AGENTS.md, IDENTITY.md, SOUL.md, USER.md
  agent <id>             openclaw agents add + workspace files ($AGENTS)
  cron <agent>           add that agent's scheduled jobs
  ids                    print Telegram user, group and topic IDs (1.9)
  check                  write a secret-free status report to ~/juniper-report.txt
USAGE
}

case "$HOST_TYPE" in
    local) [ "$(id -u)" -ne 0 ] || die "a local install runs without sudo" ;;
    ugos|linux) [ "$(id -u)" -eq 0 ] || die "run with sudo" ;;
    *) die "unknown HOST_TYPE '$HOST_TYPE' in host.env" ;;
esac
command="${1:-}"
shift || true
case "$command" in
    backup|layout|env|compose|expose|config|workspace|agent|cron|ids|check) "cmd_$command" "$@" ;;
    *) usage; exit 2 ;;
esac
