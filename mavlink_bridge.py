#!/usr/bin/env python3
"""
mavlink_bridge.py — ArduPilot SITL → MQTT Telemetry Bridge for Argus GCS
Connects to ArduPilot SITL via UDP, parses MAVLink messages,
and publishes telemetry to a local MQTT broker.

Usage:
    python3 mavlink_bridge.py
    python3 mavlink_bridge.py --sitl-address udp:127.0.0.1:14550 --mqtt-host localhost

MQTT Topics published:
    argus/telemetry/gps        → {lat, lon, hdop, fix_type}
    argus/telemetry/attitude   → {roll, pitch, yaw, rollspeed, pitchspeed, yawspeed}
    argus/telemetry/vfrhud     → {airspeed, groundspeed, heading, throttle, alt, climb}
    argus/telemetry/battery    → {voltage, current, remaining}
    argus/telemetry/gps_raw    → {satellites_visible, fix_type, lat, lon, alt}
    argus/telemetry/heartbeat  → {base_mode, system_status, custom_mode}
    argus/telemetry/status     → {armed, mode, system_status}
    argus/telemetry/all        → (combined JSON of all the above, published every 250ms)
"""

import json
import time
import math
import argparse
import threading
from pymavlink import mavutil

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("ERROR: paho-mqtt not installed. Run: pip3 install paho-mqtt")
    exit(1)

# ── Config ──────────────────────────────────────────────────────────────────
DEFAULT_SITL   = "udp:127.0.0.1:14550"
DEFAULT_MQTT   = "localhost"
DEFAULT_PORT   = 1883
PUBLISH_HZ     = 4        # How often to publish the "all" combined topic
# ────────────────────────────────────────────────────────────────────────────

# ArduPilot custom mode names (COPTER)
COPTER_MODES = {
    0: "STABILIZE", 1: "ACRO", 2: "ALT_HOLD", 3: "AUTO",
    4: "GUIDED",    5: "LOITER", 6: "RTL",     7: "CIRCLE",
    9: "LAND",      11: "DRIFT", 13: "SPORT",  14: "FLIP",
    15: "AUTOTUNE", 16: "POSHOLD", 17: "BRAKE", 18: "THROW",
    19: "AVOID_ADSB", 20: "GUIDED_NOGPS", 21: "SMART_RTL",
    22: "FLOWHOLD", 23: "FOLLOW", 24: "ZIGZAG",
}

state = {
    "lat": 0.0, "lon": 0.0, "alt": 0.0, "rel_alt": 0.0,
    "home_lat": 0.0, "home_lon": 0.0, "home_alt": 0.0,
    "roll": 0.0, "pitch": 0.0, "yaw": 0.0,
    "rollspeed": 0.0, "pitchspeed": 0.0, "yawspeed": 0.0,
    "airspeed": 0.0, "groundspeed": 0.0, "heading": 0,
    "throttle": 0, "climb": 0.0,
    "voltage": 0.0, "current": 0.0, "battery_remaining": -1,  # -1 = no data yet
    "satellites": 0, "fix_type": 0, "hdop": 0.0,
    "armed": False, "mode": "UNKNOWN", "system_status": 0,
    "vx": 0.0, "vy": 0.0, "vz": 0.0,
    "ekf_ok": True, "last_heartbeat": 0,
    "connected": False,   # True after first heartbeat received
    "has_gps": False,     # True after first GPS_RAW_INT received
    "has_battery": False, # True after first battery message received
}

master = None # Global for MQTT command handler

def rad_to_deg(r):
    return round(math.degrees(r), 2)

def setup_mavlink(address):
    print(f"[MAVLink] Connecting to SITL at {address} ...")
    master = mavutil.mavlink_connection(address, baud=115200)
    master.wait_heartbeat(timeout=10)
    print(f"[MAVLink] Heartbeat received — System {master.target_system}, Component {master.target_component}")
    # Request all data streams
    master.mav.request_data_stream_send(
        master.target_system, master.target_component,
        mavutil.mavlink.MAV_DATA_STREAM_ALL, 10, 1
    )
    return master

def process_message(msg, mqtt_client):
    global state
    t = msg.get_type()

    if t == "HEARTBEAT":
        armed = bool(msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
        mode  = COPTER_MODES.get(msg.custom_mode, f"MODE_{msg.custom_mode}")
        was_connected = state["connected"]
        state.update({"armed": armed, "mode": mode,
                      "system_status": msg.system_status,
                      "last_heartbeat": time.time(),
                      "connected": True})
        if not was_connected:
            print(f"[Bridge] ✓ SITL connected! Mode={mode}, Armed={armed}")
        mqtt_client.publish("argus/telemetry/heartbeat", json.dumps({
            "armed": armed, "mode": mode,
            "base_mode": msg.base_mode,
            "system_status": msg.system_status,
            "custom_mode": msg.custom_mode,
        }))

    elif t == "GLOBAL_POSITION_INT":
        state.update({
            "lat":     msg.lat / 1e7,
            "lon":     msg.lon / 1e7,
            "alt":     msg.alt / 1000.0,
            "rel_alt": msg.relative_alt / 1000.0,
            "vx": msg.vx / 100.0, "vy": msg.vy / 100.0, "vz": msg.vz / 100.0,
            "heading": msg.hdg / 100.0 if msg.hdg != 65535 else state["heading"],
        })
        mqtt_client.publish("argus/telemetry/gps", json.dumps({
            "lat": state["lat"], "lon": state["lon"],
            "alt": state["alt"], "rel_alt": state["rel_alt"],
            "heading": state["heading"],
        }))

    elif t == "ATTITUDE":
        state.update({
            "roll":  rad_to_deg(msg.roll),
            "pitch": rad_to_deg(msg.pitch),
            "yaw":   rad_to_deg(msg.yaw),
            "rollspeed":  round(msg.rollspeed, 3),
            "pitchspeed": round(msg.pitchspeed, 3),
            "yawspeed":   round(msg.yawspeed, 3),
        })
        mqtt_client.publish("argus/telemetry/attitude", json.dumps({
            "roll": state["roll"], "pitch": state["pitch"], "yaw": state["yaw"],
            "rollspeed": state["rollspeed"], "pitchspeed": state["pitchspeed"],
            "yawspeed": state["yawspeed"],
        }))

    elif t == "VFR_HUD":
        state.update({
            "airspeed":    round(msg.airspeed, 1),
            "groundspeed": round(msg.groundspeed, 1),
            "heading":     msg.heading,
            "throttle":    msg.throttle,
            "alt":         round(msg.alt, 1),
            "climb":       round(msg.climb, 2),
        })
        mqtt_client.publish("argus/telemetry/vfrhud", json.dumps({
            "airspeed": state["airspeed"], "groundspeed": state["groundspeed"],
            "heading": state["heading"], "throttle": state["throttle"],
            "alt": state["alt"], "climb": state["climb"],
        }))

    elif t in ("BATTERY_STATUS", "SYS_STATUS"):
        if t == "SYS_STATUS":
            state.update({
                "voltage": round(msg.voltage_battery / 1000.0, 2),
                "current": round(msg.current_battery / 100.0, 2),
                "battery_remaining": msg.battery_remaining,
            })
        elif t == "BATTERY_STATUS":
            if msg.voltages and msg.voltages[0] != 65535:
                state["voltage"] = round(msg.voltages[0] / 1000.0, 2)
            state.update({
                "current": round(msg.current_battery / 100.0, 2) if msg.current_battery != -1 else state["current"],
                "battery_remaining": msg.battery_remaining if msg.battery_remaining != -1 else state["battery_remaining"],
            })
        mqtt_client.publish("argus/telemetry/battery", json.dumps({
            "voltage": state["voltage"],
            "current": state["current"],
            "remaining": state["battery_remaining"],
        }))

    elif t == "HOME_POSITION":
        state.update({
            "home_lat": msg.latitude / 1e7,
            "home_lon": msg.longitude / 1e7,
            "home_alt": msg.altitude / 1000.0,
        })

    elif t == "GPS_RAW_INT":
        state.update({
            "satellites": msg.satellites_visible,
            "fix_type":   msg.fix_type,
            "hdop":       round(msg.eph / 100.0, 2) if msg.eph != 65535 else 0.0,
        })
        mqtt_client.publish("argus/telemetry/gps_raw", json.dumps({
            "satellites": state["satellites"],
            "fix_type":   state["fix_type"],
            "hdop":       state["hdop"],
            "lat": msg.lat / 1e7, "lon": msg.lon / 1e7,
            "alt": msg.alt / 1000.0,
        }))

def publish_combined(mqtt_client):
    """Publish the full combined state at PUBLISH_HZ rate.
    Does NOT publish until a real heartbeat has been received from SITL."""
    print("[Bridge] Combined publisher running — waiting for SITL heartbeat...")
    while True:
        try:
            # Don't publish zeros before SITL is ready
            if not state["connected"]:
                time.sleep(0.5)
                continue
            payload = {
                "lat":         state["lat"],
                "lon":         state["lon"],
                "alt":         state["alt"],
                "home_lat":    state["home_lat"],
                "home_lon":    state["home_lon"],
                "rel_alt":     state["rel_alt"],
                "roll":        state["roll"],
                "pitch":       state["pitch"],
                "yaw":         state["yaw"],
                "heading":     state["heading"],
                "airspeed":    state["airspeed"],
                "groundspeed": state["groundspeed"],
                "throttle":    state["throttle"],
                "climb":       state["climb"],
                "voltage":     state["voltage"],
                "current":     state["current"],
                # Only send battery once we have real data (not -1 placeholder)
                "battery":     state["battery_remaining"] if state["battery_remaining"] >= 0 else 0,
                "satellites":  state["satellites"],
                "fix_type":    state["fix_type"],
                "hdop":        state["hdop"],
                "armed":       state["armed"],
                "mode":        state["mode"],
                "system_status": state["system_status"],
            }
            mqtt_client.publish("argus/telemetry/all", json.dumps(payload))
        except Exception as e:
            print(f"[MQTT] Publish error: {e}")
        time.sleep(1.0 / PUBLISH_HZ)

def main():
    parser = argparse.ArgumentParser(description="MAVLink → MQTT bridge for Argus GCS")
    parser.add_argument("--sitl-address", default=DEFAULT_SITL, help="MAVLink connection string")
    parser.add_argument("--mqtt-host",    default=DEFAULT_MQTT, help="MQTT broker host")
    parser.add_argument("--mqtt-port",    default=DEFAULT_PORT,  type=int, help="MQTT broker port")
    args = parser.parse_args()

    # Connect MQTT
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="argus-mavlink-bridge")
    
    def on_connect(c, u, f, r, p):
        print(f"[MQTT] Connected to broker at {args.mqtt_host}:{args.mqtt_port}")
        c.subscribe("argus/command/drone")
        
    def on_message(c, u, msg):
        global master
        if master is None: return
        try:
            cmd = json.loads(msg.payload.decode('utf-8'))
            action = cmd.get("action")
            print(f"[Command] Received: {action}")
            if action == "arm":
                arm_state = 1 if cmd.get("state", True) else 0
                if arm_state == 1:
                    # Switch to GUIDED mode to allow GCS arming
                    master.mav.set_mode_send(master.target_system, mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 4)
                master.mav.command_long_send(
                    master.target_system, master.target_component,
                    mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                    0, arm_state, 0, 0, 0, 0, 0, 0)
            elif action == "takeoff":
                # Ensure GUIDED mode for takeoff
                master.mav.set_mode_send(master.target_system, mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 4)
                master.mav.command_long_send(
                    master.target_system, master.target_component,
                    mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
                    0, 0, 0, 0, 0, 0, 0, 10) # Take-off to 10m
            elif action == "land":
                # Switch to LAND mode (custom mode 9)
                master.mav.set_mode_send(master.target_system, mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 9)
            elif action == "rtl":
                # Switch to RTL mode (custom mode 6)
                master.mav.set_mode_send(master.target_system, mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 6)
        except Exception as e:
            print(f"[Command] Error processing msg: {e}")

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(args.mqtt_host, args.mqtt_port, keepalive=60)
    client.loop_start()

    # Start combined publisher thread
    t = threading.Thread(target=publish_combined, args=(client,), daemon=True)
    t.start()

    # Connect MAVLink
    global master
    master = setup_mavlink(args.sitl_address)

    print("[Bridge] Running. Press Ctrl+C to stop.")
    while True:
        try:
            msg = master.recv_match(blocking=True, timeout=1.0)
            if msg:
                process_message(msg, client)
        except KeyboardInterrupt:
            print("\n[Bridge] Stopped.")
            break
        except Exception as e:
            print(f"[MAVLink] Error: {e}")
            time.sleep(1)

    client.loop_stop()
    client.disconnect()

if __name__ == "__main__":
    main()
