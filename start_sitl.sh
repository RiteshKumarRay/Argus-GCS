#!/usr/bin/env bash
# start_sitl.sh — Launches ArduPilot SITL Copter + MAVProxy + Argus MAVLink Bridge
# Usage: bash start_sitl.sh

set -e
ARDUPILOT_DIR="$HOME/ardupilot"
VENV="$HOME/venv-ardupilot"
BRIDGE_DIR="$HOME/Argus GCS"
LOG_DIR="$HOME/Argus GCS/sitl_logs"

mkdir -p "$LOG_DIR"

echo "════════════════════════════════════════════"
echo "   ARGUS GCS — ArduPilot SITL Launcher"
echo "════════════════════════════════════════════"

# 1. Start SITL
echo "[1/3] Starting ArduPilot Copter SITL..."
cd "$ARDUPILOT_DIR"
source "$VENV/bin/activate"

# Kill any existing SITL or bridge processes
pkill -f "sim_vehicle.py" 2>/dev/null || true
pkill -f "mavlink_bridge.py" 2>/dev/null || true
sleep 1

# Launch SITL in background — outputs MAVLink on UDP 14550 and 14551
python3 "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" \
    -v ArduCopter \
    --out=udp:127.0.0.1:14550 \
    --out=udp:127.0.0.1:14551 \
    --map \
    --console \
    -S 1 \
    > "$LOG_DIR/sitl.log" 2>&1 &

SITL_PID=$!
echo "    SITL PID: $SITL_PID — waiting for init..."
sleep 8

# 2. Start the MAVLink → MQTT bridge
echo "[2/3] Starting MAVLink → MQTT bridge..."
python3 "$BRIDGE_DIR/mavlink_bridge.py" \
    --sitl-address udp:127.0.0.1:14551 \
    --mqtt-host localhost \
    > "$LOG_DIR/bridge.log" 2>&1 &

BRIDGE_PID=$!
echo "    Bridge PID: $BRIDGE_PID"

echo ""
echo "[3/3] All services running!"
echo ""
echo "  SITL log:   $LOG_DIR/sitl.log"
echo "  Bridge log: $LOG_DIR/bridge.log"
echo ""
echo "  MQTT topics: argus/telemetry/all"
echo "               argus/telemetry/gps"
echo "               argus/telemetry/attitude"
echo "               argus/telemetry/battery"
echo ""
echo "  Argus GCS:   http://127.0.0.1:1880/ui"
echo ""
echo "Press Ctrl+C to stop everything"

# Wait and cleanup on exit
trap "echo 'Stopping...'; kill $SITL_PID $BRIDGE_PID 2>/dev/null; exit 0" INT TERM
wait
