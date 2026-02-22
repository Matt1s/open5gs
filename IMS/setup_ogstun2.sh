#!/bin/bash
#
# Setup ogstun2 interface for IMS traffic
# Based on Open5GS UPF configuration
#

set -e

# Configuration from /etc/open5gs/upf.yaml
INTERFACE="ogstun2"
SUBNET="10.46.0.0/16"
GATEWAY="10.46.0.1"
DNN="ims"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Setting up $INTERFACE for $DNN        ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check if interface already exists
if ip link show $INTERFACE &> /dev/null; then
    echo -e "${YELLOW}Interface $INTERFACE already exists${NC}"
    
    # Check if IP is already assigned
    if ip addr show $INTERFACE | grep -q "$GATEWAY"; then
        echo -e "${GREEN}IP $GATEWAY already assigned to $INTERFACE${NC}"
    else
        echo -e "${YELLOW}Adding IP $GATEWAY/16 to $INTERFACE${NC}"
        ip addr add $GATEWAY/16 dev $INTERFACE 2>/dev/null || true
    fi
else
    echo -e "${YELLOW}Creating TUN interface $INTERFACE${NC}"
    
    # Create TUN interface
    ip tuntap add name $INTERFACE mode tun
    
    # Assign IP address
    ip addr add $GATEWAY/16 dev $INTERFACE
    
    # Bring interface up
    ip link set $INTERFACE up
    
    echo -e "${GREEN}Interface $INTERFACE created${NC}"
fi

# Ensure interface is up
ip link set $INTERFACE up

# Enable IP forwarding if not already enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo -e "${YELLOW}Enabling IPv4 forwarding${NC}"
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi

# Add iptables NAT rules for IMS subnet if not exists
if ! iptables -t nat -C POSTROUTING -s $SUBNET ! -o $INTERFACE -j MASQUERADE 2>/dev/null; then
    echo -e "${YELLOW}Adding NAT rule for $SUBNET${NC}"
    iptables -t nat -A POSTROUTING -s $SUBNET ! -o $INTERFACE -j MASQUERADE
fi

# Show interface status
echo ""
echo -e "${GREEN}Interface Status:${NC}"
ip addr show $INTERFACE

echo ""
echo -e "${GREEN}Routing for $SUBNET:${NC}"
ip route | grep $INTERFACE || echo "  (routes auto-managed by kernel)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} $INTERFACE setup complete!            ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "DNN: ${YELLOW}$DNN${NC}"
echo -e "Subnet: ${YELLOW}$SUBNET${NC}"  
echo -e "Gateway: ${YELLOW}$GATEWAY${NC}"
