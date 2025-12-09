#!/bin/bash

# 5G Core Hotspot Setup Script
# This script sets up a WiFi hotspot for srsRAN GNB to connect to Open5GS 5G Core
# Author: Generated for docker_open5gs project
# Date: $(date)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration from .env file
HOTSPOT_INTERFACE="wlp4s0"
HOTSPOT_SSID="5gcore"
HOTSPOT_PASSWORD="p1234567"  # Change this as needed
HOTSPOT_NETWORK="192.168.50.0/24"  # WiFi hotspot network
HOTSPOT_IP="192.168.50.1"
DOCKER_5GCORE_NETWORK="172.22.0.0/24"  # Open5GS 5G Core network
DOCKER_IMS_NETWORK="192.168.50.0/24"   # Kamailio IMS network (changed to avoid conflict)
INTERNET_INTERFACE="enx00e04c0266c9"  # Main internet connection
GNB_IP_RANGE="192.168.50.150-192.168.50.200"  # IP range for srsRAN devices
# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ARP and Device Discovery Functions
scan_arp_table() {
    print_status "Scanning ARP table for connected devices..."
    echo -e "${BLUE}Current ARP Table:${NC}"
    arp -a | grep "$HOTSPOT_INTERFACE" 2>/dev/null || arp -a | grep "$(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)"
}

ping_sweep() {
    print_status "Performing ping sweep on hotspot network..."
    local network_base=$(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    echo -e "${BLUE}Ping sweep results for $network_base.0/24:${NC}"
    
    for i in {1..254}; do
        ping -c 1 -W 1 "$network_base.$i" >/dev/null 2>&1 && echo "  ✅ $network_base.$i is reachable" &
    done
    wait
}

nmap_scan() {
    if command -v nmap &> /dev/null; then
        print_status "Running nmap scan on hotspot network..."
        echo -e "${BLUE}Nmap scan results:${NC}"
        nmap -sn $HOTSPOT_NETWORK 2>/dev/null | grep -E "(Nmap scan report|MAC Address)"
    else
        print_warning "nmap not installed. Install with: sudo apt install nmap"
    fi
}

check_dhcp_leases() {
    print_status "Checking DHCP leases..."
    local lease_file="/var/lib/NetworkManager/dnsmasq-$HOTSPOT_INTERFACE.leases"
    if [ -f "$lease_file" ]; then
        echo -e "${BLUE}DHCP Leases:${NC}"
        while read -r line; do
            if [ -n "$line" ]; then
                timestamp=$(echo "$line" | awk '{print $1}')
                mac=$(echo "$line" | awk '{print $2}')
                ip=$(echo "$line" | awk '{print $3}')
                hostname=$(echo "$line" | awk '{print $4}')
                readable_time=$(date -d "@$timestamp" 2>/dev/null || echo "Invalid timestamp")
                echo "  📱 IP: $ip | MAC: $mac | Hostname: $hostname | Lease: $readable_time"
            fi
        done < "$lease_file"
    else
        print_warning "DHCP lease file not found at $lease_file"
    fi
}

show_connected_devices() {
    echo -e "\n${GREEN}===========================================${NC}"
    echo -e "${GREEN}  Connected Devices Discovery${NC}"
    echo -e "${GREEN}===========================================${NC}"
    
    # Method 1: Check DHCP leases (most reliable)
    check_dhcp_leases
    
    echo ""
    
    # Method 2: ARP table scan
    scan_arp_table
    
    echo ""
    
    # Method 3: Network scan with nmap if available
    nmap_scan
    
    echo -e "\n${BLUE}ARP Testing Tips:${NC}"
    echo -e "  🔍 ${YELLOW}Real-time ARP monitoring:${NC}"
    echo -e "    ${YELLOW}watch -n 2 'arp -a | grep $(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)'${NC}"
    
    echo -e "  🔍 ${YELLOW}Monitor DHCP assignments:${NC}"
    echo -e "    ${YELLOW}sudo tail -f /var/lib/NetworkManager/dnsmasq-$HOTSPOT_INTERFACE.leases${NC}"
    
    echo -e "  🔍 ${YELLOW}Check network interface statistics:${NC}"
    echo -e "    ${YELLOW}cat /proc/net/arp | grep $HOTSPOT_INTERFACE${NC}"
    
    echo -e "  🔍 ${YELLOW}Scan for new devices (ping sweep):${NC}"
    echo -e "    ${YELLOW}for i in {1..254}; do ping -c 1 -W 1 $(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3).\$i >/dev/null 2>&1 && echo \"Found: $(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3).\$i\"; done${NC}"
    
    echo -e "  🔍 ${YELLOW}Advanced nmap device discovery:${NC}"
    echo -e "    ${YELLOW}nmap -sn $HOTSPOT_NETWORK${NC} (Host discovery)"
    echo -e "    ${YELLOW}nmap -sS $HOTSPOT_NETWORK${NC} (TCP SYN scan)"
    echo -e "    ${YELLOW}nmap -O $HOTSPOT_NETWORK${NC} (OS detection)"
    
    echo -e "  🔍 ${YELLOW}Monitor network traffic:${NC}"
    echo -e "    ${YELLOW}sudo tcpdump -i $HOTSPOT_INTERFACE${NC}"
    echo -e "    ${YELLOW}sudo netstat -i${NC} (Interface statistics)"
    
    echo -e "  🔍 ${YELLOW}Check wireless clients:${NC}"
    echo -e "    ${YELLOW}iw dev $HOTSPOT_INTERFACE station dump${NC}"
}

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  5G Core Hotspot Setup Script${NC}"
echo -e "${BLUE}==========================================${NC}"

# Handle command line arguments
if [[ "$1" == "--scan" || "$1" == "-s" ]]; then
    echo -e "${BLUE}Running device discovery scan only...${NC}"
    show_connected_devices
    exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e "${BLUE}Usage:${NC}"
    echo -e "  $0                 Setup the 5G Core hotspot"
    echo -e "  $0 --scan, -s      Scan for connected devices only"
    echo -e "  $0 --help, -h      Show this help message"
    exit 0
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "Please do not run this script as root. Use your regular user account."
    exit 1
fi

# Check if NetworkManager is available
if ! command -v nmcli &> /dev/null; then
    print_error "NetworkManager (nmcli) is required but not found. Please install it."
    exit 1
fi

# Check if the WiFi interface exists
if ! ip link show "$HOTSPOT_INTERFACE" &> /dev/null; then
    print_error "WiFi interface $HOTSPOT_INTERFACE not found!"
    exit 1
fi

print_status "Starting 5G Core hotspot setup..."

# Step 1: Remove existing hotspot connection if it exists
print_status "Checking for existing hotspot connections..."
if nmcli connection show | grep -q "Hotspot-5gcore"; then
    print_warning "Existing hotspot connection found. Removing..."
    sudo nmcli connection delete "Hotspot-5gcore" || true
fi

# Step 2: Disconnect from current WiFi if connected
print_status "Preparing WiFi interface..."
current_state=$(nmcli device status | grep "$HOTSPOT_INTERFACE" | awk '{print $3}')
current_connection=$(nmcli device status | grep "$HOTSPOT_INTERFACE" | awk '{print $4}')

if [[ "$current_state" == "connected" && "$current_connection" != "Hotspot-5gcore" && "$current_connection" != "--" ]]; then
    print_warning "Disconnecting from current WiFi: $current_connection"
    sudo nmcli device disconnect "$HOTSPOT_INTERFACE" || true
    sleep 2
elif [[ "$current_state" == "disconnected" ]]; then
    print_status "WiFi interface is already disconnected"
fi

# Step 3: Create hotspot connection
print_status "Creating hotspot connection..."
sudo nmcli connection add type wifi ifname "$HOTSPOT_INTERFACE" \
    con-name "Hotspot-5gcore" \
    autoconnect no \
    wifi.mode ap \
    wifi.ssid "$HOTSPOT_SSID" \
    ipv4.method shared \
    ipv4.addresses "$HOTSPOT_IP/24"

# Step 4: Set WiFi security (WPA2-PSK)
print_status "Configuring WiFi security..."
sudo nmcli connection modify "Hotspot-5gcore" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$HOTSPOT_PASSWORD"

# Step 5: Configure DNS and DHCP
print_status "Configuring DNS and DHCP..."
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d

# Convert IP range format from hyphen to comma for dnsmasq
DHCP_RANGE_START=$(echo $GNB_IP_RANGE | cut -d'-' -f1)
DHCP_RANGE_END=$(echo $GNB_IP_RANGE | cut -d'-' -f2)

# Create custom dnsmasq configuration for the hotspot
sudo tee /etc/NetworkManager/dnsmasq-shared.d/5gcore-hotspot.conf > /dev/null << EOF
# Open5GS + srsRAN Project Hotspot DHCP Configuration
# Interface binding
interface=$HOTSPOT_INTERFACE

# DHCP range for srsRAN gNB devices
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,255.255.255.0,24h

# DNS servers
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4

# Gateway (points to this machine where 5G Core runs)
dhcp-option=option:router,$HOTSPOT_IP

# Domain name
dhcp-option=option:domain-name,5gcore.local

# Lease file location
dhcp-leasefile=/var/lib/NetworkManager/dnsmasq-$HOTSPOT_INTERFACE.leases

# Log DHCP transactions for debugging
log-dhcp

# Network isolation settings
bind-interfaces
except-interface=docker0
except-interface=br-*
EOF

# Step 6: Enable IP forwarding
print_status "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-5gcore-forwarding.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-5gcore-forwarding.conf

# Step 7: Configure iptables rules
print_status "Configuring firewall rules..."

# Clean up any existing rules for our hotspot
sudo iptables -t nat -D POSTROUTING -s $HOTSPOT_NETWORK -o $INTERNET_INTERFACE -j MASQUERADE 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -s $HOTSPOT_NETWORK -o $HOTSPOT_INTERFACE -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i $INTERNET_INTERFACE -o $HOTSPOT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# Configure routing for Open5GS 5G Core Docker network
DOCKER_5GCORE_BRIDGE=$(docker network ls --filter name=docker_open5gs_default --format "{{.Name}}" | head -1)
if [ -n "$DOCKER_5GCORE_BRIDGE" ]; then
    DOCKER_5GCORE_IF=$(ip route | grep "$DOCKER_5GCORE_NETWORK" | awk '{print $3}' | head -1)
    
    if [ -n "$DOCKER_5GCORE_IF" ]; then
        print_status "Found Open5GS Docker bridge: $DOCKER_5GCORE_IF for network $DOCKER_5GCORE_NETWORK"
        
        # Clean up existing Docker bridge rules
        sudo iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $DOCKER_5GCORE_IF -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -i $DOCKER_5GCORE_IF -o $HOTSPOT_INTERFACE -j ACCEPT 2>/dev/null || true
        
        # Add new Docker bridge forwarding rules
        print_status "Adding Open5GS Docker bridge forwarding rules..."
        sudo iptables -I FORWARD 1 -i $HOTSPOT_INTERFACE -o $DOCKER_5GCORE_IF -j ACCEPT
        sudo iptables -I FORWARD 2 -i $DOCKER_5GCORE_IF -o $HOTSPOT_INTERFACE -j ACCEPT
    fi
fi

# Configure routing for Kamailio IMS Docker network
DOCKER_IMS_BRIDGE=$(docker network ls --filter name=ims_network --format "{{.Name}}" | head -1)
if [ -n "$DOCKER_IMS_BRIDGE" ]; then
    DOCKER_IMS_IF=$(ip route | grep "$DOCKER_IMS_NETWORK" | awk '{print $3}' | head -1)
    
    if [ -n "$DOCKER_IMS_IF" ]; then
        print_status "Found IMS Docker bridge: $DOCKER_IMS_IF for network $DOCKER_IMS_NETWORK"
        
        # Clean up existing IMS bridge rules
        sudo iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $DOCKER_IMS_IF -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -i $DOCKER_IMS_IF -o $HOTSPOT_INTERFACE -j ACCEPT 2>/dev/null || true
        
        # Add new IMS bridge forwarding rules
        print_status "Adding IMS Docker bridge forwarding rules..."
        sudo iptables -I FORWARD 3 -i $HOTSPOT_INTERFACE -o $DOCKER_IMS_IF -j ACCEPT
        sudo iptables -I FORWARD 4 -i $DOCKER_IMS_IF -o $HOTSPOT_INTERFACE -j ACCEPT
        
        # Add routing to allow hotspot devices to reach IMS network
        sudo ip route add $DOCKER_IMS_NETWORK via $(ip route | grep "$DOCKER_IMS_NETWORK" | awk '{print $9}') dev $DOCKER_IMS_IF 2>/dev/null || true
    fi
fi

# Add internet access rules
print_status "Adding internet access rules..."
sudo iptables -t nat -I POSTROUTING 1 -s $HOTSPOT_NETWORK -o $INTERNET_INTERFACE -j MASQUERADE
sudo iptables -I FORWARD 5 -i $HOTSPOT_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT
sudo iptables -I FORWARD 6 -i $INTERNET_INTERFACE -o $HOTSPOT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Add rule for local hotspot traffic (important for 5G Core connectivity)
sudo iptables -I FORWARD 7 -i $HOTSPOT_INTERFACE -o $HOTSPOT_INTERFACE -j ACCEPT

# Step 8: Save iptables rules
print_status "Saving firewall rules..."
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/5gcore-hotspot.rules > /dev/null

# Create systemd service to restore rules on boot
sudo tee /etc/systemd/system/5gcore-hotspot-iptables.service > /dev/null << 'EOF'
[Unit]
Description=5G Core Hotspot iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/5gcore-hotspot.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable 5gcore-hotspot-iptables.service

# Create a dedicated ARP monitoring script
print_status "Creating ARP monitoring script..."
cat > arp_monitor.sh << 'EOF'
#!/bin/bash

# ARP Monitor Script for 5G Core Hotspot
# Monitors connected devices on the hotspot network

HOTSPOT_INTERFACE="wlp4s0"
HOTSPOT_NETWORK="192.168.56.0/24"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  ARP Monitor for 5G Core Hotspot${NC}"
echo -e "${BLUE}===========================================${NC}"

while true; do
    clear
    echo -e "${BLUE}ARP Monitor - $(date)${NC}"
    echo -e "${BLUE}===========================================${NC}"
    
    # DHCP Leases
    echo -e "${GREEN}DHCP Leases:${NC}"
    lease_file="/var/lib/NetworkManager/dnsmasq-${HOTSPOT_INTERFACE}.leases"
    if [ -f "$lease_file" ]; then
        while read -r line; do
            if [ -n "$line" ]; then
                timestamp=$(echo "$line" | awk '{print $1}')
                mac=$(echo "$line" | awk '{print $2}')
                ip=$(echo "$line" | awk '{print $3}')
                hostname=$(echo "$line" | awk '{print $4}')
                readable_time=$(date -d "@$timestamp" 2>/dev/null || echo "Invalid")
                echo -e "  📱 ${YELLOW}$ip${NC} | $mac | $hostname | $readable_time"
            fi
        done < "$lease_file"
    else
        echo "  No DHCP leases found"
    fi
    
    echo ""
    
    # ARP Table
    echo -e "${GREEN}ARP Table:${NC}"
    network_base=$(echo $HOTSPOT_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    arp -a | grep "$network_base" | while read -r line; do
        echo -e "  🔗 ${YELLOW}$line${NC}"
    done
    
    echo ""
    
    # WiFi Station Info
    echo -e "${GREEN}WiFi Stations:${NC}"
    if command -v iw &> /dev/null; then
        station_info=$(iw dev $HOTSPOT_INTERFACE station dump 2>/dev/null)
        if [ -n "$station_info" ]; then
            echo "$station_info" | grep -E "(Station|signal|rx bytes|tx bytes)" | sed 's/^/  📡 /'
        else
            echo "  No station information available"
        fi
    else
        echo "  iw command not available"
    fi
    
    echo ""
    echo -e "${BLUE}Press Ctrl+C to exit. Refreshing every 5 seconds...${NC}"
    sleep 5
done
EOF

chmod +x arp_monitor.sh

# Step 9: Start the hotspot
print_status "Starting hotspot..."
sudo nmcli connection up "Hotspot-5gcore"

# Wait a bit for the connection to establish
sleep 5

# Step 9.1: Add additional IP addresses to WiFi interface
print_status "Adding IP addresses to $HOTSPOT_INTERFACE..."

# Add IP addresses from 192.168.50.2 to 192.168.50.30
for i in {2..30}; do
    sudo ip addr add 192.168.50.$i/24 dev $HOTSPOT_INTERFACE 2>/dev/null || print_warning "IP 192.168.50.$i already assigned or error occurred"
done

# Add additional IP 192.168.50.200
sudo ip addr add 192.168.50.200/24 dev $HOTSPOT_INTERFACE 2>/dev/null || print_warning "IP 192.168.50.200 already assigned or error occurred"

print_status "✅ IP addresses assigned to $HOTSPOT_INTERFACE"

# Step 10: Verify configuration
print_status "Verifying hotspot configuration..."

# Check if hotspot is active
if nmcli device status | grep -q "$HOTSPOT_INTERFACE.*connected"; then
    print_status "✅ Hotspot is active on $HOTSPOT_INTERFACE"
    
    # Show current IP configuration
    hotspot_ip=$(ip addr show $HOTSPOT_INTERFACE | grep -oP 'inet \K[\d.]+')
    print_status "✅ Hotspot IP: $hotspot_ip"
    
    # Test DNS resolution
    if nslookup google.com > /dev/null 2>&1; then
        print_status "✅ DNS resolution working"
    else
        print_warning "DNS resolution may have issues"
    fi
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        print_status "✅ Internet connectivity working"
    else
        print_warning "Internet connectivity may have issues"
    fi
    
    # Show Docker network info
    if docker network ls | grep -q "docker_open5gs_default"; then
        docker_5gcore_info=$(docker network inspect docker_open5gs_default --format "{{range .IPAM.Config}}{{.Subnet}} (Gateway: {{.Gateway}}){{end}}")
        print_status "✅ Docker 5G Core network: $docker_5gcore_info"
    fi
    
    if docker network ls | grep -q "ims_network"; then
        docker_ims_info=$(docker network inspect kamailio-ims-docker_ims_network --format "{{range .IPAM.Config}}{{.Subnet}} (Gateway: {{.Gateway}}){{end}}" 2>/dev/null || echo "Not available")
        print_status "✅ Docker IMS network: $docker_ims_info"
    fi
    
else
    print_error "❌ Failed to start hotspot!"
    exit 1
fi

# Step 11: Display connection information
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}  Hotspot Setup Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${BLUE}WiFi Network Details:${NC}"
echo -e "  SSID: ${YELLOW}$HOTSPOT_SSID${NC}"
echo -e "  Password: ${YELLOW}$HOTSPOT_PASSWORD${NC}"
echo -e "  Gateway IP: ${YELLOW}$HOTSPOT_IP${NC}"
echo -e "  Network Range: ${YELLOW}$HOTSPOT_NETWORK${NC}"
echo -e "  GNB IP Range: ${YELLOW}$GNB_IP_RANGE${NC}"

echo -e "\n${BLUE}5G Core Network Details:${NC}"
echo -e "  Open5GS Network: ${YELLOW}$DOCKER_5GCORE_NETWORK${NC}"
echo -e "  IMS Network: ${YELLOW}$DOCKER_IMS_NETWORK${NC}"
echo -e "  AMF IP: ${YELLOW}172.22.0.10${NC} (NGAP port 38412)"
echo -e "  UPF Advertise IP: ${YELLOW}$HOTSPOT_IP${NC}"

echo -e "\n${BLUE}Network Connectivity:${NC}"
echo -e "  ✅ Hotspot devices (${YELLOW}$HOTSPOT_NETWORK${NC}) can reach:"
echo -e "     - Internet via ${YELLOW}$INTERNET_INTERFACE${NC}"
echo -e "     - Open5GS containers (${YELLOW}$DOCKER_5GCORE_NETWORK${NC})"
echo -e "     - IMS containers (${YELLOW}$DOCKER_IMS_NETWORK${NC})"
echo -e "  ✅ No IP conflicts - all networks use different subnets"

echo -e "\n${BLUE}Available Services:${NC}"
echo -e "  Open5GS WebUI: ${YELLOW}http://$HOTSPOT_IP:9999${NC} (admin/1423)"
echo -e "  Grafana: ${YELLOW}http://$HOTSPOT_IP:3000${NC} (open5gs/open5gs)"
echo -e "  Prometheus: ${YELLOW}http://$HOTSPOT_IP:9090${NC}"

echo -e "\n${BLUE}For your srsRAN GNB configuration:${NC}"
echo -e "  1. Connect your srsRAN device to WiFi: ${YELLOW}$HOTSPOT_SSID${NC}"
echo -e "  2. Configure AMF address: ${YELLOW}172.22.0.10${NC}"
echo -e "  3. Use PLMN: MCC=${YELLOW}999${NC}, MNC=${YELLOW}70${NC}, TAC=${YELLOW}1${NC}"

echo -e "\n${GREEN}To stop the hotspot:${NC}"
echo -e "  ${YELLOW}sudo nmcli connection down \"Hotspot-5gcore\"${NC}"

echo -e "\n${GREEN}To restart the hotspot:${NC}"
echo -e "  ${YELLOW}sudo nmcli connection up \"Hotspot-5gcore\"${NC}"

echo -e "\n${GREEN}To view connected devices:${NC}"
echo -e "  ${YELLOW}sudo cat /var/lib/NetworkManager/dnsmasq-$HOTSPOT_INTERFACE.leases${NC}"

echo -e "\n${GREEN}To monitor AMF logs:${NC}"
echo -e "  ${YELLOW}docker logs -f amf${NC}"

print_status "Hotspot setup completed successfully! 🎉"

# Show connected devices and ARP testing tips
show_connected_devices

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}  Quick Device Discovery Commands${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${BLUE}Run these commands anytime to check connected devices:${NC}"
echo -e "  🔧 ${YELLOW}./setup_5gcore_hotspot.sh --scan${NC} (Run device discovery)"
echo -e "  🔧 ${YELLOW}./arp_monitor.sh${NC} (Real-time ARP monitoring)"
echo -e "  🔧 ${YELLOW}arp -a${NC} (Show ARP table)"
echo -e "  🔧 ${YELLOW}sudo cat /var/lib/NetworkManager/dnsmasq-$HOTSPOT_INTERFACE.leases${NC} (DHCP leases)"
echo -e "  🔧 ${YELLOW}iw dev $HOTSPOT_INTERFACE station dump${NC} (WiFi station info)"

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}  ARP Testing & Device Discovery Tips${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${BLUE}Best practices for monitoring connected devices:${NC}"
echo -e "  1️⃣ ${YELLOW}Start with DHCP leases${NC} - Most reliable method"
echo -e "  2️⃣ ${YELLOW}Use ARP table${NC} - Shows active IP-to-MAC mappings"
echo -e "  3️⃣ ${YELLOW}Monitor WiFi stations${NC} - Shows wireless connection info"
echo -e "  4️⃣ ${YELLOW}Run network scans${NC} - Discover devices that don't respond to DHCP"
echo -e "  5️⃣ ${YELLOW}Use real-time monitoring${NC} - Track device connections/disconnections"

echo -e "\n${BLUE}Common scenarios:${NC}"
echo -e "  📱 ${YELLOW}New device connects:${NC} Check DHCP leases first"
echo -e "  🔍 ${YELLOW}Device not visible:${NC} Try ping sweep or nmap scan"
echo -e "  📊 ${YELLOW}Monitor traffic:${NC} Use tcpdump or arp_monitor.sh"
echo -e "  🔧 ${YELLOW}Troubleshoot connection:${NC} Check WiFi station dump"