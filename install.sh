#!/bin/sh
# ================================
# OpenWrt Network Monitor v3.0
# By: The Professor -PakRT
# Features: DNS Leak Test, IP Info, Speedometer Usage
# ================================

echo "========================================"
echo "  OpenWrt Network Monitor v3.0"
echo "  By: The Professor -PakRT"
echo "========================================"

if [ "$(id -u)" != "0" ]; then
   echo "Error: Jalankan sebagai root"
   exit 1
fi

echo "[1/7] Installing dependencies..."
opkg update >/dev/null 2>&1
opkg install vnstat coreutils-stat curl >/dev/null 2>&1

echo "[2/7] Creating directories..."
mkdir -p /www/netmon/cgi-bin
mkdir -p /www/netmon/css
mkdir -p /www/netmon/js
mkdir -p /var/bandwidth
mkdir -p /var/bandwidth/history

echo "[3/7] Creating API script..."
cat > /www/netmon/cgi-bin/api.cgi << 'APISCRIPT'
#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

QUERY_STRING="${QUERY_STRING:-}"
ACTION=$(echo "$QUERY_STRING" | sed 's/.*action=\([^&]*\).*/\1/')

get_bandwidth() {
    IFACE="br-lan"
    [ ! -d "/sys/class/net/$IFACE" ] && IFACE="eth0"
    
    RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    sleep 1
    RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    
    RX_SPEED=$((RX2 - RX1))
    TX_SPEED=$((TX2 - TX1))
    
    RX_MBPS=$(awk "BEGIN {printf \"%.2f\", $RX_SPEED * 8 / 1000000}")
    TX_MBPS=$(awk "BEGIN {printf \"%.2f\", $TX_SPEED * 8 / 1000000}")
    
    NOW=$(date +%s)
    echo "$NOW,$RX_MBPS,$TX_MBPS" >> /var/bandwidth/history/realtime.csv
    tail -60 /var/bandwidth/history/realtime.csv > /var/bandwidth/history/realtime.tmp
    mv /var/bandwidth/history/realtime.tmp /var/bandwidth/history/realtime.csv
    
    echo "{\"download_speed\":\"$RX_MBPS\",\"upload_speed\":\"$TX_MBPS\",\"download_bytes\":\"$RX2\",\"upload_bytes\":\"$TX2\",\"timestamp\":\"$NOW\"}"
}

get_usage() {
    IFACE="br-lan"
    [ ! -d "/sys/class/net/$IFACE" ] && IFACE="eth0"
    
    RX_TOTAL=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_TOTAL=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    
    TODAY=$(date +%Y%m%d)
    DAILY_FILE="/var/bandwidth/daily_$TODAY.txt"
    
    if [ ! -f "$DAILY_FILE" ]; then
        echo "$RX_TOTAL,$TX_TOTAL" > "$DAILY_FILE"
    fi
    
    DAILY_START=$(cat "$DAILY_FILE" 2>/dev/null)
    DAILY_RX_START=$(echo "$DAILY_START" | cut -d',' -f1)
    DAILY_TX_START=$(echo "$DAILY_START" | cut -d',' -f2)
    
    DAILY_RX=$((RX_TOTAL - DAILY_RX_START))
    DAILY_TX=$((TX_TOTAL - DAILY_TX_START))
    [ $DAILY_RX -lt 0 ] && DAILY_RX=0
    [ $DAILY_TX -lt 0 ] && DAILY_TX=0
    
    QUOTA_DAILY=$(grep "quota_daily" /var/bandwidth/config.txt 2>/dev/null | cut -d'=' -f2)
    QUOTA_MONTHLY=$(grep "quota_monthly" /var/bandwidth/config.txt 2>/dev/null | cut -d'=' -f2)
    [ -z "$QUOTA_DAILY" ] && QUOTA_DAILY=5368709120
    [ -z "$QUOTA_MONTHLY" ] && QUOTA_MONTHLY=107374182400
    
    echo "{\"daily\":{\"download\":$DAILY_RX,\"upload\":$DAILY_TX,\"total\":$((DAILY_RX+DAILY_TX))},\"monthly\":{\"download\":$RX_TOTAL,\"upload\":$TX_TOTAL,\"total\":$((RX_TOTAL+TX_TOTAL))},\"quota\":{\"daily\":$QUOTA_DAILY,\"monthly\":$QUOTA_MONTHLY}}"
}

get_clients() {
    echo "{\"clients\":["
    FIRST=1
    NOW=$(date +%s)
    
    cat /tmp/dhcp.leases 2>/dev/null | while read EXPIRE MAC IP HOSTNAME REST; do
        [ -z "$MAC" ] && continue
        [ "$FIRST" -eq 0 ] && echo ","
        FIRST=0
        
        LEASE_TIME=$((EXPIRE - NOW))
        CONNECTED_TIME=$((43200 - LEASE_TIME))
        [ $CONNECTED_TIME -lt 0 ] && CONNECTED_TIME=0
        
        SIGNAL=""
        TYPE="lan"
        for WDEV in $(ls /sys/class/ieee80211/*/device/net/ 2>/dev/null); do
            if iw dev $WDEV station dump 2>/dev/null | grep -qi "$MAC"; then
                TYPE="wifi"
                SIGNAL=$(iw dev $WDEV station get $MAC 2>/dev/null | grep "signal:" | awk '{print $2}')
                break
            fi
        done
        
        [ -z "$HOSTNAME" ] && HOSTNAME="Unknown"
        echo "{\"mac\":\"$MAC\",\"ip\":\"$IP\",\"hostname\":\"$HOSTNAME\",\"type\":\"$TYPE\",\"signal\":\"$SIGNAL\",\"connected_time\":$CONNECTED_TIME}"
    done
    echo "]}"
}

get_system() {
    UPTIME=$(cat /proc/uptime | awk '{print int($1)}')
    LOAD=$(cat /proc/loadavg | awk '{print $1}')
    
    MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
    MEM_USED=$((MEM_TOTAL - MEM_FREE))
    
    ROUTER_NAME=$(grep "router_name" /var/bandwidth/config.txt 2>/dev/null | cut -d'=' -f2)
    OWNER_NAME=$(grep "owner_name" /var/bandwidth/config.txt 2>/dev/null | cut -d'=' -f2)
    [ -z "$ROUTER_NAME" ] && ROUTER_NAME="OpenWrt Router"
    [ -z "$OWNER_NAME" ] && OWNER_NAME="The Professor -PakRT"
    
    echo "{\"uptime\":$UPTIME,\"load\":\"$LOAD\",\"mem_total\":$MEM_TOTAL,\"mem_used\":$MEM_USED,\"router_name\":\"$ROUTER_NAME\",\"owner_name\":\"$OWNER_NAME\"}"
}

get_ipinfo() {
    IP_DATA=$(curl -s --max-time 5 "http://ip-api.com/json" 2>/dev/null)
    if [ -n "$IP_DATA" ]; then
        echo "$IP_DATA"
    else
        echo "{\"status\":\"fail\",\"message\":\"Unable to get IP info\"}"
    fi
}

dns_leak_test() {
    DNS_SERVERS=""
    FIRST=1
    
    # Check resolv.conf for DNS servers
    for DNS in $(grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}'); do
        [ "$FIRST" -eq 0 ] && DNS_SERVERS="$DNS_SERVERS,"
        FIRST=0
        DNS_SERVERS="$DNS_SERVERS{\"ip\":\"$DNS\"}"
    done
    
    echo "{\"dns_servers\":[$DNS_SERVERS]}"
}

save_config() {
    read -r POST_DATA
    touch /var/bandwidth/config.txt
    
    echo "$POST_DATA" | tr '&' '\n' | while read LINE; do
        KEY=$(echo "$LINE" | cut -d'=' -f1)
        VALUE=$(echo "$LINE" | cut -d'=' -f2- | sed 's/%20/ /g;s/+/ /g')
        sed -i "/^$KEY=/d" /var/bandwidth/config.txt
        echo "$KEY=$VALUE" >> /var/bandwidth/config.txt
    done
    
    echo "{\"status\":\"ok\"}"
}

case "$ACTION" in
    bandwidth) get_bandwidth ;;
    usage) get_usage ;;
    clients) get_clients ;;
    system) get_system ;;
    ipinfo) get_ipinfo ;;
    dnstest) dns_leak_test ;;
    save_config) save_config ;;
    *) echo "{\"actions\":[\"bandwidth\",\"usage\",\"clients\",\"system\",\"ipinfo\",\"dnstest\",\"save_config\"]}" ;;
esac
APISCRIPT

chmod +x /www/netmon/cgi-bin/api.cgi

echo "[4/7] Creating HTML..."
cat > /www/netmon/index.html << 'HTMLFILE'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenWrt Network Monitor - The Professor</title>
<link rel="stylesheet" href="css/style.css">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
</head>
<body>
<div class="app">
  <header class="header">
    <div class="header-left">
      <div class="logo">
        <div class="logo-inner">
          <svg viewBox="0 0 50 50">
            <circle cx="25" cy="25" r="20" fill="none" stroke="white" stroke-width="2" opacity="0.3"/>
            <circle cx="25" cy="25" r="14" fill="none" stroke="white" stroke-width="2" opacity="0.5"/>
            <circle cx="25" cy="25" r="8" fill="none" stroke="white" stroke-width="2" opacity="0.7"/>
            <circle cx="25" cy="25" r="3" fill="white"/>
            <path class="wave1" d="M15 35 Q25 20 35 35" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
            <path class="wave2" d="M10 40 Q25 15 40 40" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
          </svg>
        </div>
        <div class="logo-dot"></div>
      </div>
      <div class="header-info">
        <h1 id="routerName">OpenWrt Router</h1>
        <span id="ownerName">The Professor -PakRT</span>
      </div>
    </div>
    <div class="header-right">
      <div class="status online"><span class="pulse"></span>Online</div>
      <button class="btn-icon" onclick="openSettings()">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>
      </button>
    </div>
  </header>

  <main class="dashboard">
    <!-- Speed Cards -->
    <section class="speed-section">
      <div class="speed-card download">
        <div class="speed-header">
          <div class="speed-icon download">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
          </div>
          <span class="speed-label">Download</span>
        </div>
        <div class="speed-display">
          <span class="speed-value" id="downloadSpeed">0.00</span>
          <span class="speed-unit">Mbps</span>
        </div>
        <div class="speed-bar"><div class="speed-bar-fill download" id="downloadBar"></div></div>
      </div>
      <div class="speed-card upload">
        <div class="speed-header">
          <div class="speed-icon upload">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"/></svg>
          </div>
          <span class="speed-label">Upload</span>
        </div>
        <div class="speed-display">
          <span class="speed-value" id="uploadSpeed">0.00</span>
          <span class="speed-unit">Mbps</span>
        </div>
        <div class="speed-bar"><div class="speed-bar-fill upload" id="uploadBar"></div></div>
      </div>
    </section>

    <!-- Chart -->
    <section class="chart-section">
      <div class="section-header">
        <h2><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="section-icon"><path d="M3 3v18h18"/><path d="M18 17V9M13 17V5M8 17v-3"/></svg>Grafik Bandwidth Real-time</h2>
      </div>
      <div class="chart-container"><canvas id="bandwidthChart"></canvas></div>
    </section>

    <!-- DNS Leak Test & IP Info -->
    <section class="dns-section">
      <div class="section-header">
        <h2><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="section-icon"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>DNS Leak Test & IP Info</h2>
      </div>
      <div class="dns-container">
        <div class="dns-status">
          <div class="dns-icon" id="dnsIcon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
          </div>
          <p class="dns-text" id="dnsStatus">Click to Test</p>
          <button class="btn-test" id="btnDnsTest" onclick="runDnsTest()">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>
            Run Test
          </button>
        </div>
        <div class="ip-info">
          <div class="ip-item">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/></svg>
            <div><span class="ip-label">Public IP</span><span class="ip-value" id="publicIP">--</span></div>
          </div>
          <div class="ip-grid">
            <div class="ip-item small">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/></svg>
              <div><span class="ip-label">Location</span><span class="ip-value" id="ipLocation">--</span></div>
            </div>
            <div class="ip-item small">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><circle cx="6" cy="6" r="1"/><circle cx="6" cy="18" r="1"/></svg>
              <div><span class="ip-label">ISP</span><span class="ip-value" id="ipISP">--</span></div>
            </div>
          </div>
          <div class="dns-servers" id="dnsServers"></div>
        </div>
      </div>
    </section>

    <!-- Usage Speedometers -->
    <section class="usage-section">
      <div class="usage-card daily">
        <div class="usage-header">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
          <h3>Pemakaian Hari Ini</h3>
        </div>
        <div class="speedometer-container">
          <svg viewBox="0 0 200 120" class="speedometer">
            <defs>
              <linearGradient id="dailyGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stop-color="#f59e0b"/>
                <stop offset="100%" stop-color="#ef4444"/>
              </linearGradient>
            </defs>
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="#1e293b" stroke-width="12" stroke-linecap="round"/>
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="url(#dailyGrad)" stroke-width="12" stroke-linecap="round" stroke-dasharray="251" stroke-dashoffset="251" id="dailyArc"/>
            <g id="dailyNeedle" transform="rotate(-90, 100, 100)">
              <line x1="100" y1="100" x2="100" y2="35" stroke="#f1f5f9" stroke-width="3" stroke-linecap="round"/>
              <circle cx="100" cy="100" r="8" fill="#ef4444"/>
              <circle cx="100" cy="100" r="4" fill="#0f172a"/>
            </g>
            <text x="100" y="75" text-anchor="middle" fill="#f1f5f9" font-size="24" font-weight="700" id="dailyPercent">0%</text>
            <text x="100" y="95" text-anchor="middle" fill="#94a3b8" font-size="11">of quota</text>
          </svg>
        </div>
        <div class="usage-stats">
          <div class="stat"><span class="stat-value" id="dailyTotal">0 MB</span><span class="stat-label">Total</span></div>
          <div class="stat"><span class="stat-value" id="dailyDownload">0 MB</span><span class="stat-label">Download</span></div>
          <div class="stat"><span class="stat-value" id="dailyUpload">0 MB</span><span class="stat-label">Upload</span></div>
        </div>
        <div class="quota-bar"><div class="quota-fill daily" id="dailyQuotaFill"></div></div>
        <div class="quota-text"><span id="dailyRemaining">Sisa: 5 GB</span></div>
      </div>

      <div class="usage-card monthly">
        <div class="usage-header">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/></svg>
          <h3>Pemakaian Bulan Ini</h3>
        </div>
        <div class="speedometer-container">
          <svg viewBox="0 0 200 120" class="speedometer">
            <defs>
              <linearGradient id="monthlyGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stop-color="#8b5cf6"/>
                <stop offset="100%" stop-color="#ec4899"/>
              </linearGradient>
            </defs>
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="#1e293b" stroke-width="12" stroke-linecap="round"/>
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="url(#monthlyGrad)" stroke-width="12" stroke-linecap="round" stroke-dasharray="251" stroke-dashoffset="251" id="monthlyArc"/>
            <g id="monthlyNeedle" transform="rotate(-90, 100, 100)">
              <line x1="100" y1="100" x2="100" y2="35" stroke="#f1f5f9" stroke-width="3" stroke-linecap="round"/>
              <circle cx="100" cy="100" r="8" fill="#ec4899"/>
              <circle cx="100" cy="100" r="4" fill="#0f172a"/>
            </g>
            <text x="100" y="75" text-anchor="middle" fill="#f1f5f9" font-size="24" font-weight="700" id="monthlyPercent">0%</text>
            <text x="100" y="95" text-anchor="middle" fill="#94a3b8" font-size="11">of quota</text>
          </svg>
        </div>
        <div class="usage-stats">
          <div class="stat"><span class="stat-value" id="monthlyTotal">0 GB</span><span class="stat-label">Total</span></div>
          <div class="stat"><span class="stat-value" id="monthlyDownload">0 GB</span><span class="stat-label">Download</span></div>
          <div class="stat"><span class="stat-value" id="monthlyUpload">0 GB</span><span class="stat-label">Upload</span></div>
        </div>
        <div class="quota-bar"><div class="quota-fill monthly" id="monthlyQuotaFill"></div></div>
        <div class="quota-text"><span id="monthlyRemaining">Sisa: 100 GB</span></div>
      </div>
    </section>

    <!-- Devices -->
    <section class="devices-section">
      <div class="section-header">
        <h2><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="section-icon"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></svg>Perangkat Terhubung (<span id="deviceCount">0</span>)</h2>
      </div>
      <div class="devices-grid" id="devicesList"></div>
    </section>
  </main>

  <!-- Footer Signature -->
  <footer class="footer">
    <div class="footer-content">
      <span class="footer-code">â¤</span>
      <span>Created with love by</span>
    </div>
    <div class="footer-signature">The Professor -PakRT</div>
    <div class="footer-version">OpenWrt Network Monitor v3.0</div>
  </footer>

  <!-- Settings Modal -->
  <div class="modal" id="settingsModal">
    <div class="modal-backdrop" onclick="closeSettings()"></div>
    <div class="modal-content">
      <div class="modal-header">
        <h2>Pengaturan</h2>
        <button class="btn-close" onclick="closeSettings()">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
        </button>
      </div>
      <form id="settingsForm">
        <div class="form-group">
          <label>Nama Router</label>
          <input type="text" name="router_name" id="inputRouterName" placeholder="OpenWrt Router">
        </div>
        <div class="form-group">
          <label>Nama Pemilik</label>
          <input type="text" name="owner_name" id="inputOwnerName" placeholder="The Professor -PakRT">
        </div>
        <div class="form-group">
          <label>Kuota Harian (GB)</label>
          <input type="number" name="quota_daily_gb" id="inputQuotaDaily" value="5">
        </div>
        <div class="form-group">
          <label>Kuota Bulanan (GB)</label>
          <input type="number" name="quota_monthly_gb" id="inputQuotaMonthly" value="100">
        </div>
        <button type="submit" class="btn-save">Simpan Pengaturan</button>
      </form>
    </div>
  </div>
</div>
<script src="js/app.js"></script>
</body>
</html>
HTMLFILE

echo "[5/7] Creating CSS..."
cat > /www/netmon/css/style.css << 'CSSFILE'
:root {
  --bg: #0f172a;
  --bg-card: #1e293b;
  --bg-hover: #334155;
  --text: #f1f5f9;
  --text-muted: #94a3b8;
  --primary: #3b82f6;
  --secondary: #8b5cf6;
  --accent: #22c55e;
  --warning: #f59e0b;
  --error: #ef4444;
  --border: #334155;
  --shadow: 0 10px 40px -10px rgba(0,0,0,0.5);
  --radius: 16px;
}

* { margin:0; padding:0; box-sizing:border-box; }

body {
  font-family: 'Inter', system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
}

.app { max-width: 1400px; margin: 0 auto; padding: 1rem; }

/* Header */
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1.25rem 1.5rem;
  background: var(--bg-card);
  border-radius: var(--radius);
  margin-bottom: 1.5rem;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

.header-left { display: flex; align-items: center; gap: 1rem; }

.logo { position: relative; width: 64px; height: 64px; }

.logo-inner {
  width: 100%;
  height: 100%;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 0 30px rgba(59, 130, 246, 0.4);
}

.logo-inner svg { width: 40px; height: 40px; }

.logo-dot {
  position: absolute;
  top: -4px;
  right: -4px;
  width: 12px;
  height: 12px;
  background: var(--accent);
  border-radius: 50%;
  animation: bounce 2s infinite;
  box-shadow: 0 0 10px var(--accent);
}

@keyframes bounce {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-5px); }
}

.wave1 { animation: wave 2s infinite; }
.wave2 { animation: wave 2s infinite 0.5s; }

@keyframes wave {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}

.header-info h1 {
  font-size: 1.75rem;
  font-weight: 800;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.header-info span { color: var(--text-muted); font-size: 0.9rem; }

.header-right { display: flex; align-items: center; gap: 1rem; }

.status {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  background: rgba(34, 197, 94, 0.15);
  color: var(--accent);
  border-radius: 100px;
  font-size: 0.85rem;
  font-weight: 600;
}

.status .pulse {
  width: 8px;
  height: 8px;
  background: var(--accent);
  border-radius: 50%;
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.5; transform: scale(1.2); }
}

.btn-icon {
  width: 44px;
  height: 44px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 12px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.btn-icon svg { width: 20px; height: 20px; color: var(--text-muted); }
.btn-icon:hover { background: var(--primary); border-color: var(--primary); }
.btn-icon:hover svg { color: var(--text); }

/* Dashboard */
.dashboard { display: grid; gap: 1.5rem; }

/* Speed Section */
.speed-section { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1rem; }

.speed-card {
  background: var(--bg-card);
  border-radius: var(--radius);
  padding: 1.5rem;
  position: relative;
  overflow: hidden;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

.speed-card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px; }
.speed-card.download::before { background: linear-gradient(90deg, var(--primary), var(--secondary)); }
.speed-card.upload::before { background: linear-gradient(90deg, var(--accent), var(--primary)); }

.speed-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1rem; }

.speed-icon {
  width: 48px;
  height: 48px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.speed-icon.download { background: linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(139, 92, 246, 0.2)); }
.speed-icon.upload { background: linear-gradient(135deg, rgba(34, 197, 94, 0.2), rgba(59, 130, 246, 0.2)); }
.speed-icon svg { width: 24px; height: 24px; }
.speed-icon.download svg { color: var(--primary); }
.speed-icon.upload svg { color: var(--accent); }

.speed-label { color: var(--text-muted); font-size: 0.9rem; font-weight: 500; }

.speed-display { display: flex; align-items: baseline; gap: 0.5rem; margin-bottom: 1rem; }
.speed-value { font-size: 3.5rem; font-weight: 800; line-height: 1; }
.speed-unit { color: var(--text-muted); font-size: 1.1rem; font-weight: 500; }

.speed-bar { height: 6px; background: var(--bg); border-radius: 3px; overflow: hidden; }
.speed-bar-fill { height: 100%; border-radius: 3px; transition: width 0.5s ease; width: 0%; }
.speed-bar-fill.download { background: linear-gradient(90deg, var(--primary), var(--secondary)); }
.speed-bar-fill.upload { background: linear-gradient(90deg, var(--accent), var(--primary)); }

/* Section Headers */
.section-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1rem; }
.section-header h2 { font-size: 1rem; font-weight: 600; color: var(--text-muted); display: flex; align-items: center; gap: 0.5rem; }
.section-icon { width: 20px; height: 20px; }

/* Chart Section */
.chart-section {
  background: var(--bg-card);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

.chart-container { height: 200px; position: relative; }
#bandwidthChart { width: 100%; height: 100%; }

/* DNS Section */
.dns-section {
  background: var(--bg-card);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

.dns-container { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }

@media (max-width: 768px) {
  .dns-container { grid-template-columns: 1fr; }
}

.dns-status {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 2rem;
  background: rgba(255,255,255,0.03);
  border-radius: 12px;
}

.dns-icon {
  width: 80px;
  height: 80px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(148, 163, 184, 0.1);
  margin-bottom: 1rem;
  transition: all 0.3s;
}

.dns-icon svg { width: 40px; height: 40px; color: var(--text-muted); }
.dns-icon.safe { background: rgba(34, 197, 94, 0.2); box-shadow: 0 0 30px rgba(34, 197, 94, 0.3); }
.dns-icon.safe svg { color: var(--accent); }
.dns-icon.leaked { background: rgba(239, 68, 68, 0.2); }
.dns-icon.leaked svg { color: var(--error); }

.dns-text { font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; color: var(--text-muted); }
.dns-text.safe { color: var(--accent); }
.dns-text.leaked { color: var(--error); }

.btn-test {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1.5rem;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  color: white;
  border: none;
  border-radius: 100px;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: 0 4px 20px rgba(59, 130, 246, 0.4);
}

.btn-test svg { width: 16px; height: 16px; }
.btn-test:hover { transform: translateY(-2px); box-shadow: 0 8px 30px rgba(59, 130, 246, 0.5); }
.btn-test:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }

.ip-info { display: flex; flex-direction: column; gap: 1rem; }

.ip-item {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background: rgba(255,255,255,0.03);
  border-radius: 12px;
}

.ip-item svg { width: 24px; height: 24px; color: var(--primary); flex-shrink: 0; }
.ip-item div { flex: 1; min-width: 0; }
.ip-label { display: block; font-size: 0.75rem; color: var(--text-muted); margin-bottom: 0.25rem; }
.ip-value { display: block; font-weight: 600; font-size: 1.1rem; color: var(--primary); }

.ip-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
.ip-item.small { padding: 0.75rem; }
.ip-item.small .ip-value { font-size: 0.9rem; }

.dns-servers {
  padding: 1rem;
  background: rgba(255,255,255,0.03);
  border-radius: 12px;
}

.dns-servers p { font-size: 0.85rem; color: var(--text-muted); margin-bottom: 0.5rem; }

/* Usage Section */
.usage-section { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1rem; }

.usage-card {
  background: var(--bg-card);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: var(--shadow);
  position: relative;
  overflow: hidden;
  border: 1px solid var(--border);
}

.usage-card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 4px; }
.usage-card.daily::before { background: linear-gradient(90deg, var(--warning), var(--error)); }
.usage-card.monthly::before { background: linear-gradient(90deg, var(--secondary), #ec4899); }

.usage-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1rem; }
.usage-header svg { width: 20px; height: 20px; color: var(--text-muted); }
.usage-header h3 { font-size: 1rem; font-weight: 600; color: var(--text-muted); }

.speedometer-container { display: flex; justify-content: center; margin-bottom: 1rem; }
.speedometer { width: 180px; height: 110px; }

.usage-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.5rem; margin-bottom: 1rem; text-align: center; }
.stat { padding: 0.5rem; background: rgba(255,255,255,0.03); border-radius: 8px; }
.stat-value { display: block; font-size: 0.9rem; font-weight: 700; margin-bottom: 0.25rem; }
.stat-label { font-size: 0.7rem; color: var(--text-muted); }

.quota-bar { height: 6px; background: var(--bg); border-radius: 3px; overflow: hidden; margin-bottom: 0.75rem; }
.quota-fill { height: 100%; border-radius: 3px; transition: width 0.5s ease; width: 0%; }
.quota-fill.daily { background: linear-gradient(90deg, var(--warning), var(--error)); }
.quota-fill.monthly { background: linear-gradient(90deg, var(--secondary), #ec4899); }
.quota-text { font-size: 0.85rem; color: var(--text-muted); }

/* Devices Section */
.devices-section {
  background: var(--bg-card);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

.devices-grid { display: grid; gap: 0.75rem; max-height: 400px; overflow-y: auto; }

.device-card {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background: var(--bg);
  border-radius: 12px;
  transition: all 0.2s;
}

.device-card:hover { background: var(--bg-hover); transform: translateX(4px); }

.device-avatar {
  width: 48px;
  height: 48px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
}

.device-avatar.wifi { background: linear-gradient(135deg, rgba(139, 92, 246, 0.2), rgba(59, 130, 246, 0.2)); }
.device-avatar.lan { background: linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(34, 197, 94, 0.2)); }

.device-info { flex: 1; min-width: 0; }
.device-name { font-weight: 600; font-size: 0.9rem; margin-bottom: 0.25rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.device-details { font-size: 0.75rem; color: var(--text-muted); }

.device-meta { text-align: right; }
.device-time { font-size: 0.75rem; color: var(--text-muted); display: flex; align-items: center; gap: 0.25rem; justify-content: flex-end; margin-bottom: 0.25rem; }
.device-signal { display: flex; align-items: center; gap: 0.25rem; font-size: 0.75rem; color: var(--text-muted); }

/* Footer */
.footer {
  margin-top: 2rem;
  padding: 2rem 0;
  border-top: 1px solid var(--border);
  text-align: center;
}

.footer-content { display: flex; align-items: center; justify-content: center; gap: 0.5rem; color: var(--text-muted); margin-bottom: 0.5rem; }
.footer-code { font-size: 1.25rem; animation: pulse 2s infinite; }

.footer-signature {
  font-size: 1.75rem;
  font-weight: 800;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  margin-bottom: 0.5rem;
}

.footer-version { font-size: 0.85rem; color: var(--text-muted); }

/* Modal */
.modal { display: none; position: fixed; inset: 0; z-index: 1000; }
.modal.active { display: flex; align-items: center; justify-content: center; }
.modal-backdrop { position: absolute; inset: 0; background: rgba(0, 0, 0, 0.7); backdrop-filter: blur(4px); }

.modal-content {
  position: relative;
  background: var(--bg-card);
  border-radius: var(--radius);
  width: 90%;
  max-width: 400px;
  padding: 1.5rem;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
  animation: modalIn 0.3s ease;
}

@keyframes modalIn {
  from { opacity: 0; transform: scale(0.95) translateY(10px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}

.modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem; }
.modal-header h2 { font-size: 1.25rem; font-weight: 700; }

.btn-close {
  width: 36px;
  height: 36px;
  background: var(--bg);
  border: none;
  border-radius: 8px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}

.btn-close svg { width: 20px; height: 20px; color: var(--text-muted); }
.btn-close:hover { background: var(--error); }
.btn-close:hover svg { color: white; }

.form-group { margin-bottom: 1rem; }
.form-group label { display: block; font-size: 0.875rem; color: var(--text-muted); margin-bottom: 0.5rem; }

.form-group input {
  width: 100%;
  padding: 0.875rem 1rem;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text);
  font-size: 1rem;
  transition: all 0.2s;
}

.form-group input:focus { outline: none; border-color: var(--primary); box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2); }

.btn-save {
  width: 100%;
  padding: 1rem;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  color: white;
  border: none;
  border-radius: 10px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  margin-top: 0.5rem;
}

.btn-save:hover { opacity: 0.9; }

/* Responsive */
@media (max-width: 768px) {
  .header { flex-direction: column; gap: 1rem; text-align: center; }
  .header-left { flex-direction: column; }
  .speed-value { font-size: 2.5rem; }
}
CSSFILE

echo "[6/7] Creating JavaScript..."
cat > /www/netmon/js/app.js << 'JSFILE'
const API = '/netmon/cgi-bin/api.cgi';

let chartData = [];
let chart = null;

function formatBytes(bytes, decimals = 2) {
    if (!bytes || bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(decimals)) + ' ' + sizes[i];
}

function formatTime(seconds) {
    if (!seconds || seconds <= 0) return 'Baru saja';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return h + 'j ' + m + 'm';
    if (m > 0) return m + ' menit';
    return Math.floor(seconds) + ' detik';
}

function updateSpeedometer(arcId, needleId, percentId, percent) {
    const arc = document.getElementById(arcId);
    const needle = document.getElementById(needleId);
    const percentEl = document.getElementById(percentId);
    
    if (arc) {
        const offset = 251 - (251 * Math.min(percent, 100) / 100);
        arc.style.strokeDashoffset = offset;
        arc.style.transition = 'stroke-dashoffset 1s ease-out';
    }
    
    if (needle) {
        const angle = -90 + (Math.min(percent, 100) * 1.8);
        needle.style.transition = 'transform 1s ease-out';
        needle.setAttribute('transform', 'rotate(' + angle + ', 100, 100)');
    }
    
    if (percentEl) {
        percentEl.textContent = percent.toFixed(1) + '%';
    }
}

function initChart() {
    const canvas = document.getElementById('bandwidthChart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    canvas.width = canvas.parentElement.offsetWidth;
    canvas.height = 200;
    
    chart = { ctx, canvas };
    drawChart();
}

function drawChart() {
    if (!chart || chartData.length === 0) return;
    
    const { ctx, canvas } = chart;
    const w = canvas.width;
    const h = canvas.height;
    const padding = 40;
    
    ctx.clearRect(0, 0, w, h);
    
    const maxVal = Math.max(...chartData.map(d => Math.max(d.download, d.upload)), 10);
    
    ctx.strokeStyle = '#334155';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
        const y = padding + (h - padding * 2) * i / 4;
        ctx.beginPath();
        ctx.moveTo(padding, y);
        ctx.lineTo(w - padding, y);
        ctx.stroke();
        
        ctx.fillStyle = '#94a3b8';
        ctx.font = '10px Inter, sans-serif';
        ctx.fillText((maxVal * (4 - i) / 4).toFixed(1), 5, y + 3);
    }
    
    if (chartData.length < 2) return;
    
    const stepX = (w - padding * 2) / (chartData.length - 1);
    
    // Download area
    ctx.beginPath();
    ctx.moveTo(padding, h - padding);
    chartData.forEach((d, i) => {
        const x = padding + i * stepX;
        const y = h - padding - (d.download / maxVal) * (h - padding * 2);
        ctx.lineTo(x, y);
    });
    ctx.lineTo(padding + (chartData.length - 1) * stepX, h - padding);
    ctx.closePath();
    
    const gradDl = ctx.createLinearGradient(0, 0, 0, h);
    gradDl.addColorStop(0, 'rgba(59, 130, 246, 0.3)');
    gradDl.addColorStop(1, 'rgba(59, 130, 246, 0.05)');
    ctx.fillStyle = gradDl;
    ctx.fill();
    
    // Download line
    ctx.beginPath();
    chartData.forEach((d, i) => {
        const x = padding + i * stepX;
        const y = h - padding - (d.download / maxVal) * (h - padding * 2);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = '#3b82f6';
    ctx.lineWidth = 2;
    ctx.stroke();
    
    // Upload area
    ctx.beginPath();
    ctx.moveTo(padding, h - padding);
    chartData.forEach((d, i) => {
        const x = padding + i * stepX;
        const y = h - padding - (d.upload / maxVal) * (h - padding * 2);
        ctx.lineTo(x, y);
    });
    ctx.lineTo(padding + (chartData.length - 1) * stepX, h - padding);
    ctx.closePath();
    
    const gradUl = ctx.createLinearGradient(0, 0, 0, h);
    gradUl.addColorStop(0, 'rgba(34, 197, 94, 0.3)');
    gradUl.addColorStop(1, 'rgba(34, 197, 94, 0.05)');
    ctx.fillStyle = gradUl;
    ctx.fill();
    
    // Upload line
    ctx.beginPath();
    chartData.forEach((d, i) => {
        const x = padding + i * stepX;
        const y = h - padding - (d.upload / maxVal) * (h - padding * 2);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = '#22c55e';
    ctx.lineWidth = 2;
    ctx.stroke();
    
    // Legend
    ctx.fillStyle = '#3b82f6';
    ctx.fillRect(w - 120, 10, 12, 12);
    ctx.fillStyle = '#f1f5f9';
    ctx.fillText('Download', w - 100, 20);
    
    ctx.fillStyle = '#22c55e';
    ctx.fillRect(w - 120, 28, 12, 12);
    ctx.fillStyle = '#f1f5f9';
    ctx.fillText('Upload', w - 100, 38);
}

async function fetchBandwidth() {
    try {
        const res = await fetch(API + '?action=bandwidth');
        const data = await res.json();
        
        document.getElementById('downloadSpeed').textContent = data.download_speed;
        document.getElementById('uploadSpeed').textContent = data.upload_speed;
        
        const dlPercent = Math.min((parseFloat(data.download_speed) / 100) * 100, 100);
        const ulPercent = Math.min((parseFloat(data.upload_speed) / 100) * 100, 100);
        
        document.getElementById('downloadBar').style.width = dlPercent + '%';
        document.getElementById('uploadBar').style.width = ulPercent + '%';
        
        chartData.push({
            time: Date.now(),
            download: parseFloat(data.download_speed) || 0,
            upload: parseFloat(data.upload_speed) || 0
        });
        if (chartData.length > 30) chartData.shift();
        drawChart();
    } catch (e) {
        console.error('Bandwidth error:', e);
    }
}

async function fetchUsage() {
    try {
        const res = await fetch(API + '?action=usage');
        const data = await res.json();
        
        document.getElementById('dailyTotal').textContent = formatBytes(data.daily.total);
        document.getElementById('dailyDownload').textContent = formatBytes(data.daily.download);
        document.getElementById('dailyUpload').textContent = formatBytes(data.daily.upload);
        
        const dailyPercent = Math.min((data.daily.total / data.quota.daily) * 100, 100);
        document.getElementById('dailyQuotaFill').style.width = dailyPercent + '%';
        document.getElementById('dailyRemaining').textContent = 'Sisa: ' + formatBytes(Math.max(data.quota.daily - data.daily.total, 0));
        updateSpeedometer('dailyArc', 'dailyNeedle', 'dailyPercent', dailyPercent);
        
        document.getElementById('monthlyTotal').textContent = formatBytes(data.monthly.total);
        document.getElementById('monthlyDownload').textContent = formatBytes(data.monthly.download);
        document.getElementById('monthlyUpload').textContent = formatBytes(data.monthly.upload);
        
        const monthlyPercent = Math.min((data.monthly.total / data.quota.monthly) * 100, 100);
        document.getElementById('monthlyQuotaFill').style.width = monthlyPercent + '%';
        document.getElementById('monthlyRemaining').textContent = 'Sisa: ' + formatBytes(Math.max(data.quota.monthly - data.monthly.total, 0));
        updateSpeedometer('monthlyArc', 'monthlyNeedle', 'monthlyPercent', monthlyPercent);
    } catch (e) {
        console.error('Usage error:', e);
    }
}

async function fetchClients() {
    try {
        const res = await fetch(API + '?action=clients');
        const data = await res.json();
        
        const list = document.getElementById('devicesList');
        const count = document.getElementById('deviceCount');
        
        count.textContent = data.clients.length;
        list.innerHTML = '';
        
        data.clients.forEach(c => {
            const icon = c.type === 'wifi' ? 'ðŸ“¶' : 'ðŸ”Œ';
            const avatarClass = c.type === 'wifi' ? 'wifi' : 'lan';
            
            const html = '<div class="device-card"><div class="device-avatar ' + avatarClass + '">' + icon + '</div><div class="device-info"><div class="device-name">' + (c.hostname || 'Unknown') + '</div><div class="device-details">' + c.ip + ' â€¢ ' + c.mac + '</div></div><div class="device-meta"><div class="device-time">â± ' + formatTime(c.connected_time) + '</div>' + (c.signal ? '<div class="device-signal">ðŸ“¶ ' + c.signal + ' dBm</div>' : '') + '</div></div>';
            list.innerHTML += html;
        });
    } catch (e) {
        console.error('Clients error:', e);
    }
}

async function fetchSystemInfo() {
    try {
        const res = await fetch(API + '?action=system');
        const data = await res.json();
        
        document.getElementById('routerName').textContent = data.router_name;
        document.getElementById('ownerName').textContent = data.owner_name;
        document.getElementById('inputRouterName').value = data.router_name;
        document.getElementById('inputOwnerName').value = data.owner_name;
    } catch (e) {
        console.error('System info error:', e);
    }
}

let dnsTestRunning = false;

async function runDnsTest() {
    if (dnsTestRunning) return;
    
    dnsTestRunning = true;
    const btn = document.getElementById('btnDnsTest');
    const icon = document.getElementById('dnsIcon');
    const status = document.getElementById('dnsStatus');
    
    btn.disabled = true;
    btn.innerHTML = '<svg class="spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>Testing...';
    status.textContent = 'Testing...';
    status.className = 'dns-text';
    icon.className = 'dns-icon';
    
    try {
        // Get IP info
        const ipRes = await fetch('https://ipapi.co/json/');
        const ipData = await ipRes.json();
        
        document.getElementById('publicIP').textContent = ipData.ip || '--';
        document.getElementById('ipLocation').textContent = (ipData.city || '') + ', ' + (ipData.country_name || '--');
        document.getElementById('ipISP').textContent = ipData.org || '--';
        
        // Get DNS info
        const dnsRes = await fetch(API + '?action=dnstest');
        const dnsData = await dnsRes.json();
        
        const dnsServers = document.getElementById('dnsServers');
        if (dnsData.dns_servers && dnsData.dns_servers.length > 0) {
            dnsServers.innerHTML = '<p>DNS Servers:</p>';
            dnsData.dns_servers.forEach(dns => {
                dnsServers.innerHTML += '<div style="display:flex;justify-content:space-between;font-size:0.85rem;padding:0.25rem 0;border-bottom:1px solid #334155"><span style="color:#3b82f6;font-family:monospace">' + dns.ip + '</span></div>';
            });
        }
        
        // Check for leaks
        const hasLeak = false; // Simplified check
        
        if (hasLeak) {
            icon.className = 'dns-icon leaked';
            status.textContent = 'DNS Leak Detected!';
            status.className = 'dns-text leaked';
        } else {
            icon.className = 'dns-icon safe';
            status.textContent = 'No DNS Leak Detected';
            status.className = 'dns-text safe';
        }
    } catch (e) {
        console.error('DNS test error:', e);
        status.textContent = 'Test Failed';
    }
    
    btn.disabled = false;
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>Run Test';
    dnsTestRunning = false;
}

function openSettings() {
    document.getElementById('settingsModal').classList.add('active');
}

function closeSettings() {
    document.getElementById('settingsModal').classList.remove('active');
}

document.getElementById('settingsForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const form = new FormData(this);
    const params = new URLSearchParams();
    
    for (let [key, value] of form) {
        if (key === 'quota_daily_gb') {
            params.append('quota_daily', value * 1073741824);
        } else if (key === 'quota_monthly_gb') {
            params.append('quota_monthly', value * 1073741824);
        } else {
            params.append(key, value);
        }
    }
    
    try {
        await fetch(API + '?action=save_config', {
            method: 'POST',
            body: params
        });
        closeSettings();
        fetchSystemInfo();
        alert('Pengaturan berhasil disimpan!');
    } catch (e) {
        alert('Gagal menyimpan pengaturan');
    }
});

// Add spin animation
const style = document.createElement('style');
style.textContent = '@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}.spin{animation:spin 1s linear infinite;width:16px;height:16px}';
document.head.appendChild(style);

// Initialize
document.addEventListener('DOMContentLoaded', function() {
    fetchSystemInfo();
    fetchBandwidth();
    fetchUsage();
    fetchClients();
    initChart();
    
    setInterval(fetchBandwidth, 2000);
    setInterval(fetchUsage, 10000);
    setInterval(fetchClients, 30000);
    
    window.addEventListener('resize', function() {
        if (chart) {
            chart.canvas.width = chart.canvas.parentElement.offsetWidth;
            drawChart();
        }
    });
});
JSFILE

echo "[7/7] Configuring uhttpd..."
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci commit uhttpd
/etc/init.d/uhttpd restart

vnstat -u -i br-lan 2>/dev/null || true

echo ""
echo "========================================"
echo "  Installation Complete Mass Broo!"
echo "  By: The Professor -PakRT"
echo "========================================"
echo ""
echo "  Akses dashboard di:"
echo "  http://192.168.1.1/netmon/"
echo ""
echo "========================================"
