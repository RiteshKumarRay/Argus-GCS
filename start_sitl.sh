#!/usr/bin/env bash
# start_sitl.sh — Launches ArduPilot SITL Copter + MAVLink Bridge for Argus GCS
# Runs ArduCopter + MAVProxy directly (no sim_vehicle.py / no xterm needed)
# Usage: bash start_sitl.sh

set -e

ARDUPILOT_DIR="$HOME/ardupilot"
VENV="$HOME/venv-ardupilot"
BRIDGE_DIR="$HOME/Argus GCS"
LOG_DIR="$HOME/Argus GCS/sitl_logs"
COPTER_BIN="$ARDUPILOT_DIR/build/sitl/bin/arducopter"
PARM_FILE="$ARDUPILOT_DIR/Tools/autotest/default_params/copter.parm"
SITL_WDIR="$LOG_DIR/sitl_home"   # ArduCopter writes logs/params here

mkdir -p "$LOG_DIR" "$SITL_WDIR"

echo "════════════════════════════════════════════"
echo "   ARGUS GCS — ArduPilot SITL Launcher"
echo "════════════════════════════════════════════"

# ── Kill stale processes ──────────────────────────────────────────────────────
echo "Cleaning up stale processes..."
pkill -f "arducopter"        2>/dev/null || true
pkill -f "mavproxy.py"       2>/dev/null || true
pkill -f "mavlink_bridge.py" 2>/dev/null || true
fuser -k 5760/tcp  2>/dev/null || true
fuser -k 14550/udp 2>/dev/null || true
fuser -k 14551/udp 2>/dev/null || true
sleep 2
echo "   Done."

source "$VENV/bin/activate"

# ── 1. Start ArduCopter SITL directly (no xterm needed) ──────────────────────
echo "[1/3] Starting ArduCopter SITL binary..."
cd "$SITL_WDIR"
"$COPTER_BIN" \
    --model + \
    --speedup 1 \
    --slave 0 \
    --sim-address 127.0.0.1 \
    -I 0 \
    --defaults "$PARM_FILE" \
    > "$LOG_DIR/arducopter.log" 2>&1 &

COPTER_PID=$!
echo "   ArduCopter PID: $COPTER_PID"
echo "   Waiting for ArduCopter to bind TCP 5760..."

for i in $(seq 1 30); do
    sleep 1
    if ! kill -0 $COPTER_PID 2>/dev/null; then
        echo ""
        echo "ERROR: ArduCopter died after ${i}s. Log:"
        tail -20 "$LOG_DIR/arducopter.log"
        exit 1
    fi
    if ss -ltn 2>/dev/null | grep -q ":5760"; then
        echo "   ✓ TCP 5760 ready after ${i}s"
        break
    fi
    printf "."
done
echo ""

# ── 2. Start MAVProxy ────────────────────────────────────────────────────────
echo "[2/3] Starting MAVProxy..."
echo "   → UDP 14550 (QGroundControl)"
echo "   → UDP 14551 (Argus bridge)"

mavproxy.py \
    --master tcp:127.0.0.1:5760 \
    --sitl 127.0.0.1:5501 \
    --out udp:127.0.0.1:14550 \
    --out udp:127.0.0.1:14551 \
    --retries 10 \
    > "$LOG_DIR/mavproxy.log" 2>&1 &

MAVPROXY_PID=$!
echo "   MAVProxy PID: $MAVPROXY_PID"

# Wait for MAVProxy to bind 14550
echo "   Waiting for MAVProxy to bind UDP 14550..."
for i in $(seq 1 20); do
    sleep 1
    if ! kill -0 $MAVPROXY_PID 2>/dev/null; then
        echo ""
        echo "ERROR: MAVProxy died. Log:"
        tail -15 "$LOG_DIR/mavproxy.log"
        kill $COPTER_PID 2>/dev/null
        exit 1
    fi
    if ss -lun 2>/dev/null | grep -q ":14550"; then
        echo "   ✓ UDP 14550 ready after ${i}s"
        break
    fi
    printf "."
done
echo ""

# ── 3. Start MAVLink → MQTT bridge ──────────────────────────────────────────
echo "[3/3] Starting MAVLink → MQTT bridge..."
python3 "$BRIDGE_DIR/mavlink_bridge.py" \
    --sitl-address "udp:127.0.0.1:14551" \
    --mqtt-host localhost \
    > "$LOG_DIR/bridge.log" 2>&1 &

BRIDGE_PID=$!
sleep 3

if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    echo "ERROR: Bridge died. Log:"
    cat "$LOG_DIR/bridge.log"
    kill $COPTER_PID $MAVPROXY_PID 2>/dev/null
    exit 1
fi

echo "   Bridge PID: $BRIDGE_PID"

echo ""
echo "══════════════════════════════════════════════"
echo "   ✓ ALL SERVICES RUNNING"
echo "══════════════════════════════════════════════"
echo ""
echo "   UDP 14550  → QGroundControl"
echo "   UDP 14551  → MAVLink bridge → MQTT → Argus GCS"
echo ""
echo "   Logs:"
echo "   ArduCopter: $LOG_DIR/arducopter.log"
echo "   MAVProxy:   $LOG_DIR/mavproxy.log"
echo "   Bridge:     $LOG_DIR/bridge.log"
echo ""
echo "   Argus GCS:  http://127.0.0.1:1880/ui"
echo ""
echo "Press Ctrl+C to stop everything"

trap "echo ''; echo 'Stopping all...'; kill $COPTER_PID $MAVPROXY_PID $BRIDGE_PID 2>/dev/null; exit 0" INT TERM
wait
