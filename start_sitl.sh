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

# ── Kill ALL stale processes first ───────────────────────────────────────────
echo "Cleaning up stale processes..."
pkill -f "sim_vehicle.py"    2>/dev/null
pkill -f "arducopter"        2>/dev/null
pkill -f "mavproxy.py"       2>/dev/null
pkill -f "mavlink_bridge.py" 2>/dev/null

# Also kill anything sitting on UDP 14550 or 14551
fuser -k 14550/udp 2>/dev/null
fuser -k 14551/udp 2>/dev/null
sleep 3
echo "   Clean."

# ── 1. Launch SITL ───────────────────────────────────────────────────────────
echo "[1/3] Starting ArduPilot Copter SITL..."
echo "   (sim_vehicle.py auto-creates UDP 14550 for QGC + UDP 14551 for bridge)"
cd "$ARDUPILOT_DIR"
source "$VENV/bin/activate"

# Key flags:
#   -N         : --no-rebuild  (use existing binary, fast start)
#   -v         : vehicle type
#   No --out needed: sim_vehicle.py automatically binds 14550 + 14551
python3 "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" \
    -v ArduCopter \
    -N \
    > "$LOG_DIR/sitl.log" 2>&1 &

SITL_PID=$!
echo "   SITL PID: $SITL_PID"
echo "   Waiting for MAVProxy to bind port 14550..."

# Wait for the NEW process to open port 14550 (max 40s)
for i in $(seq 1 40); do
    sleep 1
    printf "   [%2ds] " $i
    if ! kill -0 $SITL_PID 2>/dev/null; then
        echo ""
        echo "ERROR: SITL process died after ${i}s."
        echo "Last 20 lines of sitl.log:"
        tail -20 "$LOG_DIR/sitl.log"
        exit 1
    fi
    if ss -lun 2>/dev/null | grep -q ":14550"; then
        echo "✓ Port 14550 up!"
        break
    fi
    echo "waiting..."
done

sleep 3  # Give MAVProxy a moment to fully settle

# Confirm SITL is still alive
if ! kill -0 $SITL_PID 2>/dev/null; then
    echo "ERROR: SITL process died during wait."
    tail -20 "$LOG_DIR/sitl.log"
    exit 1
fi

# ── 2. Start MAVLink → MQTT bridge ──────────────────────────────────────────
echo "[2/3] Starting MAVLink → MQTT bridge..."
echo "   Connecting to udp:127.0.0.1:14551 (auto-created by sim_vehicle.py)"

python3 "$BRIDGE_DIR/mavlink_bridge.py" \
    --sitl-address "udp:127.0.0.1:14551" \
    --mqtt-host localhost \
    > "$LOG_DIR/bridge.log" 2>&1 &

BRIDGE_PID=$!
sleep 3

if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    echo "ERROR: Bridge process died."
    cat "$LOG_DIR/bridge.log"
    exit 1
fi

echo "   Bridge PID: $BRIDGE_PID"

# ── 3. Done ──────────────────────────────────────────────────────────────────
echo ""
echo "[3/3] All services running!"
echo ""
echo "   UDP 14550  → QGroundControl (auto-connects)"
echo "   UDP 14551  → MAVLink bridge → MQTT → Argus GCS"
echo ""
echo "   SITL log:    $LOG_DIR/sitl.log"
echo "   Bridge log:  $LOG_DIR/bridge.log"
echo ""
echo "   Argus GCS:   http://127.0.0.1:1880/ui"
echo ""
echo "   Bridge status (live):"
sleep 2
head -5 "$LOG_DIR/bridge.log"
echo ""
echo "Press Ctrl+C to stop everything"

trap "echo 'Stopping...'; kill $SITL_PID $BRIDGE_PID 2>/dev/null; exit 0" INT TERM
wait
