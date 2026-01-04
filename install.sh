#!/bin/sh
echo "Content-type: text/html"
echo ""
# Buat folder dan file CGI
mkdir -p /www/check && cat > /www/check/index.cgi << 'EOFCGI'

# Get system info
HOSTNAME=$(uci get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname)
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"

# Get traffic data
get_traffic() {
    grep "$IFACE:" /proc/net/dev | awk '{print $2, $10}'
}
TRAFFIC=$(get_traffic)
RX_BYTES=$(echo $TRAFFIC | awk '{print $1}')
TX_BYTES=$(echo $TRAFFIC | awk '{print $2}')

# Get connected devices
DEVICES=$(cat /tmp/dhcp.leases 2>/dev/null)

cat << EOFHTML
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$HOSTNAME - Bandwidth Monitor</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --cyber-bg: #0a0a0f;
            --cyber-card: #12121a;
            --cyber-primary: #00fff5;
            --cyber-secondary: #ff00ff;
            --cyber-accent: #ffff00;
            --cyber-text: #e0e0e0;
            --cyber-glow: 0 0 20px rgba(0, 255, 245, 0.5);
        }
        body {
            font-family: 'Courier New', monospace;
            background: var(--cyber-bg);
            color: var(--cyber-text);
            min-height: 100vh;
            background-image: 
                linear-gradient(rgba(0, 255, 245, 0.03) 1px, transparent 1px),
                linear-gradient(90deg, rgba(0, 255, 245, 0.03) 1px, transparent 1px);
            background-size: 50px 50px;
        }
        header {
            background: linear-gradient(135deg, var(--cyber-card), #1a1a2e);
            padding: 20px;
            border-bottom: 2px solid var(--cyber-primary);
            box-shadow: var(--cyber-glow);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .logo-container { display: flex; align-items: center; gap: 15px; }
        .logo { width: 50px; height: 50px; filter: drop-shadow(0 0 10px var(--cyber-primary)); }
        h1 {
            font-size: 1.8rem;
            background: linear-gradient(90deg, var(--cyber-primary), var(--cyber-secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            text-shadow: 0 0 30px rgba(0, 255, 245, 0.3);
        }
        .hostname {
            color: var(--cyber-accent);
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 20px; }
        .card {
            background: var(--cyber-card);
            border: 1px solid rgba(0, 255, 245, 0.2);
            border-radius: 10px;
            padding: 20px;
            position: relative;
            overflow: hidden;
        }
        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--cyber-primary), var(--cyber-secondary));
        }
        .card-title {
            color: var(--cyber-primary);
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 2px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .card-title::before { content: '◈'; color: var(--cyber-secondary); }
        .speedometer-container {
            display: flex;
            justify-content: center;
            gap: 40px;
            flex-wrap: wrap;
        }
        .speedometer {
            position: relative;
            width: 200px;
            height: 120px;
        }
        .speed-label {
            text-align: center;
            margin-top: 10px;
            font-size: 0.8rem;
            color: var(--cyber-text);
        }
        .speed-value {
            font-size: 1.5rem;
            font-weight: bold;
            color: var(--cyber-primary);
            text-shadow: 0 0 10px var(--cyber-primary);
        }
        .quota-item { margin-bottom: 15px; }
        .quota-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-size: 0.85rem;
        }
        .quota-bar {
            height: 8px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 4px;
            overflow: hidden;
        }
        .quota-fill {
            height: 100%;
            border-radius: 4px;
            transition: width 0.5s ease;
        }
        .quota-daily .quota-fill { background: linear-gradient(90deg, #00ff88, #00fff5); }
        .quota-weekly .quota-fill { background: linear-gradient(90deg, #ff00ff, #ff6b6b); }
        .quota-monthly .quota-fill { background: linear-gradient(90deg, #ffff00, #ff8800); }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.8rem;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid rgba(0, 255, 245, 0.1);
        }
        th {
            color: var(--cyber-primary);
            text-transform: uppercase;
            font-size: 0.75rem;
            letter-spacing: 1px;
        }
        tr:hover { background: rgba(0, 255, 245, 0.05); }
        .status-online {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #00ff88;
            border-radius: 50%;
            box-shadow: 0 0 10px #00ff88;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .info-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; }
        .info-item {
            background: rgba(0, 0, 0, 0.3);
            padding: 15px;
            border-radius: 8px;
            border-left: 3px solid var(--cyber-primary);
        }
        .info-label { font-size: 0.7rem; color: #888; text-transform: uppercase; }
        .info-value { font-size: 1rem; color: var(--cyber-primary); margin-top: 5px; word-break: break-all; }
        footer {
            text-align: center;
            padding: 20px;
            border-top: 1px solid rgba(0, 255, 245, 0.2);
            margin-top: 30px;
        }
        .footer-text {
            font-size: 1.2rem;
            background: linear-gradient(90deg, var(--cyber-secondary), var(--cyber-primary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            letter-spacing: 5px;
            font-weight: bold;
        }
        .chart-container { height: 200px; margin-top: 15px; }
        .btn {
            background: linear-gradient(135deg, var(--cyber-primary), var(--cyber-secondary));
            border: none;
            padding: 10px 20px;
            color: #000;
            font-weight: bold;
            border-radius: 5px;
            cursor: pointer;
            font-family: inherit;
            text-transform: uppercase;
            letter-spacing: 1px;
            transition: all 0.3s;
        }
        .btn:hover {
            box-shadow: 0 0 20px var(--cyber-primary);
            transform: translateY(-2px);
        }
        .input-group { margin-bottom: 10px; }
        .input-group label { display: block; font-size: 0.75rem; margin-bottom: 5px; color: #888; }
        .input-group input {
            width: 100%;
            padding: 8px;
            background: rgba(0, 0, 0, 0.5);
            border: 1px solid rgba(0, 255, 245, 0.3);
            border-radius: 4px;
            color: var(--cyber-text);
            font-family: inherit;
        }
        .input-group input:focus { outline: none; border-color: var(--cyber-primary); box-shadow: 0 0 10px rgba(0, 255, 245, 0.3); }
    </style>
</head>
<body>
    <header>
        <div class="logo-container">
            <svg class="logo" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="50" cy="50" r="45" stroke="var(--cyber-primary)" stroke-width="3"/>
                <path d="M30 50 L50 30 L70 50 L50 70 Z" fill="var(--cyber-primary)" opacity="0.8"/>
                <circle cx="50" cy="50" r="15" fill="var(--cyber-secondary)"/>
            </svg>
            <div>
                <h1>BANDWIDTH MONITOR</h1>
                <div class="hostname">◈ $HOSTNAME</div>
            </div>
        </div>
        <div style="color: var(--cyber-accent); font-size: 0.8rem;">
            <span id="datetime"></span>
        </div>
    </header>

    <div class="container">
        <div class="grid">
            <div class="card" style="grid-column: span 2;">
                <div class="card-title">Real-Time Speed</div>
                <div class="speedometer-container">
                    <div>
                        <div class="speedometer">
                            <canvas id="downloadGauge"></canvas>
                        </div>
                        <div class="speed-label">DOWNLOAD<br><span class="speed-value" id="dlSpeed">0 KB/s</span></div>
                    </div>
                    <div>
                        <div class="speedometer">
                            <canvas id="uploadGauge"></canvas>
                        </div>
                        <div class="speed-label">UPLOAD<br><span class="speed-value" id="ulSpeed">0 KB/s</span></div>
                    </div>
                </div>
            </div>

            <div class="card">
                <div class="card-title">Quota Management</div>
                <div class="quota-item quota-daily">
                    <div class="quota-header">
                        <span>Daily</span>
                        <span id="quotaDaily">0%</span>
                    </div>
                    <div class="quota-bar"><div class="quota-fill" id="quotaDailyBar" style="width: 0%"></div></div>
                </div>
                <div class="quota-item quota-weekly">
                    <div class="quota-header">
                        <span>Weekly</span>
                        <span id="quotaWeekly">0%</span>
                    </div>
                    <div class="quota-bar"><div class="quota-fill" id="quotaWeeklyBar" style="width: 0%"></div></div>
                </div>
                <div class="quota-item quota-monthly">
                    <div class="quota-header">
                        <span>Monthly</span>
                        <span id="quotaMonthly">0%</span>
                    </div>
                    <div class="quota-bar"><div class="quota-fill" id="quotaMonthlyBar" style="width: 0%"></div></div>
                </div>
                <div style="margin-top: 15px;">
                    <div class="input-group">
                        <label>Daily Limit (GB)</label>
                        <input type="number" id="limitDaily" value="5" min="0" step="0.5">
                    </div>
                    <div class="input-group">
                        <label>Weekly Limit (GB)</label>
                        <input type="number" id="limitWeekly" value="30" min="0" step="1">
                    </div>
                    <div class="input-group">
                        <label>Monthly Limit (GB)</label>
                        <input type="number" id="limitMonthly" value="100" min="0" step="5">
                    </div>
                    <button class="btn" onclick="saveQuotaSettings()">Save Limits</button>
                </div>
            </div>

            <div class="card">
                <div class="card-title">Network Info</div>
                <div class="info-grid">
                    <div class="info-item">
                        <div class="info-label">Public IP</div>
                        <div class="info-value" id="publicIP">Loading...</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">ISP</div>
                        <div class="info-value" id="isp">Loading...</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Location</div>
                        <div class="info-value" id="location">Loading...</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">DNS Server</div>
                        <div class="info-value" id="dnsServer">Loading...</div>
                    </div>
                </div>
                <div style="margin-top: 15px;">
                    <button class="btn" onclick="runDnsLeakTest()">DNS Leak Test</button>
                    <div id="dnsLeakResult" style="margin-top: 10px; font-size: 0.8rem;"></div>
                </div>
            </div>
        </div>

        <div class="card">
            <div class="card-title">Traffic History</div>
            <div class="chart-container">
                <canvas id="trafficChart"></canvas>
            </div>
        </div>

        <div class="card" style="margin-top: 20px;">
            <div class="card-title">Connected Devices</div>
            <table>
                <thead>
                    <tr>
                        <th>Status</th>
                        <th>Hostname</th>
                        <th>IP Address</th>
                        <th>MAC Address</th>
                        <th>Lease Time</th>
                        <th>Data Used</th>
                    </tr>
                </thead>
                <tbody id="deviceTable">
                    <!-- Filled by JS -->
                </tbody>
            </table>
        </div>
    </div>

    <footer>
        <div class="footer-text">YUZINCRABZ</div>
        <div style="margin-top: 10px; font-size: 0.7rem; color: #666;">OpenWrt Bandwidth Monitor v1.0</div>
    </footer>

    <script>
        // Initialize data from server
        let lastRx = $RX_BYTES;
        let lastTx = $TX_BYTES;
        let totalRxSession = 0;
        let totalTxSession = 0;
        const iface = "$IFACE";

        // Traffic history
        const trafficHistory = { labels: [], download: [], upload: [] };
        const maxHistoryPoints = 30;

        // Initialize Chart
        const trafficCtx = document.getElementById('trafficChart').getContext('2d');
        const trafficChart = new Chart(trafficCtx, {
            type: 'line',
            data: {
                labels: trafficHistory.labels,
                datasets: [{
                    label: 'Download (KB/s)',
                    data: trafficHistory.download,
                    borderColor: '#00fff5',
                    backgroundColor: 'rgba(0, 255, 245, 0.1)',
                    fill: true,
                    tension: 0.4
                }, {
                    label: 'Upload (KB/s)',
                    data: trafficHistory.upload,
                    borderColor: '#ff00ff',
                    backgroundColor: 'rgba(255, 0, 255, 0.1)',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#888' } },
                    y: { grid: { color: 'rgba(255,255,255,0.05)' }, ticks: { color: '#888' } }
                },
                plugins: { legend: { labels: { color: '#e0e0e0' } } }
            }
        });

        // Speedometer drawing
        function drawGauge(canvasId, value, maxValue, color) {
            const canvas = document.getElementById(canvasId);
            const ctx = canvas.getContext('2d');
            canvas.width = 200;
            canvas.height = 120;

            const centerX = 100;
            const centerY = 100;
            const radius = 80;

            ctx.clearRect(0, 0, canvas.width, canvas.height);

            // Background arc
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius, Math.PI, 0, false);
            ctx.strokeStyle = 'rgba(255,255,255,0.1)';
            ctx.lineWidth = 15;
            ctx.stroke();

            // Tick marks
            for (let i = 0; i <= 10; i++) {
                const angle = Math.PI + (Math.PI * i / 10);
                const innerR = radius - 25;
                const outerR = radius - 15;
                const x1 = centerX + Math.cos(angle) * innerR;
                const y1 = centerY + Math.sin(angle) * innerR;
                const x2 = centerX + Math.cos(angle) * outerR;
                const y2 = centerY + Math.sin(angle) * outerR;

                ctx.beginPath();
                ctx.moveTo(x1, y1);
                ctx.lineTo(x2, y2);
                ctx.strokeStyle = color;
                ctx.lineWidth = 2;
                ctx.stroke();

                // Labels
                const labelR = radius - 35;
                const lx = centerX + Math.cos(angle) * labelR;
                const ly = centerY + Math.sin(angle) * labelR;
                ctx.fillStyle = '#888';
                ctx.font = '10px Courier New';
                ctx.textAlign = 'center';
                ctx.fillText((maxValue * i / 10).toFixed(0), lx, ly);
            }

            // Value arc
            const valueAngle = Math.PI + (Math.PI * Math.min(value, maxValue) / maxValue);
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius, Math.PI, valueAngle, false);
            const gradient = ctx.createLinearGradient(0, 0, 200, 0);
            gradient.addColorStop(0, color);
            gradient.addColorStop(1, color === '#00fff5' ? '#00ff88' : '#ff6b6b');
            ctx.strokeStyle = gradient;
            ctx.lineWidth = 15;
            ctx.lineCap = 'round';
            ctx.stroke();

            // Needle
            const needleAngle = Math.PI + (Math.PI * Math.min(value, maxValue) / maxValue);
            const needleLength = radius - 10;
            const needleX = centerX + Math.cos(needleAngle) * needleLength;
            const needleY = centerY + Math.sin(needleAngle) * needleLength;

            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(needleX, needleY);
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 3;
            ctx.lineCap = 'round';
            ctx.shadowColor = color;
            ctx.shadowBlur = 10;
            ctx.stroke();
            ctx.shadowBlur = 0;

            // Center circle
            ctx.beginPath();
            ctx.arc(centerX, centerY, 8, 0, Math.PI * 2);
            ctx.fillStyle = color;
            ctx.fill();
        }

        // Format bytes
        function formatBytes(bytes) {
            if (bytes < 1024) return bytes.toFixed(1) + ' B';
            if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
            if (bytes < 1073741824) return (bytes / 1048576).toFixed(2) + ' MB';
            return (bytes / 1073741824).toFixed(2) + ' GB';
        }

        function formatSpeed(bytesPerSec) {
            if (bytesPerSec < 1024) return bytesPerSec.toFixed(0) + ' B/s';
            if (bytesPerSec < 1048576) return (bytesPerSec / 1024).toFixed(1) + ' KB/s';
            return (bytesPerSec / 1048576).toFixed(2) + ' MB/s';
        }

        // Fetch traffic data
        async function fetchTrafficData() {
            try {
                const response = await fetch('/cgi-bin/traffic.cgi?iface=' + iface);
                const data = await response.json();
                
                const rxDiff = data.rx - lastRx;
                const txDiff = data.tx - lastTx;
                
                if (rxDiff >= 0 && txDiff >= 0) {
                    totalRxSession += rxDiff;
                    totalTxSession += txDiff;
                    
                    const dlSpeed = rxDiff / 2;
                    const ulSpeed = txDiff / 2;
                    
                    document.getElementById('dlSpeed').textContent = formatSpeed(dlSpeed);
                    document.getElementById('ulSpeed').textContent = formatSpeed(ulSpeed);
                    
                    drawGauge('downloadGauge', dlSpeed / 1024, 1000, '#00fff5');
                    drawGauge('uploadGauge', ulSpeed / 1024, 500, '#ff00ff');
                    
                    // Update history
                    const now = new Date();
                    trafficHistory.labels.push(now.toLocaleTimeString());
                    trafficHistory.download.push((dlSpeed / 1024).toFixed(2));
                    trafficHistory.upload.push((ulSpeed / 1024).toFixed(2));
                    
                    if (trafficHistory.labels.length > maxHistoryPoints) {
                        trafficHistory.labels.shift();
                        trafficHistory.download.shift();
                        trafficHistory.upload.shift();
                    }
                    
                    trafficChart.update();
                    updateQuotaDisplay();
                }
                
                lastRx = data.rx;
                lastTx = data.tx;
            } catch (e) {
                console.error('Traffic fetch error:', e);
            }
        }

        // Quota management
        function saveQuotaSettings() {
            localStorage.setItem('quotaDaily', document.getElementById('limitDaily').value);
            localStorage.setItem('quotaWeekly', document.getElementById('limitWeekly').value);
            localStorage.setItem('quotaMonthly', document.getElementById('limitMonthly').value);
            alert('Quota limits saved!');
        }

        function loadQuotaSettings() {
            const daily = localStorage.getItem('quotaDaily') || 5;
            const weekly = localStorage.getItem('quotaWeekly') || 30;
            const monthly = localStorage.getItem('quotaMonthly') || 100;
            document.getElementById('limitDaily').value = daily;
            document.getElementById('limitWeekly').value = weekly;
            document.getElementById('limitMonthly').value = monthly;
        }

        function updateQuotaDisplay() {
            const totalBytes = totalRxSession + totalTxSession;
            const totalGB = totalBytes / 1073741824;
            
            const dailyLimit = parseFloat(document.getElementById('limitDaily').value);
            const weeklyLimit = parseFloat(document.getElementById('limitWeekly').value);
            const monthlyLimit = parseFloat(document.getElementById('limitMonthly').value);
            
            const dailyPercent = Math.min(100, (totalGB / dailyLimit) * 100);
            const weeklyPercent = Math.min(100, (totalGB / weeklyLimit) * 100);
            const monthlyPercent = Math.min(100, (totalGB / monthlyLimit) * 100);
            
            document.getElementById('quotaDaily').textContent = dailyPercent.toFixed(1) + '%';
            document.getElementById('quotaDailyBar').style.width = dailyPercent + '%';
            document.getElementById('quotaWeekly').textContent = weeklyPercent.toFixed(1) + '%';
            document.getElementById('quotaWeeklyBar').style.width = weeklyPercent + '%';
            document.getElementById('quotaMonthly').textContent = monthlyPercent.toFixed(1) + '%';
            document.getElementById('quotaMonthlyBar').style.width = monthlyPercent + '%';
        }

        // Fetch network info
        async function fetchNetworkInfo() {
            try {
                const response = await fetch('https://ipapi.co/json/');
                const data = await response.json();
                document.getElementById('publicIP').textContent = data.ip;
                document.getElementById('isp').textContent = data.org;
                document.getElementById('location').textContent = data.city + ', ' + data.country_name;
            } catch (e) {
                document.getElementById('publicIP').textContent = 'Error';
            }
        }

        // DNS Leak Test
        async function runDnsLeakTest() {
            const resultDiv = document.getElementById('dnsLeakResult');
            resultDiv.innerHTML = '<span style="color: var(--cyber-accent);">Testing DNS...</span>';
            try {
                const response = await fetch('https://1.1.1.1/cdn-cgi/trace');
                const text = await response.text();
                const lines = text.split('\\n');
                let result = '<div style="color: var(--cyber-primary);">DNS Test Results:</div>';
                lines.forEach(line => {
                    if (line.includes('=')) {
                        result += '<div>' + line + '</div>';
                    }
                });
                resultDiv.innerHTML = result;
                document.getElementById('dnsServer').textContent = '1.1.1.1 (Cloudflare)';
            } catch (e) {
                resultDiv.innerHTML = '<span style="color: #ff6b6b;">DNS test failed</span>';
            }
        }

        // Load devices
        async function loadDevices() {
            try {
                const response = await fetch('/cgi-bin/devices.cgi');
                const devices = await response.json();
                const tbody = document.getElementById('deviceTable');
                tbody.innerHTML = '';
                
                devices.forEach(device => {
                    const row = document.createElement('tr');
                    row.innerHTML = \`
                        <td><span class="status-online"></span></td>
                        <td>\${device.hostname || 'Unknown'}</td>
                        <td>\${device.ip}</td>
                        <td>\${device.mac}</td>
                        <td>\${device.lease}</td>
                        <td>\${formatBytes(device.bytes || 0)}</td>
                    \`;
                    tbody.appendChild(row);
                });
            } catch (e) {
                console.error('Devices fetch error:', e);
            }
        }

        // Update datetime
        function updateDateTime() {
            const now = new Date();
            document.getElementById('datetime').textContent = now.toLocaleString('id-ID');
        }

        // Initialize
        drawGauge('downloadGauge', 0, 1000, '#00fff5');
        drawGauge('uploadGauge', 0, 500, '#ff00ff');
        loadQuotaSettings();
        fetchNetworkInfo();
        loadDevices();
        updateDateTime();

        setInterval(fetchTrafficData, 2000);
        setInterval(loadDevices, 10000);
        setInterval(updateDateTime, 1000);
    </script>
</body>
</html>
EOFHTML
EOFCGI

# Create traffic API endpoint
cat > /www/cgi-bin/traffic.cgi << 'EOFTRAFFIC'
#!/bin/sh
echo "Content-type: application/json"
echo ""
IFACE=$(echo "$QUERY_STRING" | sed -n 's/.*iface=\([^&]*\).*/\1/p')
[ -z "$IFACE" ] && IFACE="eth0"
DATA=$(grep "$IFACE:" /proc/net/dev | awk '{print $2, $10}')
RX=$(echo $DATA | awk '{print $1}')
TX=$(echo $DATA | awk '{print $2}')
echo "{\"rx\":$RX,\"tx\":$TX}"
EOFTRAFFIC

# Create devices API endpoint
cat > /www/cgi-bin/devices.cgi << 'EOFDEVICES'
#!/bin/sh
echo "Content-type: application/json"
echo ""
echo "["
FIRST=1
while read LEASE MAC IP HOST CLIENT; do
    [ "$FIRST" = "1" ] || echo ","
    FIRST=0
    BYTES=$(iptables -L FORWARD -v -n 2>/dev/null | grep "$IP" | awk '{s+=$2} END {print s+0}')
    echo "{\"lease\":\"$LEASE\",\"mac\":\"$MAC\",\"ip\":\"$IP\",\"hostname\":\"$HOST\",\"bytes\":$BYTES}"
done < /tmp/dhcp.leases
echo "]"
EOFDEVICES

# Set permissions
chmod +x /www/check/index.cgi
chmod +x /www/cgi-bin/traffic.cgi
chmod +x /www/cgi-bin/devices.cgi

# Configure uhttpd for CGI
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci set uhttpd.main.interpreter='.cgi=/bin/sh'
uci commit uhttpd
/etc/init.d/uhttpd restart

echo "✓ Dashboard installed! Access at http://192.168.1.1/check/"
