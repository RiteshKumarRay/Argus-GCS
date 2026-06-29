# Argus GCS

**Argus GCS** is a modern, high-performance Ground Control Station (GCS) built using Node-RED. Designed with a clean, glassmorphism-inspired UI, it provides real-time telemetry tracking, 3D attitude visualization, and seamless mission management for autonomous vehicles.

![Argus GCS Dashboard](Photos/Dashboard.png)

## Features
- **Real-time Telemetry:** Live tracking of altitude, speed, battery, heading, and GPS coordinates.
- **Interactive Map:** Powered by Leaflet, featuring dynamic ranges (WiFi/LoRa), waypoint planning, and custom base layers.
- **3D Attitude Indicator:** Real-time Three.js drone rendering visualizing roll, pitch, and yaw.
- **System Redundancy:** Live monitoring of RC, LoRa, and Video links along with real-time IMU/GPS trust scores.
- **AI Detections:** Person detection mapping with automatic coordinate logging and quick-clear functionality.
- **Mission Control:** Quick-access tools for clearing paths, enabling thermal overlays, and system arming/RTL.

## Installation
The system is built on Node-RED. 

1. Install dependencies via `npm install`.
2. Start Node-RED.
3. Import the `flows.json` file.
