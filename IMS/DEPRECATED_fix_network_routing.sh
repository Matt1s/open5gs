#!/bin/bash

# Unified Network Routing Fix for Open5GS + IMS
# This script configures routing for:
# 1. PFCP connectivity (SMF <-> UPF)
# 2. IMS routing (IMS tunnel <-> IMS containers)
# 3. Hotspot connectivity (WiFi <-> Docker networks)
# 4. Internet access (Hotspot <-> Internet)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Unified Network Routing Configuration${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Get configuration
HOTSPOT_INTERFACE="wlp4s0"
HOTSPOT_NETWORK="192.168.56.0/24"
HOTSPOT_IP="192.168.56.1"
INTERNET_INTERFACE="enx00e04c0266c9"

# Docker networks
DOCKER_5GCORE_NETWORK="172.22.0.0/24"
# Detect the current IMS Docker bridge for ims_network (fallback to any route carrying 172.22.0.0/24)
DOCKER_ID=$(docker network inspect ims_network --format '{{.Id}}' 2>/dev/null | cut -c1-12 || true)
if [ -n "$DOCKER_ID" ]; then
    DOCKER_BRIDGE="br-$DOCKER_ID"
else
    # fallback: try to find a bridge that carries 172.22.0.0/24
    DOCKER_BRIDGE=$(ip -o -4 route show | grep "172.22.0.0/24" | awk '{print $3}' | head -1 || true)
fi

# 5G Core components
SMF_IP="172.22.0.7"
UPF_IP="192.168.56.1"
PCSCF_IP="172.22.0.21"

# Tunnels
INTERNET_TUNNEL="ogstun"
IMS_TUNNEL="ogstun2"
IMS_SUBNET="10.46.0.0/16"

echo -e "${GREEN}Configuration:${NC}"
echo "  Hotspot Interface: $HOTSPOT_INTERFACE"
echo "  Hotspot Network: $HOTSPOT_NETWORK"
echo "  Internet Interface: $INTERNET_INTERFACE"
echo "  Docker Bridge: $DOCKER_BRIDGE"
echo "  Docker Network: $DOCKER_5GCORE_NETWORK"
echo "  IMS Tunnel: $IMS_TUNNEL ($IMS_SUBNET)"
echo ""

# Function to print status messages
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

if [ ! -d "/sys/class/net/$HOTSPOT_INTERFACE" ]; then
    print_error "Hotspot interface $HOTSPOT_INTERFACE not found!"
    exit 1
fi

if [ ! -d "/sys/class/net/$DOCKER_BRIDGE" ]; then
    print_error "Docker bridge $DOCKER_BRIDGE not found! Is Open5GS running?"
    exit 1
fi

# Enable IP forwarding
print_status "Step 1: Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Disable reverse path filtering (required for asymmetric routing)
print_status "Step 2: Disabling reverse path filtering..."
sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 > /dev/null
sysctl -w net.ipv4.conf.$HOTSPOT_INTERFACE.rp_filter=0 > /dev/null
sysctl -w net.ipv4.conf.$DOCKER_BRIDGE.rp_filter=0 > /dev/null

if [ -d "/sys/class/net/$INTERNET_TUNNEL" ]; then
    sysctl -w net.ipv4.conf.$INTERNET_TUNNEL.rp_filter=0 > /dev/null 2>&1 || true
fi

if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    sysctl -w net.ipv4.conf.$IMS_TUNNEL.rp_filter=0 > /dev/null 2>&1 || true
fi

# CRITICAL: Allow IMS traffic from ogstun2 to Docker in raw table
# This bypasses Docker's bridge isolation rules
print_status "Step 2b: Configuring raw iptables (bypass Docker isolation)..."
if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    print_status "  - Allowing IMS tunnel traffic to Docker containers..."
    iptables -t raw -D PREROUTING -i $IMS_TUNNEL -d $DOCKER_5GCORE_NETWORK -j ACCEPT 2>/dev/null || true
    iptables -t raw -I PREROUTING 1 -i $IMS_TUNNEL -d $DOCKER_5GCORE_NETWORK -j ACCEPT -m comment --comment "IMS: Allow ogstun2 to Docker"
fi

# Clean up existing rules
print_status "Step 3: Cleaning up existing iptables rules..."

# Remove old NAT rules
iptables -t nat -D POSTROUTING -s $HOTSPOT_NETWORK -o $INTERNET_INTERFACE -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s $HOTSPOT_NETWORK -o $HOTSPOT_INTERFACE -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s $IMS_SUBNET -d $DOCKER_5GCORE_NETWORK -o $DOCKER_BRIDGE -j ACCEPT 2>/dev/null || true

# Remove old FORWARD rules
iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $INTERNET_INTERFACE -o $HOTSPOT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $DOCKER_BRIDGE -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $DOCKER_BRIDGE -o $HOTSPOT_INTERFACE -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $HOTSPOT_INTERFACE -j ACCEPT 2>/dev/null || true

# Remove old IMS rules
if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    iptables -D FORWARD -i $IMS_TUNNEL -o $DOCKER_BRIDGE -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $DOCKER_BRIDGE -o $IMS_TUNNEL -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D DOCKER-USER -i $IMS_TUNNEL -o $DOCKER_BRIDGE -j ACCEPT 2>/dev/null || true
    iptables -D DOCKER-USER -i $DOCKER_BRIDGE -o $IMS_TUNNEL -j ACCEPT 2>/dev/null || true
fi

# Remove old PFCP rules
iptables -D DOCKER-USER -p udp -s $SMF_IP -d $UPF_IP --dport 8805 -j ACCEPT 2>/dev/null || true
iptables -D DOCKER-USER -p udp -s $UPF_IP --sport 8805 -d $SMF_IP -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $DOCKER_BRIDGE -o $HOTSPOT_INTERFACE -p udp --dport 8805 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $HOTSPOT_INTERFACE -o $DOCKER_BRIDGE -p udp --sport 8805 -j ACCEPT 2>/dev/null || true

print_status "Step 4: Configuring DOCKER-USER chain (highest priority)..."

# PFCP connectivity (SMF <-> UPF) - CRITICAL
iptables -I DOCKER-USER 1 -p udp -s $SMF_IP -d $UPF_IP --dport 8805 -j ACCEPT
iptables -I DOCKER-USER 2 -p udp -s $UPF_IP --sport 8805 -d $SMF_IP -j ACCEPT

# IMS routing (IMS tunnel <-> IMS containers)
if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    print_status "  - Configuring IMS tunnel routing..."
    iptables -I DOCKER-USER 3 -i $IMS_TUNNEL -o $DOCKER_BRIDGE -j ACCEPT
    iptables -I DOCKER-USER 4 -i $DOCKER_BRIDGE -o $IMS_TUNNEL -j ACCEPT
    
    print_status "  - Enabling proxy ARP for IMS connectivity..."
    sysctl -w net.ipv4.conf.${DOCKER_BRIDGE}.proxy_arp=1 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.${IMS_TUNNEL}.proxy_arp=1 >/dev/null 2>&1
fi

# Hotspot <-> Docker network connectivity
iptables -I DOCKER-USER 5 -i $HOTSPOT_INTERFACE -o $DOCKER_BRIDGE -j ACCEPT
iptables -I DOCKER-USER 6 -i $DOCKER_BRIDGE -o $HOTSPOT_INTERFACE -j ACCEPT

print_status "Step 5: Configuring FORWARD chain..."

# PFCP forwarding
iptables -I FORWARD 1 -i $DOCKER_BRIDGE -o $HOTSPOT_INTERFACE -p udp --dport 8805 -j ACCEPT
iptables -I FORWARD 2 -i $HOTSPOT_INTERFACE -o $DOCKER_BRIDGE -p udp --sport 8805 -j ACCEPT

# IMS forwarding
if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    iptables -I FORWARD 3 -i $IMS_TUNNEL -o $DOCKER_BRIDGE -j ACCEPT
    iptables -I FORWARD 4 -i $DOCKER_BRIDGE -o $IMS_TUNNEL -m state --state RELATED,ESTABLISHED -j ACCEPT
fi

# Hotspot <-> Docker network forwarding
iptables -I FORWARD 5 -i $HOTSPOT_INTERFACE -o $DOCKER_BRIDGE -j ACCEPT
iptables -I FORWARD 6 -i $DOCKER_BRIDGE -o $HOTSPOT_INTERFACE -j ACCEPT

# Internet access for hotspot devices
iptables -I FORWARD 7 -i $HOTSPOT_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT
iptables -I FORWARD 8 -i $INTERNET_INTERFACE -o $HOTSPOT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Local hotspot traffic
iptables -I FORWARD 9 -i $HOTSPOT_INTERFACE -o $HOTSPOT_INTERFACE -j ACCEPT

print_status "Step 6: Configuring NAT (POSTROUTING)..."

# PFCP traffic - NO NAT for SMF <-> UPF communication
# Use RETURN to skip further NAT rules (ACCEPT would continue processing)
print_status "  - PFCP (SMF <-> UPF): NO NAT"
iptables -t nat -I POSTROUTING 1 -p udp -s $UPF_IP -d $SMF_IP --sport 8805 -j RETURN -m comment --comment "PFCP: UPF to SMF"
iptables -t nat -I POSTROUTING 1 -p udp -s $SMF_IP -d $UPF_IP --dport 8805 -j RETURN -m comment --comment "PFCP: SMF to UPF"

# IMS traffic bidirectional - NO NAT for IMS <-> Docker communication
if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    print_status "  - IMS forward path (IMS tunnel -> Docker): NO NAT"
    iptables -t nat -I POSTROUTING 1 -s $IMS_SUBNET -d $DOCKER_5GCORE_NETWORK -o $DOCKER_BRIDGE -j ACCEPT
    
    print_status "  - IMS return path (Docker -> IMS tunnel): NO NAT"
    iptables -t nat -I POSTROUTING 1 -s $DOCKER_5GCORE_NETWORK -d $IMS_SUBNET -o $IMS_TUNNEL -j ACCEPT -m comment --comment "IMS return: P-CSCF to UE"
fi

# Internet access NAT
iptables -t nat -I POSTROUTING 3 -s $HOTSPOT_NETWORK -o $INTERNET_INTERFACE -j MASQUERADE

print_status "Step 7: Verifying configuration..."

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Configuration Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

echo -e "\n${BLUE}DOCKER-USER chain rules:${NC}"
iptables -L DOCKER-USER -n -v --line-numbers | head -15

echo -e "\n${BLUE}FORWARD chain rules (first 15):${NC}"
iptables -L FORWARD -n -v --line-numbers | head -20

echo -e "\n${BLUE}NAT POSTROUTING rules:${NC}"
iptables -t nat -L POSTROUTING -n -v --line-numbers | head -10

# Test connectivity
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Connectivity Tests${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo ""

# Test 1: P-CSCF reachability
if timeout 2 bash -c "echo > /dev/tcp/$PCSCF_IP/5060" 2>/dev/null; then
    print_status "P-CSCF (IMS) is reachable on port 5060"
else
    print_warning "Cannot reach P-CSCF on port 5060 (might be normal if container doesn't respond)"
fi

# Test 2: Check if tunnels exist
if [ -d "/sys/class/net/$INTERNET_TUNNEL" ]; then
    print_status "Internet tunnel ($INTERNET_TUNNEL) exists"
else
    print_warning "Internet tunnel ($INTERNET_TUNNEL) not found - UPF may not be running"
fi

if [ -d "/sys/class/net/$IMS_TUNNEL" ]; then
    print_status "IMS tunnel ($IMS_TUNNEL) exists"
else
    print_warning "IMS tunnel ($IMS_TUNNEL) not found - no IMS sessions active yet"
fi

# Save rules
print_status "Step 8: Saving iptables rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/open5gs-unified-routing.rules

echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Unified Network Routing Configured!${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}What's configured:${NC}"
echo "  ✓ PFCP: SMF ($SMF_IP) ↔ UPF ($UPF_IP)"
echo "  ✓ IMS: IMS tunnel ($IMS_TUNNEL) ↔ P-CSCF ($PCSCF_IP)"
echo "  ✓ Hotspot: WiFi ($HOTSPOT_INTERFACE) ↔ Docker ($DOCKER_BRIDGE)"
echo "  ✓ Internet: Hotspot → Internet ($INTERNET_INTERFACE)"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Toggle airplane mode on your phone to re-register"
echo "  2. Monitor PDU sessions:"
echo -e "     ${YELLOW}docker logs -f smf | grep --line-buffered 'DNN\['${NC}"
echo ""
echo "  3. Monitor IMS registration:"
echo -e "     ${YELLOW}docker logs -f pcscf | grep --line-buffered REGISTER${NC}"
echo ""
echo "  4. Check active sessions:"
echo -e "     ${YELLOW}docker logs smf 2>&1 | grep 'imsi-999700000071627' | grep -E 'DNN\[(internet|ims)\]' | tail -10${NC}"
echo ""
echo -e "${BLUE}To restore these rules after reboot:${NC}"
echo -e "  ${YELLOW}sudo iptables-restore < /etc/iptables/open5gs-unified-routing.rules${NC}"
echo ""


# Policy-based routing to force UPF PFCP packets to use correct source IP (192.168.56.1)
# This fixes the issue where UPF responses were using bridge IP (172.22.0.1) instead
print_status "  - Adding policy routing for UPF PFCP source IP fix"
iptables -t mangle -I OUTPUT 1 -p udp -d $SMF_IP --dport 8805 -j MARK --set-mark 0x1 -m comment --comment "Mark PFCP packets for policy routing"
ip rule add fwmark 0x1 table 100 2>/dev/null || true
ip route add default via $DOCKER_BRIDGE_GATEWAY dev $DOCKER_BRIDGE src $UPF_IP table 100 2>/dev/null || true
ip route add 172.22.0.7 via $DOCKER_BRIDGE_GATEWAY dev $DOCKER_BRIDGE src $UPF_IP 2>/dev/null || true
