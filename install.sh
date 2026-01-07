#!/bin/sh
#============================================================
# OpenWRT Bandwidth Monitor - One-Click Installer
# Author: Network Engineer Assistant
# Compatible: OpenWRT 19.07+ / 21.02+ / 22.03+ / 23.05+
#============================================================

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     OpenWRT Bandwidth Monitor - Installation Script        ║"
echo "║                    v2.0 Professional                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Deteksi interface WAN otomatis
WAN_IFACE=$(uci get network.wan.device 2>/dev/null || uci get network.wan.ifname 2>/dev/null || echo "eth0")
LAN_IFACE=$(uci get network.lan.device 2>/dev/null || uci get network.lan.ifname 2>/dev/null || echo "br-lan")

echo "[*] Detected WAN Interface: $WAN_IFACE"
echo "[*] Detected LAN Interface: $LAN_IFACE"
echo ""

#------------------------------------------------------------
# STEP 1: Buat Direktori
#------------------------------------------------------------
echo "[1/7] Creating directories..."
mkdir -p /www/bandwidth
mkdir -p /www/cgi-bin
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/view/bandwidth
chmod 755 /www/bandwidth
chmod 755 /www/cgi-bin

#------------------------------------------------------------
# STEP 2: Buat CGI API Backend
#------------------------------------------------------------
echo "[2/7] Creating CGI API Backend..."

cat > /www/cgi-bin/bandwidth-api.sh << 'APIEOF'
#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Cache-Control: no-cache"
echo ""

# Deteksi interface
WAN_IFACE=$(uci get network.wan.device 2>/dev/null || uci get network.wan.ifname 2>/dev/null || echo "eth0")
LAN_IFACE=$(uci get network.lan.device 2>/dev/null || uci get network.lan.ifname 2>/dev/null || echo "br-lan")

ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')

case "$ACTION" in
    bandwidth)
        # Baca data dari /proc/net/dev
        if [ -f /proc/net/dev ]; then
            WAN_DATA=$(grep "$WAN_IFACE" /proc/net/dev 2>/dev/null | tr -s ' ')
            LAN_DATA=$(grep "$LAN_IFACE" /proc/net/dev 2>/dev/null | tr -s ' ')
            
            WAN_RX=$(echo "$WAN_DATA" | awk -F'[: ]+' '{print $3}')
            WAN_TX=$(echo "$WAN_DATA" | awk -F'[: ]+' '{print $11}')
            LAN_RX=$(echo "$LAN_DATA" | awk -F'[: ]+' '{print $3}')
            LAN_TX=$(echo "$LAN_DATA" | awk -F'[: ]+' '{print $11}')
            
            WAN_RX=${WAN_RX:-0}
            WAN_TX=${WAN_TX:-0}
            LAN_RX=${LAN_RX:-0}
            LAN_TX=${LAN_TX:-0}
        fi
        
        # CPU & Memory
        CPU_LOAD=$(cat /proc/loadavg | awk '{print $1}')
        MEM_INFO=$(free 2>/dev/null || cat /proc/meminfo)
        MEM_TOTAL=$(echo "$MEM_INFO" | grep -i "MemTotal" | awk '{print $2}')
        MEM_FREE=$(echo "$MEM_INFO" | grep -i "MemFree" | awk '{print $2}')
        MEM_TOTAL=${MEM_TOTAL:-1}
        MEM_FREE=${MEM_FREE:-0}
        MEM_USED=$((MEM_TOTAL - MEM_FREE))
        MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
        
        cat << EOF
{
    "wan_rx": $WAN_RX,
    "wan_tx": $WAN_TX,
    "lan_rx": $LAN_RX,
    "lan_tx": $LAN_TX,
    "cpu_load": "$CPU_LOAD",
    "mem_percent": $MEM_PERCENT,
    "mem_used": $MEM_USED,
    "mem_total": $MEM_TOTAL,
    "wan_iface": "$WAN_IFACE",
    "lan_iface": "$LAN_IFACE",
    "timestamp": $(date +%s)
}
EOF
        ;;
        
    devices)
        echo "{"
        echo '"devices": ['
        FIRST=1
        
        # Dari DHCP Leases
        if [ -f /tmp/dhcp.leases ]; then
            while read -r EXPIRE MAC IP HOSTNAME CLIENTID; do
                [ -z "$MAC" ] && continue
                HOSTNAME=${HOSTNAME:-"Unknown"}
                [ "$FIRST" = "0" ] && echo ","
                FIRST=0
                
                # Cek status online via ARP
                STATUS="offline"
                if grep -q "$MAC" /proc/net/arp 2>/dev/null; then
                    STATUS="online"
                fi
                
                cat << EOF
    {
        "mac": "$MAC",
        "ip": "$IP",
        "hostname": "$HOSTNAME",
        "status": "$STATUS",
        "expire": "$EXPIRE"
    }
EOF
            done < /tmp/dhcp.leases
        fi
        
        # Tambah dari ARP table untuk device static
        if [ -f /proc/net/arp ]; then
            while read -r IP TYPE FLAGS MAC MASK IFACE; do
                [ "$IP" = "IP" ] && continue
                [ "$MAC" = "00:00:00:00:00:00" ] && continue
                
                # Skip jika sudah ada di DHCP
                if [ -f /tmp/dhcp.leases ] && grep -qi "$MAC" /tmp/dhcp.leases 2>/dev/null; then
                    continue
                fi
                
                [ "$FIRST" = "0" ] && echo ","
                FIRST=0
                
                cat << EOF
    {
        "mac": "$MAC",
        "ip": "$IP",
        "hostname": "Static/Unknown",
        "status": "online",
        "expire": "static"
    }
EOF
            done < /proc/net/arp
        fi
        
        echo ""
        echo "],"
        
        # Count devices
        TOTAL=$(cat /tmp/dhcp.leases 2>/dev/null | wc -l)
        ONLINE=$(grep -c "0x2" /proc/net/arp 2>/dev/null || echo "0")
        
        echo '"total": '$TOTAL','
        echo '"online": '$ONLINE
        echo "}"
        ;;
        
    system)
        # Uptime
        UPTIME_SEC=$(cat /proc/uptime | awk '{print int($1)}')
        UPTIME_DAYS=$((UPTIME_SEC / 86400))
        UPTIME_HOURS=$(((UPTIME_SEC % 86400) / 3600))
        UPTIME_MINS=$(((UPTIME_SEC % 3600) / 60))
        
        # Model & Firmware
        MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || uname -m)
        FIRMWARE=$(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d"'" -f2)
        KERNEL=$(uname -r)
        HOSTNAME=$(uname -n)
        
        # WAN IP
        WAN_IP=$(ip addr show $WAN_IFACE 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
        WAN_IP=${WAN_IP:-"Not Connected"}
        
        # LAN IP
        LAN_IP=$(ip addr show $LAN_IFACE 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
        LAN_IP=${LAN_IP:-"192.168.1.1"}
        
        # DNS Servers
        DNS=$(cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | grep nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        DNS=${DNS:-$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')}
        
        cat << EOF
{
    "hostname": "$HOSTNAME",
    "model": "$MODEL",
    "firmware": "$FIRMWARE",
    "kernel": "$KERNEL",
    "uptime_sec": $UPTIME_SEC,
    "uptime_formatted": "${UPTIME_DAYS}d ${UPTIME_HOURS}h ${UPTIME_MINS}m",
    "wan_ip": "$WAN_IP",
    "lan_ip": "$LAN_IP",
    "dns_servers": "$DNS",
    "wan_iface": "$WAN_IFACE",
    "lan_iface": "$LAN_IFACE"
}
EOF
        ;;
        
    interfaces)
        echo '{"interfaces": ['
        FIRST=1
        
        for IFACE in $(ls /sys/class/net/); do
            [ "$FIRST" = "0" ] && echo ","
            FIRST=0
            
            MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null || echo "00:00:00:00:00:00")
            STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo "unknown")
            MTU=$(cat /sys/class/net/$IFACE/mtu 2>/dev/null || echo "1500")
            SPEED=$(cat /sys/class/net/$IFACE/speed 2>/dev/null || echo "-1")
            
            RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo "0")
            TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo "0")
            
            cat << EOF
    {
        "name": "$IFACE",
        "mac": "$MAC",
        "state": "$STATE",
        "mtu": $MTU,
        "speed": $SPEED,
        "rx_bytes": $RX,
        "tx_bytes": $TX
    }
EOF
        done
        
        echo "]}"
        ;;
        
    *)
        echo '{"error": "Invalid action", "valid_actions": ["bandwidth", "devices", "system", "interfaces"]}'
        ;;
esac
APIEOF

chmod 755 /www/cgi-bin/bandwidth-api.sh

#------------------------------------------------------------
# STEP 3: Buat Dashboard HTML
#------------------------------------------------------------
echo "[3/7] Creating Dashboard HTML..."

cat > /www/bandwidth/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bandwidth Monitor | OpenWRT</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <link href__="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        * { font-family: 'Inter', sans-serif; }
        
        :root {
            --bg-primary: #0a0a0f;
            --bg-secondary: #12121a;
            --bg-card: rgba(20, 20, 35, 0.7);
            --accent-cyan: #00d4ff;
            --accent-magenta: #ff006e;
            --accent-purple: #8b5cf6;
            --accent-green: #10b981;
            --text-primary: #ffffff;
            --text-secondary: #94a3b8;
        }
        
        body {
            background: var(--bg-primary);
            background-image: 
                radial-gradient(ellipse at 20% 20%, rgba(139, 92, 246, 0.15) 0%, transparent 50%),
                radial-gradient(ellipse at 80% 80%, rgba(0, 212, 255, 0.1) 0%, transparent 50%),
                radial-gradient(ellipse at 50% 50%, rgba(255, 0, 110, 0.05) 0%, transparent 70%);
            min-height: 100vh;
        }
        
        .glass-card {
            background: var(--bg-card);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.08);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        
        .glass-card:hover {
            border-color: rgba(255, 255, 255, 0.15);
            box-shadow: 0 8px 40px rgba(0, 212, 255, 0.1);
        }
        
        .neon-text-cyan { 
            color: var(--accent-cyan);
            text-shadow: 0 0 20px rgba(0, 212, 255, 0.5);
        }
        
        .neon-text-magenta { 
            color: var(--accent-magenta);
            text-shadow: 0 0 20px rgba(255, 0, 110, 0.5);
        }
        
        .neon-text-green { 
            color: var(--accent-green);
            text-shadow: 0 0 20px rgba(16, 185, 129, 0.5);
        }
        
        .gauge-container {
            position: relative;
            width: 200px;
            height: 120px;
            margin: 0 auto;
        }
        
        .gauge-bg {
            fill: none;
            stroke: rgba(255, 255, 255, 0.1);
            stroke-width: 20;
        }
        
        .gauge-fill {
            fill: none;
            stroke-width: 20;
            stroke-linecap: round;
            transition: stroke-dashoffset 0.5s ease-out, stroke 0.3s ease;
            filter: drop-shadow(0 0 8px currentColor);
        }
        
        .gauge-download { stroke: var(--accent-cyan); }
        .gauge-upload { stroke: var(--accent-magenta); }
        
        .stat-value {
            font-size: 2rem;
            font-weight: 700;
            line-height: 1;
        }
        
        .pulse-dot {
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(1.1); }
        }
        
        .device-online { border-left: 3px solid var(--accent-green); }
        .device-offline { border-left: 3px solid #ef4444; }
        
        .scrollbar-thin::-webkit-scrollbar { width: 6px; }
        .scrollbar-thin::-webkit-scrollbar-track { background: rgba(255,255,255,0.05); border-radius: 3px; }
        .scrollbar-thin::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.2); border-radius: 3px; }
        .scrollbar-thin::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.3); }
        
        .fade-in { animation: fadeIn 0.5s ease-out; }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .loading-skeleton {
            background: linear-gradient(90deg, rgba(255,255,255,0.05) 25%, rgba(255,255,255,0.1) 50%, rgba(255,255,255,0.05) 75%);
            background-size: 200% 100%;
            animation: shimmer 1.5s infinite;
        }
        
        @keyframes shimmer {
            0% { background-position: 200% 0; }
            100% { background-position: -200% 0; }
        }
    </style>
</head>
<body class="text-white p-4 md:p-6">
    <!-- Header -->
    <header class="mb-6 fade-in">
        <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div>
                <h1 class="text-2xl md:text-3xl font-bold flex items-center gap-3">
                    <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-500 to-purple-600 flex items-center justify-center">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                        </svg>
                    </div>
                    <span>Bandwidth Monitor</span>
                </h1>
                <p class="text-slate-400 mt-1 text-sm md:text-base">Real-time Network Statistics</p>
            </div>
            <div class="flex items-center gap-4">
                <div id="connection-status" class="flex items-center gap-2 px-4 py-2 rounded-full glass-card">
                    <div class="w-2 h-2 rounded-full bg-green-500 pulse-dot"></div>
                    <span class="text-sm text-slate-300">Connected</span>
                </div>
                <div class="text-right">
                    <div class="text-xs text-slate-500">Last Update</div>
                    <div id="last-update" class="text-sm font-medium">--:--:--</div>
                </div>
            </div>
        </div>
    </header>

    <!-- Speed Gauges -->
    <section class="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6 mb-6">
        <!-- Download Gauge -->
        <div class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.1s">
            <div class="flex items-center justify-between mb-4">
                <h3 class="text-slate-400 font-medium flex items-center gap-2">
                    <svg class="w-5 h-5 text-cyan-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3"/>
                    </svg>
                    Download Speed
                </h3>
                <span class="text-xs px-2 py-1 rounded-full bg-cyan-500/20 text-cyan-400">LIVE</span>
            </div>
            <div class="gauge-container mb-4">
                <svg viewBox="0 0 200 120" class="w-full h-full">
                    <path class="gauge-bg" d="M 20 100 A 80 80 0 0 1 180 100"/>
                    <path id="gauge-download" class="gauge-fill gauge-download" d="M 20 100 A 80 80 0 0 1 180 100" 
                          stroke-dasharray="251" stroke-dashoffset="251"/>
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-end pb-2">
                    <span id="download-speed" class="stat-value neon-text-cyan">0.00</span>
                    <span class="text-slate-400 text-sm">Mbps</span>
                </div>
            </div>
            <div class="grid grid-cols-2 gap-4 text-center">
                <div class="p-3 rounded-xl bg-white/5">
                    <div class="text-xs text-slate-500 mb-1">Total Downloaded</div>
                    <div id="total-download" class="text-lg font-semibold text-cyan-400">0 GB</div>
                </div>
                <div class="p-3 rounded-xl bg-white/5">
                    <div class="text-xs text-slate-500 mb-1">Peak Speed</div>
                    <div id="peak-download" class="text-lg font-semibold text-cyan-400">0 Mbps</div>
                </div>
            </div>
        </div>

        <!-- Upload Gauge -->
        <div class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.2s">
            <div class="flex items-center justify-between mb-4">
                <h3 class="text-slate-400 font-medium flex items-center gap-2">
                    <svg class="w-5 h-5 text-pink-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 10l7-7m0 0l7 7m-7-7v18"/>
                    </svg>
                    Upload Speed
                </h3>
                <span class="text-xs px-2 py-1 rounded-full bg-pink-500/20 text-pink-400">LIVE</span>
            </div>
            <div class="gauge-container mb-4">
                <svg viewBox="0 0 200 120" class="w-full h-full">
                    <path class="gauge-bg" d="M 20 100 A 80 80 0 0 1 180 100"/>
                    <path id="gauge-upload" class="gauge-fill gauge-upload" d="M 20 100 A 80 80 0 0 1 180 100" 
                          stroke-dasharray="251" stroke-dashoffset="251"/>
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-end pb-2">
                    <span id="upload-speed" class="stat-value neon-text-magenta">0.00</span>
                    <span class="text-slate-400 text-sm">Mbps</span>
                </div>
            </div>
            <div class="grid grid-cols-2 gap-4 text-center">
                <div class="p-3 rounded-xl bg-white/5">
                    <div class="text-xs text-slate-500 mb-1">Total Uploaded</div>
                    <div id="total-upload" class="text-lg font-semibold text-pink-400">0 GB</div>
                </div>
                <div class="p-3 rounded-xl bg-white/5">
                    <div class="text-xs text-slate-500 mb-1">Peak Speed</div>
                    <div id="peak-upload" class="text-lg font-semibold text-pink-400">0 Mbps</div>
                </div>
            </div>
        </div>
    </section>

    <!-- Live Chart -->
    <section class="glass-card rounded-2xl p-6 mb-6 fade-in" style="animation-delay: 0.3s">
        <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold flex items-center gap-2">
                <svg class="w-5 h-5 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
                </svg>
                Traffic History
            </h3>
            <div class="flex gap-4 text-sm">
                <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-cyan-400"></div>
                    <span class="text-slate-400">Download</span>
                </div>
                <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full bg-pink-400"></div>
                    <span class="text-slate-400">Upload</span>
                </div>
            </div>
        </div>
        <div class="h-64 md:h-80">
            <canvas id="traffic-chart"></canvas>
        </div>
    </section>

    <!-- Stats Grid -->
    <section class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6 mb-6">
        <!-- System Info -->
        <div class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.4s">
            <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/>
                </svg>
                System Info
            </h3>
            <div class="space-y-3">
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">Hostname</span>
                    <span id="sys-hostname" class="font-medium text-sm">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">Model</span>
                    <span id="sys-model" class="font-medium text-sm truncate max-w-[150px]">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">Firmware</span>
                    <span id="sys-firmware" class="font-medium text-sm truncate max-w-[150px]">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">Uptime</span>
                    <span id="sys-uptime" class="font-medium text-sm neon-text-green">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2">
                    <span class="text-slate-400 text-sm">CPU Load</span>
                    <span id="sys-cpu" class="font-medium text-sm">0%</span>
                </div>
            </div>
            <!-- Memory Bar -->
            <div class="mt-4">
                <div class="flex justify-between text-xs mb-1">
                    <span class="text-slate-400">Memory Usage</span>
                    <span id="mem-text" class="text-slate-300">0%</span>
                </div>
                <div class="h-2 bg-white/10 rounded-full overflow-hidden">
                    <div id="mem-bar" class="h-full bg-gradient-to-r from-purple-500 to-pink-500 rounded-full transition-all duration-500" style="width: 0%"></div>
                </div>
            </div>
        </div>

        <!-- Network Info -->
        <div class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.5s">
            <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                <svg class="w-5 h-5 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                </svg>
                Network Info
            </h3>
            <div class="space-y-3">
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">WAN IP</span>
                    <span id="net-wan-ip" class="font-medium text-sm font-mono">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">LAN IP</span>
                    <span id="net-lan-ip" class="font-medium text-sm font-mono">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">WAN Interface</span>
                    <span id="net-wan-iface" class="font-medium text-sm">Loading...</span>
                </div>
                <div class="flex justify-between items-center py-2 border-b border-white/10">
                    <span class="text-slate-400 text-sm">DNS Server</span>
                    <span id="net-dns" class="font-medium text-sm font-mono truncate max-w-[150px]">Loading...</span>
                </div>
            </div>
            <!-- ISP Info (External API) -->
            <div class="mt-4 p-3 rounded-xl bg-gradient-to-r from-blue-500/10 to-purple-500/10 border border-blue-500/20">
                <div class="text-xs text-slate-400 mb-2">ISP Information</div>
                <div id="isp-info" class="text-sm">
                    <div class="flex justify-between mb-1">
                        <span class="text-slate-400">ISP:</span>
                        <span id="isp-name" class="font-medium">Checking...</span>
                    </div>
                    <div class="flex justify-between mb-1">
                        <span class="text-slate-400">Location:</span>
                        <span id="isp-location" class="font-medium">Checking...</span>
                    </div>
                    <div class="flex justify-between">
                        <span class="text-slate-400">Public IP:</span>
                        <span id="isp-public-ip" class="font-medium font-mono">Checking...</span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Connected Devices -->
        <div class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.6s">
            <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold flex items-center gap-2">
                    <svg class="w-5 h-5 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                    </svg>
                    Devices
                </h3>
                <div class="flex items-center gap-2">
                    <span id="device-count" class="text-2xl font-bold neon-text-cyan">0</span>
                    <span class="text-slate-400 text-sm">online</span>
                </div>
            </div>
            <div id="device-list" class="space-y-2 max-h-64 overflow-y-auto scrollbar-thin pr-2">
                <div class="loading-skeleton h-12 rounded-lg"></div>
                <div class="loading-skeleton h-12 rounded-lg"></div>
                <div class="loading-skeleton h-12 rounded-lg"></div>
            </div>
        </div>
    </section>

    <!-- Interfaces Table -->
    <section class="glass-card rounded-2xl p-6 fade-in" style="animation-delay: 0.7s">
        <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
            <svg class="w-5 h-5 text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"/>
            </svg>
            Network Interfaces
        </h3>
        <div class="overflow-x-auto">
            <table class="w-full text-sm">
                <thead>
                    <tr class="text-slate-400 text-left border-b border-white/10">
                        <th class="pb-3 font-medium">Interface</th>
                        <th class="pb-3 font-medium">MAC Address</th>
                        <th class="pb-3 font-medium">State</th>
                        <th class="pb-3 font-medium text-right">RX</th>
                        <th class="pb-3 font-medium text-right">TX</th>
                    </tr>
                </thead>
                <tbody id="interfaces-table">
                    <tr><td colspan="5" class="py-8 text-center text-slate-500">Loading interfaces...</td></tr>
                </tbody>
            </table>
        </div>
    </section>

    <!-- Footer -->
    <footer class="mt-8 text-center text-slate-500 text-sm">
        <p>OpenWRT Bandwidth Monitor v2.0 | Real-time Network Statistics</p>
    </footer>

    <script>
        // ==================== CONFIGURATION ====================
        const API_BASE = '/cgi-bin/bandwidth-api.sh';
        const UPDATE_INTERVAL = 1000; // 1 second
        const CHART_MAX_POINTS = 60;
        const GAUGE_MAX_SPEED = 100; // Mbps
        
        // ==================== STATE ====================
        let lastRxBytes = 0;
        let lastTxBytes = 0;
        let lastTimestamp = Date.now();
        let peakDownload = 0;
        let peakUpload = 0;
        let trafficChart = null;
        let chartData = {
            labels: [],
            download: [],
            upload: []
        };
        
        // ==================== UTILITIES ====================
        function formatBytes(bytes, decimals = 2) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(decimals)) + ' ' + sizes[i];
        }
        
        function formatSpeed(bytesPerSec) {
            const mbps = (bytesPerSec * 8) / 1000000;
            return mbps.toFixed(2);
        }
        
        function updateGauge(elementId, value, maxValue = GAUGE_MAX_SPEED) {
            const gauge = document.getElementById(elementId);
            if (!gauge) return;
            
            const percentage = Math.min(value / maxValue, 1);
            const circumference = 251; // Arc length
            const offset = circumference * (1 - percentage);
            gauge.style.strokeDashoffset = offset;
        }
        
        function getTimeLabel() {
            const now = new Date();
            return now.toLocaleTimeString('en-US', { hour12: false });
        }
        
        // ==================== CHART INITIALIZATION ====================
        function initChart() {
            const ctx = document.getElementById('traffic-chart').getContext('2d');
            
            const gradient1 = ctx.createLinearGradient(0, 0, 0, 300);
            gradient1.addColorStop(0, 'rgba(0, 212, 255, 0.3)');
            gradient1.addColorStop(1, 'rgba(0, 212, 255, 0)');
            
            const gradient2 = ctx.createLinearGradient(0, 0, 0, 300);
            gradient2.addColorStop(0, 'rgba(255, 0, 110, 0.3)');
            gradient2.addColorStop(1, 'rgba(255, 0, 110, 0)');
            
            trafficChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [
                        {
                            label: 'Download',
                            data: [],
                            borderColor: '#00d4ff',
                            backgroundColor: gradient1,
                            borderWidth: 2,
                            fill: true,
                            tension: 0.4,
                            pointRadius: 0,
                            pointHoverRadius: 4,
                            pointHoverBackgroundColor: '#00d4ff'
                        },
                        {
                            label: 'Upload',
                            data: [],
                            borderColor: '#ff006e',
                            backgroundColor: gradient2,
                            borderWidth: 2,
                            fill: true,
                            tension: 0.4,
                            pointRadius: 0,
                            pointHoverRadius: 4,
                            pointHoverBackgroundColor: '#ff006e'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        intersect: false,
                        mode: 'index'
                    },
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            backgroundColor: 'rgba(20, 20, 35, 0.9)',
                            titleColor: '#fff',
                            bodyColor: '#94a3b8',
                            borderColor: 'rgba(255, 255, 255, 0.1)',
                            borderWidth: 1,
                            padding: 12,
                            displayColors: true,
                            callbacks: {
                                label: (context) => `${context.dataset.label}: ${context.raw.toFixed(2)} Mbps`
                            }
                        }
                    },
                    scales: {
                        x: {
                            grid: { color: 'rgba(255, 255, 255, 0.05)' },
                            ticks: { color: '#64748b', maxTicksLimit: 10 }
                        },
                        y: {
                            beginAtZero: true,
                            grid: { color: 'rgba(255, 255, 255, 0.05)' },
                            ticks: {
                                color: '#64748b',
                                callback: (value) => value + ' Mbps'
                            }
                        }
                    }
                }
            });
        }
        
        function updateChart(downloadSpeed, uploadSpeed) {
            const label = getTimeLabel();
            
            chartData.labels.push(label);
            chartData.download.push(downloadSpeed);
            chartData.upload.push(uploadSpeed);
            
            if (chartData.labels.length > CHART_MAX_POINTS) {
                chartData.labels.shift();
                chartData.download.shift();
                chartData.upload.shift();
            }
            
            trafficChart.data.labels = chartData.labels;
            trafficChart.data.datasets[0].data = chartData.download;
            trafficChart.data.datasets[1].data = chartData.upload;
            trafficChart.update('none');
        }
        
        // ==================== API CALLS ====================
        async function fetchBandwidth() {
            try {
                const response = await fetch(`${API_BASE}?action=bandwidth`);
                const data = await response.json();
                
                const now = Date.now();
                const timeDiff = (now - lastTimestamp) / 1000;
                
                if (lastRxBytes > 0 && timeDiff > 0) {
                    const rxDiff = data.wan_rx - lastRxBytes;
                    const txDiff = data.wan_tx - lastTxBytes;
                    
                    const downloadSpeed = parseFloat(formatSpeed(rxDiff / timeDiff));
                    const uploadSpeed = parseFloat(formatSpeed(txDiff / timeDiff));
                    
                    // Update display
                    document.getElementById('download-speed').textContent = downloadSpeed.toFixed(2);
                    document.getElementById('upload-speed').textContent = uploadSpeed.toFixed(2);
                    
                    // Update gauges
                    updateGauge('gauge-download', downloadSpeed);
                    updateGauge('gauge-upload', uploadSpeed);
                    
                    // Update peaks
                    if (downloadSpeed > peakDownload) {
                        peakDownload = downloadSpeed;
                        document.getElementById('peak-download').textContent = peakDownload.toFixed(2) + ' Mbps';
                    }
                    if (uploadSpeed > peakUpload) {
                        peakUpload = uploadSpeed;
                        document.getElementById('peak-upload').textContent = peakUpload.toFixed(2) + ' Mbps';
                    }
                    
                    // Update chart
                    updateChart(downloadSpeed, uploadSpeed);
                }
                
                // Update totals
                document.getElementById('total-download').textContent = formatBytes(data.wan_rx);
                document.getElementById('total-upload').textContent = formatBytes(data.wan_tx);
                
                // Update system stats
                document.getElementById('sys-cpu').textContent = data.cpu_load;
                document.getElementById('mem-text').textContent = data.mem_percent + '%';
                document.getElementById('mem-bar').style.width = data.mem_percent + '%';
                
                // Save for next calculation
                lastRxBytes = data.wan_rx;
                lastTxBytes = data.wan_tx;
                lastTimestamp = now;
                
                // Update timestamp
                document.getElementById('last-update').textContent = getTimeLabel();
                
            } catch (error) {
                console.error('Bandwidth fetch error:', error);
            }
        }
        
        async function fetchDevices() {
            try {
                const response = await fetch(`${API_BASE}?action=devices`);
                const data = await response.json();
                
                document.getElementById('device-count').textContent = data.online || 0;
                
                const deviceList = document.getElementById('device-list');
                if (data.devices && data.devices.length > 0) {
                    deviceList.innerHTML = data.devices.map(device => `
                        <div class="p-3 rounded-lg bg-white/5 ${device.status === 'online' ? 'device-online' : 'device-offline'} hover:bg-white/10 transition-colors">
                            <div class="flex justify-between items-start">
                                <div>
                                    <div class="font-medium text-sm">${device.hostname || 'Unknown'}</div>
                                    <div class="text-xs text-slate-500 font-mono">${device.ip}</div>
                                </div>
                                <div class="text-right">
                                    <div class="text-xs ${device.status === 'online' ? 'text-green-400' : 'text-red-400'}">${device.status}</div>
                                    <div class="text-xs text-slate-600 font-mono">${device.mac}</div>
                                </div>
                            </div>
                        </div>
                    `).join('');
                } else {
                    deviceList.innerHTML = '<div class="text-center text-slate-500 py-4">No devices found</div>';
                }
                
            } catch (error) {
                console.error('Devices fetch error:', error);
            }
        }
        
        async function fetchSystemInfo() {
            try {
                const response = await fetch(`${API_BASE}?action=system`);
                const data = await response.json();
                
                document.getElementById('sys-hostname').textContent = data.hostname || 'OpenWRT';
                document.getElementById('sys-model').textContent = data.model || 'Unknown';
                document.getElementById('sys-firmware').textContent = data.firmware || 'OpenWRT';
                document.getElementById('sys-uptime').textContent = data.uptime_formatted || '0d 0h 0m';
                
                document.getElementById('net-wan-ip').textContent = data.wan_ip || 'Not Connected';
                document.getElementById('net-lan-ip').textContent = data.lan_ip || '192.168.1.1';
                document.getElementById('net-wan-iface').textContent = data.wan_iface || 'eth0';
                document.getElementById('net-dns').textContent = data.dns_servers || 'N/A';
                
            } catch (error) {
                console.error('System info fetch error:', error);
            }
        }
        
        async function fetchInterfaces() {
            try {
                const response = await fetch(`${API_BASE}?action=interfaces`);
                const data = await response.json();
                
                const tbody = document.getElementById('interfaces-table');
                if (data.interfaces && data.interfaces.length > 0) {
                    tbody.innerHTML = data.interfaces.map(iface => `
                        <tr class="border-b border-white/5 hover:bg-white/5 transition-colors">
                            <td class="py-3 font-medium">${iface.name}</td>
                            <td class="py-3 font-mono text-slate-400">${iface.mac}</td>
                            <td class="py-3">
                                <span class="px-2 py-1 rounded-full text-xs ${iface.state === 'up' ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}">
                                    ${iface.state}
                                </span>
                            </td>
                            <td class="py-3 text-right font-mono text-cyan-400">${formatBytes(iface.rx_bytes)}</td>
                            <td class="py-3 text-right font-mono text-pink-400">${formatBytes(iface.tx_bytes)}</td>
                        </tr>
                    `).join('');
                }
                
            } catch (error) {
                console.error('Interfaces fetch error:', error);
            }
        }
        
        async function fetchISPInfo() {
            try {
                const response = await fetch('https://ipapi.co/json/');
                const data = await response.json();
                
                document.getElementById('isp-name').textContent = data.org || 'Unknown';
                document.getElementById('isp-location').textContent = `${data.city || ''}, ${data.country_name || ''}`;
                document.getElementById('isp-public-ip').textContent = data.ip || 'Unknown';
                
            } catch (error) {
                document.getElementById('isp-name').textContent = 'Unable to fetch';
                document.getElementById('isp-location').textContent = 'N/A';
                document.getElementById('isp-public-ip').textContent = 'N/A';
            }
        }
        
        // ==================== INITIALIZATION ====================
        document.addEventListener('DOMContentLoaded', () => {
            initChart();
            
            // Initial fetch
            fetchBandwidth();
            fetchDevices();
            fetchSystemInfo();
            fetchInterfaces();
            fetchISPInfo();
            
            // Set up intervals
            setInterval(fetchBandwidth, UPDATE_INTERVAL);
            setInterval(fetchDevices, 5000);
            setInterval(fetchSystemInfo, 10000);
            setInterval(fetchInterfaces, 10000);
            setInterval(fetchISPInfo, 60000);
        });
    </script>
</body>
</html>
HTMLEOF

#------------------------------------------------------------
# STEP 4: Buat LuCI Controller (Lua)
#------------------------------------------------------------
echo "[4/7] Creating LuCI Controller..."

cat > /usr/lib/lua/luci/controller/bandwidth.lua << 'LUAEOF'
module("luci.controller.bandwidth", package.seeall)

function index()
    entry({"admin", "status", "bandwidth"}, template("bandwidth/monitor"), _("Bandwidth Monitor"), 90).leaf = true
end
LUAEOF

#------------------------------------------------------------
# STEP 5: Buat LuCI View Template
#------------------------------------------------------------
echo "[5/7] Creating LuCI View Template..."

cat > /usr/lib/lua/luci/view/bandwidth/monitor.htm << 'VIEWEOF'
<%+header%>
<style>
    .cbi-map { padding: 0 !important; }
    .cbi-map-descr { display: none; }
    #bandwidth-frame {
        width: 100%;
        height: calc(100vh - 120px);
        min-height: 800px;
        border: none;
        border-radius: 8px;
    }
</style>
<div class="cbi-map">
    <iframe id="bandwidth-frame" src="/bandwidth/"></iframe>
</div>
<%+footer%>
VIEWEOF

#------------------------------------------------------------
# STEP 6: Konfigurasi uhttpd untuk CGI
#------------------------------------------------------------
echo "[6/7] Configuring uhttpd..."

# Backup config
cp /etc/config/uhttpd /etc/config/uhttpd.bak 2>/dev/null

# Pastikan CGI aktif
if ! grep -q "list interpreter" /etc/config/uhttpd; then
    uci add_list uhttpd.main.interpreter=".sh=/bin/sh"
    uci commit uhttpd
fi

# Set CGI prefix jika belum ada
if ! uci get uhttpd.main.cgi_prefix >/dev/null 2>&1; then
    uci set uhttpd.main.cgi_prefix='/cgi-bin'
    uci commit uhttpd
fi

#------------------------------------------------------------
# STEP 7: Restart Services
#------------------------------------------------------------
echo "[7/7] Restarting services..."

# Restart uhttpd
/etc/init.d/uhttpd restart 2>/dev/null || service uhttpd restart 2>/dev/null

# Clear LuCI cache
rm -rf /tmp/luci-modulecache/* 2>/dev/null
rm -rf /tmp/luci-indexcache* 2>/dev/null

#------------------------------------------------------------
# SELESAI
#------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           ✅ INSTALLATION COMPLETED SUCCESSFULLY!          ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  📍 Access Points:                                         ║"
echo "║                                                            ║"
echo "║  • Standalone Dashboard:                                   ║"
echo "║    http://192.168.1.1/bandwidth/                           ║"
echo "║                                                            ║"
echo "║  • LuCI Integration:                                       ║"
echo "║    Status → Bandwidth Monitor                              ║"
echo "║                                                            ║"
echo "║  • API Endpoint:                                           ║"
echo "║    http://192.168.1.1/cgi-bin/bandwidth-api.sh             ║"
echo "║                                                            ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  ⚙️  Detected Interfaces:                                   ║"
echo "║  • WAN: $WAN_IFACE                                         ║"
echo "║  • LAN: $LAN_IFACE                                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🔄 If LuCI menu doesn't appear, run: rm -rf /tmp/luci-* && /etc/init.d/uhttpd restart"
echo ""
