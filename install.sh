#!/bin/sh

#############################################
#  BANDIX DASHBOARD INSTALLER FOR OPENWRT  #
#  Version: 1.0.0                          #
#############################################

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   ██████╗  █████╗ ███╗   ██╗██████╗ ██╗██╗  ██╗          ║"
echo "║   ██╔══██╗██╔══██╗████╗  ██║██╔══██╗██║╚██╗██╔╝          ║"
echo "║   ██████╔╝███████║██╔██╗ ██║██║  ██║██║ ╚███╔╝           ║"
echo "║   ██╔══██╗██╔══██║██║╚██╗██║██║  ██║██║ ██╔██╗           ║"
echo "║   ██████╔╝██║  ██║██║ ╚████║██████╔╝██║██╔╝ ██╗          ║"
echo "║   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝╚═╝  ╚═╝          ║"
echo "║                                                           ║"
echo "║            Dashboard Installer for OpenWRT                ║"
echo "║                     Version 1.0.0                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Direktori instalasi
INSTALL_DIR="/www/bandix"
API_DIR="/www/cgi-bin"
BACKUP_DIR="/tmp/bandix_backup_$(date +%Y%m%d_%H%M%S)"

# Fungsi untuk menampilkan status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# Cek apakah running sebagai root
if [ "$(id -u)" != "0" ]; then
    print_error "Script ini harus dijalankan sebagai root!"
    exit 1
fi

echo ""
print_info "Memulai instalasi Bandix Dashboard..."
echo ""

# Step 1: Update package list
print_info "Step 1/7: Mengupdate daftar paket..."
opkg update > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_status "Daftar paket berhasil diupdate"
else
    print_warning "Gagal update paket, melanjutkan instalasi..."
fi

# Step 2: Install dependencies
print_info "Step 2/7: Menginstall dependensi..."
PACKAGES="uhttpd uhttpd-mod-ubus rpcd rpcd-mod-file rpcd-mod-iwinfo luci-lib-jsonc"

for pkg in $PACKAGES; do
    opkg install $pkg > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_status "Paket $pkg terinstall"
    else
        print_warning "Paket $pkg sudah ada atau gagal install"
    fi
done

# Step 3: Backup existing installation
print_info "Step 3/7: Backup instalasi lama (jika ada)..."
if [ -d "$INSTALL_DIR" ]; then
    mkdir -p $BACKUP_DIR
    cp -r $INSTALL_DIR $BACKUP_DIR/
    print_status "Backup tersimpan di $BACKUP_DIR"
else
    print_info "Tidak ada instalasi sebelumnya"
fi

# Step 4: Create installation directory
print_info "Step 4/7: Membuat direktori instalasi..."
mkdir -p $INSTALL_DIR
mkdir -p $API_DIR
print_status "Direktori berhasil dibuat"

# Step 5: Create API Backend Scripts
print_info "Step 5/7: Membuat API backend..."

# API: System Info
cat > $API_DIR/bandix-api << 'APIEOF'
#!/bin/sh

# Set header
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# Parse query string
ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')

case "$ACTION" in
    "system")
        # Get system info
        UPTIME=$(cat /proc/uptime | awk '{print $1}')
        HOSTNAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")
        MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Generic")
        FIRMWARE=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2)
        KERNEL=$(uname -r)
        
        # CPU Load
        CPU_LOAD=$(cat /proc/loadavg | awk '{print $1}')
        
        # Memory
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
        MEM_USED=$((MEM_TOTAL - MEM_FREE))
        MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
        
        # Temperature (if available)
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
            TEMP=$((TEMP / 1000))
        else
            TEMP="N/A"
        fi
        
        cat << EOF
{
    "hostname": "$HOSTNAME",
    "model": "$MODEL",
    "firmware": "$FIRMWARE",
    "kernel": "$KERNEL",
    "uptime": $UPTIME,
    "cpu_load": $CPU_LOAD,
    "memory": {
        "total": $MEM_TOTAL,
        "used": $MEM_USED,
        "free": $MEM_FREE,
        "percent": $MEM_PERCENT
    },
    "temperature": "$TEMP"
}
EOF
        ;;
        
    "network")
        # Get network interfaces
        WAN_IP=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null || echo "Disconnected")
        WAN_PROTO=$(uci get network.wan.proto 2>/dev/null || echo "dhcp")
        LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
        
        # Get WiFi info
        WIFI_SSID_24=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null || echo "N/A")
        WIFI_SSID_5=$(uci get wireless.@wifi-iface[1].ssid 2>/dev/null || echo "N/A")
        
        cat << EOF
{
    "wan": {
        "ip": "$WAN_IP",
        "protocol": "$WAN_PROTO"
    },
    "lan": {
        "ip": "$LAN_IP"
    },
    "wifi": {
        "ssid_24ghz": "$WIFI_SSID_24",
        "ssid_5ghz": "$WIFI_SSID_5"
    }
}
EOF
        ;;
        
    "devices")
        # Get connected devices from DHCP leases
        echo "["
        FIRST=1
        while read EXPIRES MAC IP HOSTNAME CLIENTID; do
            if [ "$FIRST" = "1" ]; then
                FIRST=0
            else
                echo ","
            fi
            
            # Check if device is online (ping)
            ping -c 1 -W 1 $IP > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                STATUS="online"
            else
                STATUS="offline"
            fi
            
            cat << EOF
    {
        "mac": "$MAC",
        "ip": "$IP",
        "hostname": "$HOSTNAME",
        "status": "$STATUS",
        "expires": "$EXPIRES"
    }
EOF
        done < /tmp/dhcp.leases
        echo ""
        echo "]"
        ;;
        
    "bandwidth")
        # Get bandwidth stats
        RX_BYTES=$(cat /sys/class/net/br-lan/statistics/rx_bytes 2>/dev/null || echo "0")
        TX_BYTES=$(cat /sys/class/net/br-lan/statistics/tx_bytes 2>/dev/null || echo "0")
        
        cat << EOF
{
    "rx_bytes": $RX_BYTES,
    "tx_bytes": $TX_BYTES,
    "timestamp": $(date +%s)
}
EOF
        ;;
        
    "connections")
        # Get active connections count
        CONN_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
        CONN_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "0")
        
        cat << EOF
{
    "active": $CONN_COUNT,
    "max": $CONN_MAX
}
EOF
        ;;
        
    "reboot")
        echo '{"status": "rebooting"}'
        sleep 1
        reboot
        ;;
        
    "wifi_restart")
        wifi reload > /dev/null 2>&1
        echo '{"status": "wifi_restarted"}'
        ;;
        
    *)
        cat << EOF
{
    "error": "Unknown action",
    "available_actions": ["system", "network", "devices", "bandwidth", "connections", "reboot", "wifi_restart"]
}
EOF
        ;;
esac
APIEOF

chmod +x $API_DIR/bandix-api
print_status "API backend berhasil dibuat"

# Step 6: Create Dashboard HTML
print_info "Step 6/7: Membuat dashboard frontend..."

cat > $INSTALL_DIR/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bandix Dashboard - OpenWRT</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Inter:wght@300;400;500;600;700&display=swap');
        
        :root {
            --bg-primary: #0a0a0f;
            --bg-secondary: #12121a;
            --bg-card: rgba(20, 20, 30, 0.8);
            --text-primary: #e4e4e7;
            --text-secondary: #71717a;
            --accent: #06b6d4;
            --accent-glow: rgba(6, 182, 212, 0.3);
            --success: #22c55e;
            --warning: #f59e0b;
            --danger: #ef4444;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
        }
        
        .glass-card {
            background: var(--bg-card);
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            transition: all 0.3s ease;
        }
        
        .glass-card:hover {
            border-color: rgba(6, 182, 212, 0.3);
            box-shadow: 0 0 30px var(--accent-glow);
        }
        
        .gradient-text {
            background: linear-gradient(135deg, #06b6d4, #3b82f6, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .stat-value {
            font-family: 'JetBrains Mono', monospace;
        }
        
        .glow-effect {
            box-shadow: 0 0 20px var(--accent-glow);
        }
        
        .progress-bar {
            background: linear-gradient(90deg, #06b6d4, #3b82f6);
            border-radius: 9999px;
            transition: width 0.5s ease;
        }
        
        .progress-bg {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 9999px;
        }
        
        .device-online::before {
            content: '';
            width: 8px;
            height: 8px;
            background: var(--success);
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        
        .device-offline::before {
            content: '';
            width: 8px;
            height: 8px;
            background: var(--text-secondary);
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .sidebar {
            background: var(--bg-secondary);
            border-right: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .nav-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 16px;
            border-radius: 8px;
            transition: all 0.2s ease;
            cursor: pointer;
        }
        
        .nav-item:hover, .nav-item.active {
            background: rgba(6, 182, 212, 0.1);
            color: var(--accent);
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #06b6d4, #3b82f6);
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 500;
            transition: all 0.2s ease;
            border: none;
            cursor: pointer;
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 30px rgba(6, 182, 212, 0.3);
        }
        
        .btn-danger {
            background: linear-gradient(135deg, #ef4444, #dc2626);
        }
        
        .btn-danger:hover {
            box-shadow: 0 10px 30px rgba(239, 68, 68, 0.3);
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: var(--accent);
            animation: spin 1s ease-in-out infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        .fade-in {
            animation: fadeIn 0.5s ease;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        /* Custom scrollbar */
        ::-webkit-scrollbar {
            width: 8px;
        }
        
        ::-webkit-scrollbar-track {
            background: var(--bg-secondary);
        }
        
        ::-webkit-scrollbar-thumb {
            background: rgba(6, 182, 212, 0.3);
            border-radius: 4px;
        }
        
        ::-webkit-scrollbar-thumb:hover {
            background: var(--accent);
        }
    </style>
</head>
<body>
    <div class="flex min-h-screen">
        <!-- Sidebar -->
        <aside class="sidebar w-64 p-4 hidden lg:block">
            <div class="mb-8">
                <h1 class="text-2xl font-bold gradient-text">Bandix</h1>
                <p class="text-sm text-zinc-500">OpenWRT Dashboard</p>
            </div>
            
            <nav class="space-y-2">
                <div class="nav-item active" onclick="showSection('dashboard')">
                    <i data-lucide="layout-dashboard" class="w-5 h-5"></i>
                    <span>Dashboard</span>
                </div>
                <div class="nav-item" onclick="showSection('devices')">
                    <i data-lucide="smartphone" class="w-5 h-5"></i>
                    <span>Devices</span>
                </div>
                <div class="nav-item" onclick="showSection('network')">
                    <i data-lucide="network" class="w-5 h-5"></i>
                    <span>Network</span>
                </div>
                <div class="nav-item" onclick="showSection('wifi')">
                    <i data-lucide="wifi" class="w-5 h-5"></i>
                    <span>Wireless</span>
                </div>
                <div class="nav-item" onclick="showSection('system')">
                    <i data-lucide="settings" class="w-5 h-5"></i>
                    <span>System</span>
                </div>
            </nav>
            
            <div class="absolute bottom-4 left-4 right-4">
                <div class="glass-card p-4">
                    <p class="text-xs text-zinc-500 mb-2">System Uptime</p>
                    <p id="uptime" class="stat-value text-accent text-lg">Loading...</p>
                </div>
            </div>
        </aside>
        
        <!-- Main Content -->
        <main class="flex-1 p-6 overflow-auto">
            <!-- Header -->
            <header class="flex items-center justify-between mb-8">
                <div>
                    <h2 class="text-2xl font-bold" id="section-title">Dashboard</h2>
                    <p class="text-zinc-500" id="hostname">Loading hostname...</p>
                </div>
                <div class="flex items-center gap-4">
                    <button class="btn-primary" onclick="refreshData()">
                        <i data-lucide="refresh-cw" class="w-4 h-4 inline mr-2"></i>
                        Refresh
                    </button>
                    <button class="btn-primary btn-danger" onclick="confirmReboot()">
                        <i data-lucide="power" class="w-4 h-4 inline mr-2"></i>
                        Reboot
                    </button>
                </div>
            </header>
            
            <!-- Dashboard Section -->
            <section id="section-dashboard" class="fade-in">
                <!-- Stats Grid -->
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                    <div class="glass-card p-6">
                        <div class="flex items-center justify-between mb-4">
                            <span class="text-zinc-400">Connected Devices</span>
                            <i data-lucide="users" class="w-5 h-5 text-cyan-400"></i>
                        </div>
                        <p id="device-count" class="stat-value text-3xl font-bold">-</p>
                        <p class="text-xs text-zinc-500 mt-2">Active on network</p>
                    </div>
                    
                    <div class="glass-card p-6">
                        <div class="flex items-center justify-between mb-4">
                            <span class="text-zinc-400">Active Connections</span>
                            <i data-lucide="activity" class="w-5 h-5 text-blue-400"></i>
                        </div>
                        <p id="conn-count" class="stat-value text-3xl font-bold">-</p>
                        <p class="text-xs text-zinc-500 mt-2">NAT connections</p>
                    </div>
                    
                    <div class="glass-card p-6">
                        <div class="flex items-center justify-between mb-4">
                            <span class="text-zinc-400">Download</span>
                            <i data-lucide="download" class="w-5 h-5 text-green-400"></i>
                        </div>
                        <p id="download-speed" class="stat-value text-3xl font-bold">- MB/s</p>
                        <p class="text-xs text-zinc-500 mt-2">Current speed</p>
                    </div>
                    
                    <div class="glass-card p-6">
                        <div class="flex items-center justify-between mb-4">
                            <span class="text-zinc-400">Upload</span>
                            <i data-lucide="upload" class="w-5 h-5 text-purple-400"></i>
                        </div>
                        <p id="upload-speed" class="stat-value text-3xl font-bold">- MB/s</p>
                        <p class="text-xs text-zinc-500 mt-2">Current speed</p>
                    </div>
                </div>
                
                <!-- Charts & Info -->
                <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
                    <!-- Bandwidth Chart -->
                    <div class="glass-card p-6 lg:col-span-2">
                        <h3 class="text-lg font-semibold mb-4">Bandwidth Usage</h3>
                        <canvas id="bandwidthChart" height="200"></canvas>
                    </div>
                    
                    <!-- System Status -->
                    <div class="glass-card p-6">
                        <h3 class="text-lg font-semibold mb-4">System Status</h3>
                        <div class="space-y-4">
                            <div>
                                <div class="flex justify-between text-sm mb-2">
                                    <span class="text-zinc-400">CPU Load</span>
                                    <span id="cpu-load" class="stat-value">-</span>
                                </div>
                                <div class="progress-bg h-2">
                                    <div id="cpu-bar" class="progress-bar h-2" style="width: 0%"></div>
                                </div>
                            </div>
                            
                            <div>
                                <div class="flex justify-between text-sm mb-2">
                                    <span class="text-zinc-400">Memory Usage</span>
                                    <span id="mem-usage" class="stat-value">-</span>
                                </div>
                                <div class="progress-bg h-2">
                                    <div id="mem-bar" class="progress-bar h-2" style="width: 0%"></div>
                                </div>
                            </div>
                            
                            <div>
                                <div class="flex justify-between text-sm mb-2">
                                    <span class="text-zinc-400">Temperature</span>
                                    <span id="temp" class="stat-value">-</span>
                                </div>
                            </div>
                            
                            <div>
                                <div class="flex justify-between text-sm mb-2">
                                    <span class="text-zinc-400">Firmware</span>
                                    <span id="firmware" class="stat-value text-xs">-</span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Network Info & Devices -->
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                    <!-- Network Info -->
                    <div class="glass-card p-6">
                        <h3 class="text-lg font-semibold mb-4">Network Information</h3>
                        <div class="space-y-3">
                            <div class="flex justify-between py-2 border-b border-zinc-800">
                                <span class="text-zinc-400">WAN IP</span>
                                <span id="wan-ip" class="stat-value">-</span>
                            </div>
                            <div class="flex justify-between py-2 border-b border-zinc-800">
                                <span class="text-zinc-400">WAN Protocol</span>
                                <span id="wan-proto" class="stat-value">-</span>
                            </div>
                            <div class="flex justify-between py-2 border-b border-zinc-800">
                                <span class="text-zinc-400">LAN IP</span>
                                <span id="lan-ip" class="stat-value">-</span>
                            </div>
                            <div class="flex justify-between py-2 border-b border-zinc-800">
                                <span class="text-zinc-400">WiFi 2.4GHz</span>
                                <span id="wifi-24" class="stat-value">-</span>
                            </div>
                            <div class="flex justify-between py-2">
                                <span class="text-zinc-400">WiFi 5GHz</span>
                                <span id="wifi-5" class="stat-value">-</span>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Connected Devices List -->
                    <div class="glass-card p-6">
                        <h3 class="text-lg font-semibold mb-4">Connected Devices</h3>
                        <div id="device-list" class="space-y-3 max-h-64 overflow-auto">
                            <p class="text-zinc-500">Loading devices...</p>
                        </div>
                    </div>
                </div>
            </section>
            
            <!-- Other sections (hidden by default) -->
            <section id="section-devices" class="hidden fade-in">
                <div class="glass-card p-6">
                    <h3 class="text-lg font-semibold mb-4">All Connected Devices</h3>
                    <div id="all-devices" class="space-y-3">
                        <p class="text-zinc-500">Loading...</p>
                    </div>
                </div>
            </section>
            
            <section id="section-network" class="hidden fade-in">
                <div class="glass-card p-6">
                    <h3 class="text-lg font-semibold mb-4">Network Configuration</h3>
                    <p class="text-zinc-500">Network settings will be displayed here.</p>
                </div>
            </section>
            
            <section id="section-wifi" class="hidden fade-in">
                <div class="glass-card p-6">
                    <h3 class="text-lg font-semibold mb-4">Wireless Settings</h3>
                    <p class="text-zinc-500">WiFi configuration will be displayed here.</p>
                    <button class="btn-primary mt-4" onclick="restartWifi()">
                        <i data-lucide="refresh-cw" class="w-4 h-4 inline mr-2"></i>
                        Restart WiFi
                    </button>
                </div>
            </section>
            
            <section id="section-system" class="hidden fade-in">
                <div class="glass-card p-6">
                    <h3 class="text-lg font-semibold mb-4">System Settings</h3>
                    <p class="text-zinc-500">System configuration will be displayed here.</p>
                </div>
            </section>
        </main>
    </div>
    
    <script>
        // Initialize Lucide icons
        lucide.createIcons();
        
        // API Base URL
        const API_URL = '/cgi-bin/bandix-api';
        
        // Chart instance
        let bandwidthChart;
        let bandwidthData = {
            labels: [],
            download: [],
            upload: []
        };
        let lastRxBytes = 0;
        let lastTxBytes = 0;
        
        // Initialize chart
        function initChart() {
            const ctx = document.getElementById('bandwidthChart').getContext('2d');
            bandwidthChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: bandwidthData.labels,
                    datasets: [
                        {
                            label: 'Download',
                            data: bandwidthData.download,
                            borderColor: '#22c55e',
                            backgroundColor: 'rgba(34, 197, 94, 0.1)',
                            fill: true,
                            tension: 0.4
                        },
                        {
                            label: 'Upload',
                            data: bandwidthData.upload,
                            borderColor: '#8b5cf6',
                            backgroundColor: 'rgba(139, 92, 246, 0.1)',
                            fill: true,
                            tension: 0.4
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            labels: { color: '#a1a1aa' }
                        }
                    },
                    scales: {
                        x: {
                            grid: { color: 'rgba(255,255,255,0.05)' },
                            ticks: { color: '#71717a' }
                        },
                        y: {
                            grid: { color: 'rgba(255,255,255,0.05)' },
                            ticks: { color: '#71717a' }
                        }
                    }
                }
            });
        }
        
        // Format bytes
        function formatBytes(bytes, decimals = 2) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(decimals)) + ' ' + sizes[i];
        }
        
        // Format uptime
        function formatUptime(seconds) {
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            
            if (days > 0) return `${days}d ${hours}h ${minutes}m`;
            if (hours > 0) return `${hours}h ${minutes}m`;
            return `${minutes}m`;
        }
        
        // Fetch system info
        async function fetchSystemInfo() {
            try {
                const response = await fetch(`${API_URL}?action=system`);
                const data = await response.json();
                
                document.getElementById('hostname').textContent = data.hostname + ' - ' + data.model;
                document.getElementById('uptime').textContent = formatUptime(data.uptime);
                document.getElementById('cpu-load').textContent = data.cpu_load;
                document.getElementById('cpu-bar').style.width = Math.min(data.cpu_load * 100, 100) + '%';
                document.getElementById('mem-usage').textContent = data.memory.percent + '%';
                document.getElementById('mem-bar').style.width = data.memory.percent + '%';
                document.getElementById('temp').textContent = data.temperature !== 'N/A' ? data.temperature + '°C' : 'N/A';
                document.getElementById('firmware').textContent = data.firmware;
            } catch (error) {
                console.error('Error fetching system info:', error);
            }
        }
        
        // Fetch network info
        async function fetchNetworkInfo() {
            try {
                const response = await fetch(`${API_URL}?action=network`);
                const data = await response.json();
                
                document.getElementById('wan-ip').textContent = data.wan.ip;
                document.getElementById('wan-proto').textContent = data.wan.protocol.toUpperCase();
                document.getElementById('lan-ip').textContent = data.lan.ip;
                document.getElementById('wifi-24').textContent = data.wifi.ssid_24ghz;
                document.getElementById('wifi-5').textContent = data.wifi.ssid_5ghz;
            } catch (error) {
                console.error('Error fetching network info:', error);
            }
        }
        
        // Fetch devices
        async function fetchDevices() {
            try {
                const response = await fetch(`${API_URL}?action=devices`);
                const devices = await response.json();
                
                document.getElementById('device-count').textContent = devices.length;
                
                const deviceList = document.getElementById('device-list');
                const allDevices = document.getElementById('all-devices');
                
                if (devices.length === 0) {
                    deviceList.innerHTML = '<p class="text-zinc-500">No devices connected</p>';
                    allDevices.innerHTML = '<p class="text-zinc-500">No devices connected</p>';
                    return;
                }
                
                const html = devices.map(device => `
                    <div class="flex items-center justify-between py-2 border-b border-zinc-800">
                        <div class="flex items-center">
                            <span class="${device.status === 'online' ? 'device-online' : 'device-offline'}"></span>
                            <div>
                                <p class="font-medium">${device.hostname || 'Unknown'}</p>
                                <p class="text-xs text-zinc-500">${device.mac}</p>
                            </div>
                        </div>
                        <span class="stat-value text-sm">${device.ip}</span>
                    </div>
                `).join('');
                
                deviceList.innerHTML = html;
                allDevices.innerHTML = html;
            } catch (error) {
                console.error('Error fetching devices:', error);
            }
        }
        
        // Fetch connections
        async function fetchConnections() {
            try {
                const response = await fetch(`${API_URL}?action=connections`);
                const data = await response.json();
                document.getElementById('conn-count').textContent = data.active;
            } catch (error) {
                console.error('Error fetching connections:', error);
            }
        }
        
        // Fetch bandwidth
        async function fetchBandwidth() {
            try {
                const response = await fetch(`${API_URL}?action=bandwidth`);
                const data = await response.json();
                
                if (lastRxBytes > 0) {
                    const rxSpeed = (data.rx_bytes - lastRxBytes) / 1024 / 1024; // MB/s
                    const txSpeed = (data.tx_bytes - lastTxBytes) / 1024 / 1024; // MB/s
                    
                    document.getElementById('download-speed').textContent = rxSpeed.toFixed(2) + ' MB/s';
                    document.getElementById('upload-speed').textContent = txSpeed.toFixed(2) + ' MB/s';
                    
                    // Update chart
                    const now = new Date().toLocaleTimeString();
                    bandwidthData.labels.push(now);
                    bandwidthData.download.push(rxSpeed);
                    bandwidthData.upload.push(txSpeed);
                    
                    // Keep only last 20 data points
                    if (bandwidthData.labels.length > 20) {
                        bandwidthData.labels.shift();
                        bandwidthData.download.shift();
                        bandwidthData.upload.shift();
                    }
                    
                    bandwidthChart.update();
                }
                
                lastRxBytes = data.rx_bytes;
                lastTxBytes = data.tx_bytes;
            } catch (error) {
                console.error('Error fetching bandwidth:', error);
            }
        }
        
        // Refresh all data
        function refreshData() {
            fetchSystemInfo();
            fetchNetworkInfo();
            fetchDevices();
            fetchConnections();
            fetchBandwidth();
        }
        
        // Show section
        function showSection(section) {
            // Hide all sections
            document.querySelectorAll('[id^="section-"]').forEach(el => {
                if (!el.id.includes('title')) {
                    el.classList.add('hidden');
                }
            });
            
            // Show selected section
            document.getElementById('section-' + section).classList.remove('hidden');
            
            // Update title
            const titles = {
                'dashboard': 'Dashboard',
                'devices': 'Devices',
                'network': 'Network',
                'wifi': 'Wireless',
                'system': 'System'
            };
            document.getElementById('section-title').textContent = titles[section];
            
            // Update nav
            document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
            event.target.closest('.nav-item').classList.add('active');
        }
        
        // Confirm reboot
        function confirmReboot() {
            if (confirm('Are you sure you want to reboot the router?')) {
                fetch(`${API_URL}?action=reboot`);
                alert('Router is rebooting...');
            }
        }
        
        // Restart WiFi
        function restartWifi() {
            fetch(`${API_URL}?action=wifi_restart`)
                .then(() => alert('WiFi restarted successfully!'))
                .catch(() => alert('Failed to restart WiFi'));
        }
        
        // Initialize
        document.addEventListener('DOMContentLoaded', () => {
            initChart();
            refreshData();
            
            // Auto refresh every 2 seconds
            setInterval(refreshData, 2000);
        });
    </script>
</body>
</html>
HTMLEOF

print_status "Dashboard frontend berhasil dibuat"

# Step 7: Configure uhttpd
print_info "Step 7/7: Mengkonfigurasi web server..."

# Enable CGI
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci set uhttpd.main.index_page='index.html'
uci commit uhttpd

# Restart uhttpd
/etc/init.d/uhttpd restart > /dev/null 2>&1
print_status "Web server berhasil dikonfigurasi"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║           ✓ INSTALASI BERHASIL!                          ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Akses dashboard di:${NC}"
echo -e "   ${YELLOW}http://$(uci get network.lan.ipaddr)/bandix/${NC}"
echo ""
echo -e "${CYAN}Atau jika menggunakan IP default:${NC}"
echo -e "   ${YELLOW}http://192.168.1.1/bandix/${NC}"
echo ""
print_info "Selamat menggunakan Bandix Dashboard!"
echo ""
