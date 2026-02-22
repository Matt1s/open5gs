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








# -------------------------------------------------------
# Step 1: Create and activate the WiFi hotspot
# -------------------------------------------------------
print_status "Setting up WiFi hotspot on $HOTSPOT_INTERFACE (SSID: $HOTSPOT_SSID)..."

# Delete any existing hotspot connection with the same name to avoid conflicts
nmcli connection delete "$HOTSPOT_SSID" 2>/dev/null || true

# Create the hotspot
nmcli connection add \
    type wifi \
    ifname "$HOTSPOT_INTERFACE" \
    con-name "$HOTSPOT_SSID" \
    autoconnect yes \
    ssid "$HOTSPOT_SSID" \
    -- \
    wifi.mode ap \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$HOTSPOT_PASSWORD" \
    ipv4.method shared \
    ipv4.addresses "$HOTSPOT_IP/24"

# Bring up the hotspot
nmcli connection up "$HOTSPOT_SSID"

print_status "✅ Hotspot '$HOTSPOT_SSID' is up on $HOTSPOT_INTERFACE"

# Wait for the interface to fully come up
sleep 3


# -------------------------------------------------------
# Step 2: Enable IP forwarding
# -------------------------------------------------------
print_status "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-5gcore-forwarding.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/99-5gcore-forwarding.conf


# -------------------------------------------------------
# Step 3: Configure iptables rules
# -------------------------------------------------------
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


# Wait a bit for the connection to establish
sleep 5

# -------------------------------------------------------
# Step 4: Add additional IP addresses to WiFi interface
# -------------------------------------------------------
print_status "Adding IP addresses to $HOTSPOT_INTERFACE..."

# Add IP addresses from 192.168.50.2 to 192.168.50.30
for i in {2..30}; do
    sudo ip addr add 192.168.50.$i/24 dev $HOTSPOT_INTERFACE 2>/dev/null || print_warning "IP 192.168.50.$i already assigned or error occurred"
done

# Add additional IPs
sudo ip addr add 192.168.50.200/24 dev $HOTSPOT_INTERFACE 2>/dev/null || print_warning "IP 192.168.50.200 already assigned or error occurred"
sudo ip addr add 192.168.50.101/24 dev $HOTSPOT_INTERFACE 2>/dev/null || print_warning "IP 192.168.50.101 already assigned or error occurred"

print_status "✅ IP addresses assigned to $HOTSPOT_INTERFACE"
