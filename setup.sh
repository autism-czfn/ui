#!/usr/bin/env bash

HOST="192.168.1.9"
PORT=18000
PIDFILE=".serve.pid"
LOGFILE="serve.log"

is_running() {
    if [ -f "$PIDFILE" ]; then
        local pid
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

start_service() {
    echo ""
    if is_running; then
        local pid
        pid=$(cat "$PIDFILE")
        echo "  ↻  Service already running (PID $pid) — restarting..."
        kill "$pid" 2>/dev/null
        sleep 1
    fi

    nohup python3 serve.py > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1

    if is_running; then
        echo "  ✅  Service started (PID $(cat $PIDFILE))"
        echo "  🌐  UI: http://$HOST:$PORT/"
        echo "  📄  Logs: $LOGFILE"
    else
        echo "  ❌  Failed to start — check $LOGFILE for details"
    fi
    echo ""
}

stop_service() {
    echo ""
    if is_running; then
        local pid
        pid=$(cat "$PIDFILE")
        kill "$pid" 2>/dev/null
        rm -f "$PIDFILE"
        echo "  🛑  Service stopped (PID $pid)"
    else
        echo "  ⚠️   Service is not running"
    fi
    echo ""
}

service_status() {
    echo ""
    if is_running; then
        local pid
        pid=$(cat "$PIDFILE")
        echo "  ✅  Service is running (PID $pid)"
        echo "  🌐  http://$HOST:$PORT/"

        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST:$PORT/" 2>/dev/null)
        if [ "$http_code" = "200" ]; then
            echo "  💚  HTTP check: OK (200)"
        else
            echo "  ⚠️   HTTP check: no response (HTTP $http_code)"
        fi
    else
        echo "  🔴  Service is NOT running"
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
    echo "║  0) Exit                         ║"
    echo "╚══════════════════════════════════╝"
    printf "  Choose an option: "
    read -r choice

    case "$choice" in
        1) start_service ;;
        2) stop_service ;;
        3) service_status ;;
        0) echo ""; echo "  Bye!"; echo ""; exit 0 ;;
        *) echo ""; echo "  ⚠️  Invalid option, try again."; echo "" ;;
    esac
done
