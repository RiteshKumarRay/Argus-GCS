# Argus GCS

**Argus GCS** is a professional-grade Ground Control Station built on Node-RED, designed for real-time drone operations, autonomous mission planning, and emergency crash recovery. The UI features a premium dark-mode glassmorphism aesthetic with live telemetry, interactive mapping, AI-powered person detection, and a cryptographic flight log verification system.

![Argus GCS Dashboard](Photos/Dashboard.png)

---

## Tabs Overview

### ✈️ Flight
- **Real-time Telemetry:** Live altitude, speed, battery, heading, GPS coordinates, and link quality (RC / LoRa / Video)
- **Interactive Leaflet Map:** Dynamic WiFi/LoRa range rings, AI detection markers, waypoint overlays, and custom base layers with red geo-tag pins
- **3D Attitude Indicator:** Real-time Three.js drone model visualizing roll, pitch, and yaw
- **System Trust Scores:** Live IMU/GPS trust percentage with redundancy monitoring
- **Pre-Flight Checklist:** Automated GPS, IMU, battery, and link status verification before arming
- **Broadcast Rescue:** One-tap LoRa rescue broadcast for detected persons

### 📷 Cameras
- Multi-feed camera view with thermal and AI overlay controls

### 🗺️ Mission
- **Interactive Mission Planner:** Click-to-place waypoints on a live Leaflet map
- **Waypoint Panel:** Right-side list with per-waypoint action assignment (supporting all ArduPilot actions — Waypoint, Takeoff, Land, RTL, Loiter, DO_CHANGE_SPEED, DO_SET_CAM_TRIGG_DIST, DO_GRIPPER, and more)
- **Route Visualization:** Blue flight path lines with red geo-tag pins at each waypoint
- **Mission Export:** Serialized mission data ready for upload

### 📋 Logs
- **Flight Log Table:** 24-record flight log with REC#, TIME, GPS, ALT, SPD, HASH, and STATUS columns
- **Hash Chain Verifier:** Real-time SHA-256 chain verification engine with animated progress bar and terminal output
- **Tamper Simulation:** One-click demo that corrupts a GPS record and visually highlights chain breakage
- **Export:** PDF verification report and encrypted raw log export
- **Encryption:** AES-256 data protection, SHA-256 hash chaining

### 🚨 Recovery
- **Beacon Status:** Live pulsing green indicator showing LoRa beacon is active and transmitting
- **Incident Report:** Time of signal loss, last altitude, speed, GPS, battery, and flight time — all captured at the moment of crash
- **Live Recovery Map:** Dark tactical map showing HOME marker, dashed flight path, and a pulsing red geo-tag pin at the Last Known Position with radar-ping rings
- **Recovery Timeline:** Horizontal event log showing the full failover sequence from signal degradation → crash detection → beacon activation
- **Actions:** Open in Google Maps, Copy Coordinates, Broadcast Crash Location via LoRa
- **Backup LiPo Monitor:** Beacon battery voltage, percentage, and estimated runtime remaining

---

## Installation

The system is built on Node-RED.

1. Install dependencies:
   ```bash
   npm install
   ```
2. Start Node-RED:
   ```bash
   node-red
   ```
3. Import `flows.json` via the Node-RED editor (☰ → Import).
4. Open the dashboard at `http://localhost:1880/ui`.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend / Flow | Node-RED |
| UI Framework | AngularJS (Node-RED Dashboard) |
| Mapping | Leaflet.js |
| 3D Rendering | Three.js |
| Styling | Vanilla CSS (glassmorphism, dark mode) |
| Communication | LoRa, RC Link, Video Link |
| Hashing | SHA-256 (flight log integrity) |
| Encryption | AES-256 |

---

## License

MIT
