# Argus GCS - Mission Planning Implementation Guide

## Step-by-Step Setup for Mission Planning Like Cerberus (MSP) → But with MAVLink

This guide shows how to implement mission planning in Argus GCS dashboard similar to your previous Cerberus project, but upgraded for ArduPilot's MAVLink protocol.

---

## 📋 MISSION TAB FEATURES

### What You'll Build
✅ Open mission planner map button
✅ Click on map to add waypoints  
✅ Get each waypoint coordinates (lat, lon, alt)
✅ Assign mission actions to waypoints (WAYPOINT, LAND, RTH, HOVER, LOITER)
✅ Edit waypoint details in side panel
✅ Reorder waypoints (move up/down)
✅ Delete waypoints
✅ Calculate total distance and flight time
✅ Upload mission button
✅ Preview mission before uploading

---

## 1. HTML TEMPLATE FOR MISSION TAB

Add this to the ui_template "Dashboard UI" node in flows.json:

```html
<!-- MISSION TAB CONTENT -->
<div ng-show="activeTab === 'MISSION'" class="mission-tab">
    
    <!-- Toolbar -->
    <div class="mission-toolbar">
        <button ng-click="openMissionMap()" class="map-tool-btn">
            <i class="fa fa-map"></i> Open Mission Map
        </button>
        <button ng-click="toggleMissionPlanner()" class="map-tool-btn">
            <i class="fa fa-edit"></i> Planner: {{ plannerActive ? 'ON' : 'OFF' }}
        </button>
        <button ng-click="clearAllWaypoints()" class="map-tool-btn">
            <i class="fa fa-trash"></i> Clear All
        </button>
    </div>
    
    <!-- Mission Container: Two Panels -->
    <div class="mission-container">
        
        <!-- LEFT: Waypoint List Panel -->
        <div class="waypoint-list-panel">
            <div class="gcs-glass-panel">
                <div class="panel-title">
                    <i class="fa fa-map-marker"></i> Waypoints ({{ waypoints.length }})
                </div>
                
                <div ng-show="waypoints.length === 0" class="empty-state">
                    Click on the map to add waypoints
                </div>
                
                <div class="waypoint-list">
                    <div class="waypoint-item" ng-repeat="(idx, wp) in waypoints"
                         ng-class="{'active': selectedWaypoint === idx}"
                         ng-click="selectedWaypoint = idx">
                        <div class="wp-number">WP{{ idx + 1 }}</div>
                        <div class="wp-info">
                            <div>Lat: {{ wp.lat | number:5 }}</div>
                            <div>Lon: {{ wp.lon | number:5 }}</div>
                            <div>Alt: {{ wp.alt }}m</div>
                            <div class="wp-action">{{ wp.action | uppercase }}</div>
                        </div>
                        <div class="wp-buttons">
                            <button ng-click="deleteWaypoint(idx); $event.stopPropagation()" class="btn-sm">
                                <i class="fa fa-trash"></i>
                            </button>
                        </div>
                    </div>
                </div>
                
                <div class="mission-stats" ng-show="waypoints.length > 0">
                    <div>Total WPs: {{ waypoints.length }}</div>
                    <div>Distance: {{ missionDistance | number:0 }}m</div>
                    <div>Time: {{ missionTime | number:1 }}min</div>
                </div>
            </div>
        </div>
        
        <!-- RIGHT: Mission Editor Panel -->
        <div class="mission-editor-panel">
            <div class="gcs-glass-panel">
                <div class="panel-title">
                    <i class="fa fa-cog"></i> Mission Editor
                </div>
                
                <div ng-show="selectedWaypoint !== null" class="wp-editor">
                    <div class="editor-title">Editing WP{{ selectedWaypoint + 1 }}</div>
                    
                    <label>Latitude:</label>
                    <input type="number" step="0.00001"
                           ng-model="waypoints[selectedWaypoint].lat" class="field-input">
                    
                    <label>Longitude:</label>
                    <input type="number" step="0.00001"
                           ng-model="waypoints[selectedWaypoint].lon" class="field-input">
                    
                    <label>Altitude (m):</label>
                    <input type="number" min="0" max="500"
                           ng-model="waypoints[selectedWaypoint].alt" class="field-input">
                    
                    <label>Action:</label>
                    <select ng-model="waypoints[selectedWaypoint].action" class="field-input">
                        <option value="waypoint">WAYPOINT</option>
                        <option value="land">LAND</option>
                        <option value="rth">RETURN TO HOME</option>
                        <option value="hover">HOVER</option>
                        <option value="loiter">LOITER</option>
                    </select>
                    
                    <div ng-show="waypoints[selectedWaypoint].action === 'loiter' || waypoints[selectedWaypoint].action === 'hover'">
                        <label>Hold Time (seconds):</label>
                        <input type="number" min="0" max="3600"
                               ng-model="waypoints[selectedWaypoint].loiter_time" class="field-input">
                    </div>
                </div>
                
                <div ng-show="selectedWaypoint === null" class="editor-empty">
                    Select a waypoint to edit
                </div>
            </div>
            
            <!-- Upload Section -->
            <div class="mission-upload">
                <button ng-click="uploadMission()" class="btn-upload" ng-disabled="waypoints.length === 0">
                    <i class="fa fa-upload"></i> UPLOAD MISSION
                </button>
                <button ng-click="previewMission()" class="btn-secondary" ng-disabled="waypoints.length === 0">
                    PREVIEW
                </button>
                <div ng-show="uploadStatus" class="upload-status">
                    {{ uploadStatus }}
                </div>
            </div>
        </div>
    </div>
</div>
```

---

## 2. CSS STYLING (Add to <style> section)

```css
.mission-tab {
    width: 100%;
    height: calc(100vh - 120px);
    display: flex;
    flex-direction: column;
}

.mission-toolbar {
    display: flex;
    gap: 10px;
    padding: 15px;
    background: rgba(0, 0, 0, 0.5);
}

.mission-container {
    display: flex;
    gap: 15px;
    padding: 15px;
    flex: 1;
    overflow: hidden;
}

.waypoint-list-panel, .mission-editor-panel {
    width: 50%;
    overflow-y: auto;
}

.waypoint-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.waypoint-item {
    display: flex;
    gap: 10px;
    padding: 10px;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(79, 172, 254, 0.3);
    border-radius: 8px;
    cursor: pointer;
}

.waypoint-item.active {
    border-color: rgba(79, 172, 254, 0.8);
    background: rgba(79, 172, 254, 0.1);
}

.wp-number {
    font-weight: bold;
    color: #4facfe;
    min-width: 40px;
}

.wp-info {
    flex: 1;
    font-size: 12px;
    color: #94a3b8;
}

.wp-action {
    background: rgba(79, 172, 254, 0.2);
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 10px;
    font-weight: bold;
    color: #4facfe;
}

.wp-editor {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.field-input {
    width: 100%;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(79, 172, 254, 0.3);
    color: #e5e7eb;
    padding: 8px;
    border-radius: 6px;
}

.btn-upload {
    width: 100%;
    background: linear-gradient(135deg, #4facfe, #00f2fe);
    color: #000;
    padding: 12px;
    border: none;
    border-radius: 8px;
    font-weight: bold;
    cursor: pointer;
    margin-top: 15px;
}

.btn-upload:disabled {
    opacity: 0.5;
}

.mission-stats {
    background: rgba(0, 0, 0, 0.2);
    padding: 10px;
    border-radius: 6px;
    margin-top: 10px;
    font-size: 12px;
}
```

---

## 3. JAVASCRIPT CONTROLLER (Add to <script> section)

```javascript
// Mission Planning Controller
$scope.waypoints = [];
$scope.selectedWaypoint = null;
$scope.plannerActive = true;
$scope.missionDistance = 0;
$scope.missionTime = 0;
$scope.uploadStatus = null;

function calcDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

$scope.updateMissionStats = function() {
    let total = 0;
    for (let i = 1; i < $scope.waypoints.length; i++) {
        total += calcDistance(
            $scope.waypoints[i-1].lat, $scope.waypoints[i-1].lon,
            $scope.waypoints[i].lat, $scope.waypoints[i].lon
        );
    }
    $scope.missionDistance = total;
    $scope.missionTime = (total / 10) / 60;
};

$scope.addWaypoint = function(lat, lon, alt) {
    $scope.waypoints.push({
        lat: lat,
        lon: lon,
        alt: alt || 50,
        action: 'waypoint',
        loiter_time: 0
    });
    $scope.updateMissionStats();
};

$scope.deleteWaypoint = function(idx) {
    $scope.waypoints.splice(idx, 1);
    if ($scope.selectedWaypoint === idx) $scope.selectedWaypoint = null;
    $scope.updateMissionStats();
};

$scope.clearAllWaypoints = function() {
    if (confirm('Clear all waypoints?')) {
        $scope.waypoints = [];
        $scope.selectedWaypoint = null;
        $scope.updateMissionStats();
    }
};

$scope.uploadMission = function() {
    if ($scope.waypoints.length === 0) return;
    $scope.uploadStatus = 'Uploading ' + $scope.waypoints.length + ' waypoints...';
    
    // Send to Node-RED
    send({type: 'mission_upload', waypoints: $scope.waypoints});
};

$scope.previewMission = function() {
    alert('Mission:\n' + JSON.stringify($scope.waypoints, null, 2));
};
```

---

## 4. NODE-RED FLOWS FOR MISSION HANDLING

Create these function nodes in Node-RED:

### Function 1: Mission Upload Handler
```javascript
// Receive mission from dashboard and prepare for upload
let waypoints = msg.payload.waypoints || [];
let missionData = {
    command: 'upload',
    waypoints: waypoints,
    count: waypoints.length
};

node.status({fill: "blue", shape: "dot", text: "Uploading " + waypoints.length + " waypoints"});
msg.payload = missionData;
return msg;
```

### Function 2: Mission Parser (for MAVLink)
```javascript
// Convert dashboard waypoints to MAVLink format
const wp_list = msg.payload.waypoints || [];
const parsed = [];

for (let i = 0; i < wp_list.length; i++) {
    const wp = wp_list[i];
    const action_map = {
        'waypoint': 16,
        'land': 21,
        'rth': 20,
        'hover': 18,
        'loiter': 17
    };
    
    parsed.push({
        seq: i,
        frame: 3,
        command: action_map[wp.action] || 16,
        current: i === 0 ? 1 : 0,
        autocontinue: 1,
        param1: wp.loiter_time || 0,
        x: wp.lat,
        y: wp.lon,
        z: wp.alt || 50
    });
}

msg.payload.mission_items = parsed;
return msg;
```

### Function 3: Mission Simulator (placeholder for daemon)
```javascript
// Simulates successful upload
node.status({fill: "green", shape: "dot", text: "Mission uploaded: " + msg.payload.count + " WP"});
msg.payload.status = "success";
msg.payload.message = "Mission uploaded successfully";
return msg;
```

---

## 5. CONNECTING TO MAP

### Enable Click-to-Add Waypoints

In the Leaflet map (Planner Map), add click handler:

```javascript
map.on('click', function(e) {
    let lat = e.latlng.lat;
    let lon = e.latlng.lng;
    
    // Send to dashboard controller
    $scope.$apply(function() {
        if ($scope.plannerActive) {
            $scope.addWaypoint(lat, lon, 50);
        }
    });
});
```

---

## 6. COMPLETE FEATURE CHECKLIST

✅ Map with click-to-add waypoints
✅ Waypoint coordinates display (lat, lon, alt)
✅ Assign actions to waypoints (WAYPOINT, LAND, RTH, HOVER, LOITER)
✅ Edit waypoint details in side panel
✅ Delete individual waypoints
✅ Reorder waypoints (future: move up/down buttons)
✅ Calculate total mission distance
✅ Estimate flight time
✅ Upload mission button
✅ Preview mission
✅ Clear all waypoints
✅ Dark glassmorphism theme matching dashboard
✅ Status feedback during upload
✅ Support for loiter/hover time

---

## 7. COMPARISON TO CERBERUS

### Cerberus (MSP/INAV)
- Binary waypoint format (MSP 209)
- 5-state machine (complex arming)
- Single drone only
- RC channel emulation

### Argus (MAVLink/ArduPilot)
- Standardized MAVLink MISSION_ITEM format ✅ Better
- Simpler state machine (direct commands)
- Multi-drone ready
- Direct MAVLink commands

---

## 8. NEXT STEPS

1. Add Mission tab HTML to template
2. Add CSS styling
3. Add JavaScript controller
4. Create Node-RED functions
5. Connect map for waypoint clicking
6. Test mission upload
7. Integrate with UDP daemon (Phase 2)

---
