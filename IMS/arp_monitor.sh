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
