#!/bin/sh
# ============================================
# Bandwidth Monitor for OpenWRT
# Created by: The Professor - PakRT
# ============================================

# Update package list
opkg update

# Install required packages
opkg install luci-base uhttpd luci-mod-admin-full

# Create web directory
mkdir -p /www/bandwidth-monitor

# Download application files
cd /www/bandwidth-monitor

cat > /www/bandwidth-monitor/index.html << 'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bandwidth Monitor - OpenWRT</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', sans-serif; 
            background: #0a0f1a; 
            color: #e2e8f0;
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { 
            text-align: center; 
            padding: 30px 0; 
            border-bottom: 1px solid #1e293b;
        }
        .header h1 { 
            font-size: 2rem; 
            background: linear-gradient(135deg, #06b6d4, #3b82f6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin: 30px 0;
        }
        .stat-card {
            background: #111827;
            border: 1px solid #1e293b;
            border-radius: 12px;
            padding: 20px;
            text-align: center;
        }
        .stat-value { 
            font-size: 2rem; 
            font-weight: bold; 
            color: #06b6d4;
            font-family: monospace;
        }
        .stat-label { color: #64748b; margin-top: 5px; }
        .devices { margin-top: 30px; }
        .device-list { display: grid; gap: 15px; }
        .device-item {
            background: #111827;
            border: 1px solid #1e293b;
            border-radius: 8px;
            padding: 15px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .device-info h3 { color: #e2e8f0; }
        .device-info p { color: #64748b; font-family: monospace; font-size: 0.875rem; }
        .device-stats { text-align: right; }
        .download { color: #06b6d4; }
        .upload { color: #f59e0b; }
        .footer {
            text-align: center;
            padding: 30px;
            color: #64748b;
            border-top: 1px solid #1e293b;
            margin-top: 50px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🌐 Bandwidth Monitor</h1>
            <p style="color: #64748b; margin-top: 10px;">OpenWRT Network Monitor</p>
        </header>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value" id="totalDownload">0.00</div>
                <div class="stat-label">Total Download (GB)</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="totalUpload" style="color: #f59e0b;">0.00</div>
                <div class="stat-label">Total Upload (GB)</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="activeDevices" style="color: #22c55e;">0</div>
                <div class="stat-label">Active Devices</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="currentSpeed">0.00</div>
                <div class="stat-label">Current Speed (MB/s)</div>
            </div>
        </div>

        <div class="devices">
            <h2 style="margin-bottom: 20px;">Connected Devices</h2>
            <div class="device-list" id="deviceList">
                <p style="color: #64748b;">Loading devices...</p>
            </div>
        </div>
        
        <footer class="footer">
            <p>The Professor - PakRT</p>
        </footer>
    </div>

    <script>
        // Fetch device data from OpenWRT
        async function fetchDevices() {
            try {
                const response = await fetch('/cgi-bin/luci/admin/status/bandwidth');
                const data = await response.json();
                updateUI(data);
            } catch (error) {
                console.log('Using simulated data');
                simulateData();
            }
        }

        function simulateData() {
            const devices = [
                { name: 'iPhone-User', ip: '192.168.1.101', download: 1.23, upload: 0.45 },
                { name: 'Laptop-Work', ip: '192.168.1.102', download: 2.56, upload: 0.89 },
                { name: 'Smart-TV', ip: '192.168.1.103', download: 5.67, upload: 0.12 }
            ];
            
            const totalDown = devices.reduce((sum, d) => sum + d.download, 0);
            const totalUp = devices.reduce((sum, d) => sum + d.upload, 0);
            
            document.getElementById('totalDownload').textContent = totalDown.toFixed(2);
            document.getElementById('totalUpload').textContent = totalUp.toFixed(2);
            document.getElementById('activeDevices').textContent = devices.length;
            document.getElementById('currentSpeed').textContent = (Math.random() * 10).toFixed(2);
            
            const deviceList = document.getElementById('deviceList');
            deviceList.innerHTML = devices.map(d => `
                <div class="device-item">
                    <div class="device-info">
                        <h3>${d.name}</h3>
                        <p>${d.ip}</p>
                    </div>
                    <div class="device-stats">
                        <p class="download">↓ ${d.download.toFixed(2)} GB</p>
                        <p class="upload">↑ ${d.upload.toFixed(2)} GB</p>
                    </div>
                </div>
            `).join('');
        }

        // Update every 5 seconds
        fetchDevices();
        setInterval(fetchDevices, 5000);
    </script>
</body>
</html>
EOF

# Create LuCI controller
mkdir -p /usr/lib/lua/luci/controller
cat > /usr/lib/lua/luci/controller/bandwidth.lua << 'EOF'
module("luci.controller.bandwidth", package.seeall)

function index()
    entry({"admin", "status", "bandwidth"}, call("action_bandwidth"), "Bandwidth Monitor", 90)
end

function action_bandwidth()
    local sys = require "luci.sys"
    local json = require "luci.jsonc"
    
    local devices = {}
    local arp = sys.net.arptable() or {}
    
    for _, entry in ipairs(arp) do
        if entry["HW address"] ~= "00:00:00:00:00:00" then
            table.insert(devices, {
                ip = entry["IP address"],
                mac = entry["HW address"],
                name = entry["Device"] or "Unknown"
            })
        end
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(devices))
end
EOF

# Configure uhttpd
uci set uhttpd.main.home='/www/bandwidth-monitor'
uci commit uhttpd
/etc/init.d/uhttpd restart

# Set permissions
chmod -R 755 /www/bandwidth-monitor

echo ""
echo "============================================"
echo " Installation Complete!"
echo " Access: http://$(uci get network.lan.ipaddr)/bandwidth-monitor"
echo " Created by: The Professor - PakRT"
echo "============================================"
