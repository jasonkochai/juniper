#!/usr/bin/env bash
# Juniper NAS helper. Runs on the NAS as root, from the rendered bundle:
#   sudo bash ~/juniper/nas.sh <command> [args]
# Every command is safe to re-run. Nothing here prints a secret.
set -euo pipefail

OC_DIR="${OC_DIR:-/volume1/docker/openclaw}"
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="calendar events email news comments"

die() { echo "error: $*" >&2; exit 1; }
stamp() { date +%Y%m%d-%H%M%S; }
dc() { docker compose -p openclaw-agents "$@"; }
oc() { docker exec openclaw-gateway node dist/index.js "$@"; }

wait_live() {
    local i
    for i in $(seq 1 24); do
        if curl -m 5 -s http://127.0.0.1:18789/healthz | grep -q '"status":"live"'; then
            echo "healthz: live"
            return 0
        fi
        sleep 5
    done
    return 1
}

config_errors() {
    docker logs --tail 60 openclaw-gateway 2>&1 \
        | grep -iE "blocked|invalid|unknown key|error" || echo "no config errors in the log"
}

cmd_backup() {
    # step 1.1: the archive holds tokens in plaintext, treat it like a password file
    local out="/volume1/docker/openclaw-backup-$(date +%F).tgz"
    tar czf "$out" -C /volume1/docker openclaw
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
    chown 1000:1000 $dirs
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
        (umask 077 && cp "$HERE/env.example" .env)
        sed -i "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)/" .env
        chmod 600 .env
        echo "created .env with a fresh gateway token"
    fi
    echo "keys still holding example values (fill them with: sudo nano $OC_DIR/.env):"
    grep -nE 'REPLACE|123456|you@icloud.com' .env | cut -d= -f1 || echo "  none"
}

cmd_compose() {
    # step 1.4
    cd "$OC_DIR"
    if [ -e docker-compose.yaml ]; then
        cp -p docker-compose.yaml "docker-compose.yaml.bak-$(stamp)"
    fi
    cp "$HERE/docker-compose.yaml" docker-compose.yaml
    dc config --quiet && echo "compose file valid"
    if [ ! -e config/openclaw.json ]; then
        echo "no config/openclaw.json yet: run 'nas.sh config 1' to start the gateway"
        return
    fi
    dc up -d openclaw-gateway
    wait_live || die "gateway not live; see: sudo docker logs --tail 80 openclaw-gateway"
    docker exec openclaw-gateway id
    docker port openclaw-gateway
}

cmd_config() {
    # step 1.6 workflow: stop, back up, merge, check, start, check again
    local phase="${1:-}" mode="${2:-}"
    local tpl="$HERE/config/openclaw.phase$phase.json"
    [ -f "$tpl" ] || die "no $tpl (render it on the Mac first; it is skipped while values are missing)"
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
    install -o 1000 -g 1000 -m 600 "$tmp" "$live"
    rm -f "$tmp"
    dc up -d openclaw-gateway
    if ! wait_live; then
        config_errors
        [ -n "$bak" ] && echo "restore with: sudo cp $OC_DIR/$bak $OC_DIR/$live"
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
        events|news|comments) echo "google/gemini-3.5-flash-lite" ;;
        *) die "unknown agent: $1 (one of: $AGENTS)" ;;
    esac
}

cmd_workspace() {
    # steps 1.10 and 2.3: instruction files from the bundle, never edited through chat
    local id="${1:-}" src="$HERE/workspaces"
    [ -n "$id" ] || die "usage: nas.sh workspace <main|agent>"
    [ -f "$src/$id/AGENTS.md" ] || die "no rendered $src/$id/AGENTS.md (missing values?)"
    cd "$OC_DIR"
    if [ "$id" = "main" ]; then
        install -o root -g root -m 644 "$src/main/AGENTS.md" workspace/AGENTS.md
        install -o root -g root -m 644 "$src/shared/SOUL.md" workspace/SOUL.md
        install -o root -g root -m 644 "$src/shared/USER.md" workspace/USER.md
        ls -l workspace/*.md
        return
    fi
    local dir="workspace-$id"
    rm -f "$dir/BOOTSTRAP.md"
    install -m 644 "$src/$id/AGENTS.md" "$dir/AGENTS.md"
    install -m 644 "$src/$id/IDENTITY.md" "$dir/IDENTITY.md"
    install -m 644 "$src/shared/SOUL.md" "$dir/SOUL.md"
    install -m 644 "$src/shared/USER.md" "$dir/USER.md"
    chown -R 1000:1000 "$dir"
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
    echo "next: 'nas.sh config <phase>' replaces the generated entry with the full one"
}

cmd_cron() {
    bash "$HERE/cron/jobs.sh" "${1:-}"
}

cmd_ids() {
    # step 1.9: user, group and topic IDs from recent bot updates; the token is never printed
    local token script
    token="$(grep '^TELEGRAM_BOT_TOKEN=' "$OC_DIR/.env" | cut -d= -f2-)"
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
    # a secret-free report the Mac side can read without sudo
    local owner="${SUDO_USER:-root}" home report
    home="$(getent passwd "$owner" | cut -d: -f6)"
    report="$home/juniper-report.txt"
    {
        set +e  # a failing probe belongs in the report, it must not end it
        echo "== $(date '+%F %T')"
        echo "== container"
        docker ps -a --filter name=openclaw-gateway --filter name=syncthing --format '{{.Names}}\t{{.Status}}'
        docker exec openclaw-gateway id
        docker port openclaw-gateway
        docker inspect openclaw-gateway --format 'nnp={{.HostConfig.SecurityOpt}} mem={{.HostConfig.Memory}} caps_drop={{.HostConfig.CapDrop}}'
        docker inspect openclaw-gateway --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
        curl -m 5 -s http://127.0.0.1:18789/healthz; echo
        echo "== agents";   oc agents list --bindings
        echo "== cron";     oc cron list
        echo "== mcp";      oc mcp list
        echo "== audit";    oc security audit --deep
        echo "== log (last hour, errors and code mode)"
        docker logs --since 1h openclaw-gateway 2>&1 | grep -iE "error|blocked|invalid|code-mode" | tail -30
    } 2>&1 | sed -E 's/(Authorization: *(Basic|Bearer) )[^ ]+/\1[redacted]/Ig' > "$report"
    chown "$owner" "$report"
    chmod 600 "$report"
    echo "report written to $report"
}

usage() {
    cat <<USAGE
usage: sudo bash nas.sh <command>
  backup                 tar the current $OC_DIR (step 1.1)
  layout                 create folders and permissions (1.2)
  env                    create .env with a gateway token, list unfilled keys (1.3)
  compose                install docker-compose.yaml, start if configured (1.4)
  config <1-5> [--dry-run]  merge openclaw.phaseN.json into the live config (1.6 workflow)
  workspace <main|agent> install AGENTS.md, IDENTITY.md, SOUL.md, USER.md
  agent <id>             openclaw agents add + workspace files ($AGENTS)
  cron <agent>           add that agent's scheduled jobs
  ids                    print Telegram user, group and topic IDs (1.9)
  check                  write a secret-free status report to ~/juniper-report.txt
USAGE
}

[ "$(id -u)" -eq 0 ] || die "run with sudo"
command="${1:-}"
shift || true
case "$command" in
    backup|layout|env|compose|config|workspace|agent|cron|ids|check) "cmd_$command" "$@" ;;
    *) usage; exit 2 ;;
esac
