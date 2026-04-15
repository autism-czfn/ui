#!/usr/bin/env bash

PORT=19000
PIDFILE=".serve.pid"
LOGFILE="serve.log"

NGINX_TEMPLATE="config/nginx/ui.conf"
NGINX_TARGET="/etc/nginx/conf.d/ui.conf"
NGINX_PLACEHOLDER="__PUBLIC_IP__"

get_local_ip() {
    # Try Linux first, then macOS, then fall back to localhost
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' \
    || ipconfig getifaddr en0 2>/dev/null \
    || ipconfig getifaddr en1 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}' \
    || echo "127.0.0.1"
}

get_public_ip() {
    # Query several public IP echo services in turn; first success wins.
    # Each call has a hard timeout so a hung resolver can't stall setup.
    local svc ip
    for svc in https://ifconfig.me https://api.ipify.org https://icanhazip.com https://ipv4.icanhazip.com; do
        ip=$(curl -fsS --max-time 4 -4 "$svc" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

install_nginx_config() {
    echo ""
    if [ ! -f "$NGINX_TEMPLATE" ]; then
        echo "  ❌  Template not found: $NGINX_TEMPLATE"
        echo "      (run this from the ui/ project directory)"
        echo ""
        return
    fi

    if ! grep -q "$NGINX_PLACEHOLDER" "$NGINX_TEMPLATE"; then
        echo "  ⚠️   Placeholder $NGINX_PLACEHOLDER not found in $NGINX_TEMPLATE"
        echo "      Has the template already been substituted by hand?"
        echo ""
        return
    fi

    echo "  🌐  Detecting public IP..."
    local ip
    ip=$(get_public_ip)
    if [ -z "$ip" ]; then
        echo "  ❌  Could not detect public IP from any echo service"
        printf "  ✏️   Enter public IP manually (or blank to abort): "
        read -r ip
        if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "  ✋  Aborted"
            echo ""
            return
        fi
    fi
    echo "  ✅  Public IP: $ip"

    # Render template into a tempfile, then install via sudo.
    local rendered
    rendered=$(mktemp)
    sed "s/$NGINX_PLACEHOLDER/$ip/g" "$NGINX_TEMPLATE" > "$rendered"

    if grep -q "$NGINX_PLACEHOLDER" "$rendered"; then
        echo "  ❌  Substitution failed — placeholder still present"
        rm -f "$rendered"
        echo ""
        return
    fi

    # Show the diff (if any) before clobbering the live file
    if [ -f "$NGINX_TARGET" ] && command -v diff >/dev/null 2>&1; then
        if sudo diff -q "$NGINX_TARGET" "$rendered" >/dev/null 2>&1; then
            echo "  ✓   $NGINX_TARGET is already up-to-date"
            rm -f "$rendered"
            echo ""
            return
        fi
        echo "  📋  Pending changes vs $NGINX_TARGET:"
        sudo diff -u "$NGINX_TARGET" "$rendered" | sed 's/^/      /' | head -40
    fi

    printf "  ❓  Install and reload nginx? [y/N] "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "  ✋  Aborted (rendered file kept at $rendered)"
        echo ""
        return
    fi

    sudo install -m 644 -o root -g root "$rendered" "$NGINX_TARGET" || {
        echo "  ❌  Install failed"
        rm -f "$rendered"
        echo ""
        return
    }
    rm -f "$rendered"

    if ! sudo nginx -t 2>&1 | sed 's/^/      /'; then
        echo "  ❌  nginx -t failed — config NOT reloaded"
        echo ""
        return
    fi

    if sudo systemctl reload nginx; then
        echo "  ✅  nginx reloaded — $NGINX_TARGET is live with public IP $ip"
    else
        echo "  ❌  systemctl reload nginx failed"
    fi
    echo ""
}

port_pid() {
    # Return the PID of whatever process is bound to $PORT (empty if none)
    ss -tlnp "sport = :$PORT" 2>/dev/null \
        | grep -oP 'pid=\K[0-9]+' \
        | head -1
}

is_running() {
    # True when something is actually listening on the port
    [ -n "$(port_pid)" ]
}

start_service() {
    echo ""
    if is_running; then
        echo "  ↻  Service already running — restarting..."
        stop_service
    fi

    nohup python3 -u serve.py > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"

    # Wait up to 3 seconds for the port to open
    local i=0
    while [ $i -lt 6 ]; do
        is_running && break
        sleep 0.5
        i=$((i + 1))
    done

    if is_running; then
        local ip
        ip=$(get_local_ip)
        echo "  ✅  Service started (PID $(cat $PIDFILE))"
        echo "  🌐  UI: https://$ip:$PORT/"
        echo "  📄  Logs: $LOGFILE"
    else
        echo "  ❌  Failed to start — check $LOGFILE for details"
        tail -5 "$LOGFILE" 2>/dev/null | sed 's/^/      /'
    fi
    echo ""
}

stop_service() {
    echo ""
    local pid
    pid=$(port_pid)

    if [ -z "$pid" ]; then
        echo "  ⚠️   Service is not running"
        rm -f "$PIDFILE"
        echo ""
        return
    fi

    echo "  🛑  Stopping PID $pid..."
    kill "$pid" 2>/dev/null

    # Wait up to 5 seconds for the port to actually close
    local i=0
    while [ $i -lt 10 ]; do
        sleep 0.5
        is_running || break
        i=$((i + 1))
    done

    # Force-kill if still alive
    if is_running; then
        echo "  ⚡  SIGTERM timed out — sending SIGKILL..."
        kill -9 "$pid" 2>/dev/null
        sleep 0.5
    fi

    if is_running; then
        echo "  ❌  Could not stop service (PID $(port_pid) still on port $PORT)"
    else
        echo "  ✅  Service stopped"
    fi

    rm -f "$PIDFILE"
    echo ""
}

service_status() {
    echo ""
    local pid
    pid=$(port_pid)

    if [ -n "$pid" ]; then
        local ip
        ip=$(get_local_ip)
        echo "  ✅  Service is running"
        echo "  🔢  PID:  $pid"
        echo "  🌐  URL:  https://$ip:$PORT/"

        # Uptime via /proc
        if [ -f "/proc/$pid/stat" ]; then
            local start_ticks uptime_sec btime elapsed
            start_ticks=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)
            btime=$(awk '/^btime/{print $2}' /proc/stat 2>/dev/null)
            if [ -n "$start_ticks" ] && [ -n "$btime" ]; then
                local hz; hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
                elapsed=$(( $(date +%s) - btime - start_ticks / hz ))
                local h=$((elapsed/3600)) m=$(( (elapsed%3600)/60 )) s=$((elapsed%60))
                printf "  ⏱️   Up:   %dh %02dm %02ds\n" "$h" "$m" "$s"
            fi
        fi

        # HTTP reachability
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 -k "https://127.0.0.1:$PORT/" 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            echo "  💚  HTTP: OK (200)"
        else
            echo "  ⚠️   HTTP: unexpected response (HTTP ${http_code:-timeout})"
        fi
    else
        echo "  🔴  Service is NOT running"
    fi

    # Last 5 log lines (always shown)
    if [ -f "$LOGFILE" ] && [ -s "$LOGFILE" ]; then
        echo "  ─────────────────────────────────"
        echo "  📄  Last log lines ($LOGFILE):"
        tail -5 "$LOGFILE" | sed 's/^/      /'
    fi
    echo ""
}

# ── Menu ───────────────────────────────────────────────────────────────────────

while true; do
    echo "╔══════════════════════════════════╗"
    echo "║       Autism Q&A UI Server       ║"
    echo "╠══════════════════════════════════╣"
    echo "║  1) Start / Restart service      ║"
    echo "║  2) Stop service                 ║"
    echo "║  3) Service status               ║"
    echo "║  4) Install nginx config         ║"
    echo "║  0) Exit                         ║"
    echo "╚══════════════════════════════════╝"
    printf "  Choose an option: "
    read -r choice

    case "$choice" in
        1) start_service ;;
        2) stop_service ;;
        3) service_status ;;
        4) install_nginx_config ;;
        0) echo ""; echo "  Bye!"; echo ""; exit 0 ;;
        *) echo ""; echo "  ⚠️  Invalid option, try again."; echo "" ;;
    esac
done
