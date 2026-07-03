#!/usr/bin/env bash
# start_sitl.sh — Launches ArduPilot SITL Copter + MAVLink Bridge for Argus GCS
# Usage: bash start_sitl.sh

ARDUPILOT_DIR="$HOME/ardupilot"
VENV="$HOME/venv-ardupilot"
BRIDGE_DIR="$HOME/Argus GCS"
LOG_DIR="$HOME/Argus GCS/sitl_logs"

mkdir -p "$LOG_DIR"

echo "════════════════════════════════════════════"
echo "   ARGUS GCS — ArduPilot SITL Launcher"
echo "════════════════════════════════════════════"

# Kill any stale processes
pkill -f "sim_vehicle.py"   2>/dev/null
pkill -f "arducopter"       2>/dev/null
pkill -f "mavproxy.py"      2>/dev/null
pkill -f "mavlink_bridge.py" 2>/dev/null
sleep 2

# ── 1. Launch SITL (skip rebuild, use existing binary) ───────────────────────
echo "[1/3] Starting ArduPilot Copter SITL..."
cd "$ARDUPILOT_DIR"
source "$VENV/bin/activate"

python3 "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" \
    -v ArduCopter \
    --no-rebuild \
    -A "--out=udp:127.0.0.1:14551" \
    --no-mavproxy-console \
    --no-mavproxy-map \
    > "$LOG_DIR/sitl.log" 2>&1 &

SITL_PID=$!
echo "   SITL PID: $SITL_PID"
echo "   Waiting 25s for SITL to initialise..."

# Wait for MAVProxy to bind port 14550
for i in $(seq 1 25); do
    sleep 1
    if ss -lun 2>/dev/null | grep -q ":14550"; then
        echo "   ✓ MAVProxy port 14550 detected after ${i}s"
        break
    fi
    printf "."
done
echo ""

# ── 2. Verify SITL is alive ──────────────────────────────────────────────────
if ! kill -0 $SITL_PID 2>/dev/null; then
    echo "ERROR: SITL process died. Check $LOG_DIR/sitl.log"
    tail -20 "$LOG_DIR/sitl.log"
    exit 1
fi

# ── 3. Start MAVLink → MQTT bridge ──────────────────────────────────────────
echo "[2/3] Starting MAVLink → MQTT bridge (connecting to UDP 14551)..."
python3 "$BRIDGE_DIR/mavlink_bridge.py" \
    --sitl-address "udp:127.0.0.1:14551" \
    --mqtt-host localhost \
    > "$LOG_DIR/bridge.log" 2>&1 &

BRIDGE_PID=$!
sleep 3

if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    echo "ERROR: Bridge process died. Check $LOG_DIR/bridge.log"
    cat "$LOG_DIR/bridge.log"
    exit 1
fi

echo "   Bridge PID: $BRIDGE_PID"

echo ""
echo "[3/3] All services running!"
echo ""
echo "   SITL port:   UDP 14550  → QGroundControl auto-connects here"
echo "   Bridge port: UDP 14551  → MQTT → Node-RED"
echo ""
echo "   SITL log:    $LOG_DIR/sitl.log"
echo "   Bridge log:  $LOG_DIR/bridge.log"
echo ""
echo "   Argus GCS:   http://127.0.0.1:1880/ui"
echo ""
echo "   QGroundControl: should auto-connect to UDP 14550"
echo "   If not, add connection: UDP, host 127.0.0.1, port 14550"
echo ""
echo "Press Ctrl+C to stop everything"

trap "echo 'Stopping...'; kill $SITL_PID $BRIDGE_PID 2>/dev/null; exit 0" INT TERM
wait
