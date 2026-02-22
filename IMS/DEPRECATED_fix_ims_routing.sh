#!/bin/bash

echo "========================================"
echo "IMS Routing Fix Script"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get network information
IMS_NET_ID=$(docker network inspect ims_network --format '{{.Id}}' 2>/dev/null | cut -c1-12 || true)
if [ -n "$IMS_NET_ID" ]; then
    DOCKER_NETWORK="br-$IMS_NET_ID"
else
    # fallback: try to find a bridge that carries 172.22.0.0/24
    DOCKER_NETWORK=$(ip -o -4 route show | grep "172.22.0.0/24" | awk '{print $3}' | head -1 || true)
fi
IMS_TUNNEL="ogstun2"
PCSCF_IP="172.22.0.21"
IMS_SUBNET="10.46.0.0/16"

echo "Configuration:"
echo "  Docker Network: $DOCKER_NETWORK"
echo "  IMS Tunnel: $IMS_TUNNEL"
echo "  P-CSCF IP: $PCSCF_IP"
echo "  IMS Subnet: $IMS_SUBNET"
echo ""

# Check if ogstun2 exists
if ! ip link show $IMS_TUNNEL > /dev/null 2>&1; then
    echo -e "${RED}ERROR: IMS tunnel interface $IMS_TUNNEL does not exist!${NC}"
    echo "Please start the UPF first."
    exit 1
fi

# Check if P-CSCF container is running
if ! docker ps --format '{{.Names}}' | grep -q "ims_pcscf\|pcscf"; then
    echo -e "${RED}ERROR: P-CSCF container is not running!${NC}"
    echo "Please start IMS containers first."
    exit 1
fi

echo "Step 1: Enable IP forwarding"
sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo "Step 2: Add iptables rules for IMS traffic routing"

# Allow forwarding between IMS tunnel and Docker network
echo "  - Allow forwarding from $IMS_TUNNEL to $DOCKER_NETWORK"
iptables -I FORWARD 1 -i $IMS_TUNNEL -o $DOCKER_NETWORK -j ACCEPT
iptables -I FORWARD 1 -i $DOCKER_NETWORK -o $IMS_TUNNEL -m state --state RELATED,ESTABLISHED -j ACCEPT

# Ensure DOCKER-USER chain allows this traffic
echo "  - Configure DOCKER-USER chain for IMS traffic"
iptables -I DOCKER-USER 1 -i $IMS_TUNNEL -o $DOCKER_NETWORK -j ACCEPT
iptables -I DOCKER-USER 1 -i $DOCKER_NETWORK -o $IMS_TUNNEL -j ACCEPT

# Allow NAT for IMS traffic if needed
echo "  - Configure NAT for IMS traffic"
iptables -t nat -I POSTROUTING 1 -s $IMS_SUBNET -d 172.22.0.0/24 -o $DOCKER_NETWORK -j ACCEPT

echo ""
echo "Step 3: Testing connectivity"
echo -e "${YELLOW}Testing ping from IMS tunnel to P-CSCF...${NC}"
if ping -c 2 -W 2 -I $IMS_TUNNEL $PCSCF_IP > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SUCCESS: Can ping P-CSCF from IMS tunnel!${NC}"
else
    echo -e "${RED}✗ WARNING: Cannot ping P-CSCF from IMS tunnel${NC}"
    echo "This might be OK if P-CSCF doesn't respond to ICMP, but routing is configured."
fi

echo ""
echo "Step 4: Verify iptables rules"
echo -e "${YELLOW}Current FORWARD chain rules for IMS:${NC}"
iptables -L FORWARD -n -v | grep -E "$IMS_TUNNEL|ogstun2" | head -5

echo ""
echo -e "${YELLOW}Current DOCKER-USER chain rules for IMS:${NC}"
iptables -L DOCKER-USER -n -v | grep -E "$IMS_TUNNEL|ogstun2" | head -5

echo ""
echo "========================================"
echo -e "${GREEN}IMS Routing Fix Applied!${NC}"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Toggle airplane mode on your phone to force re-registration"
echo "2. Monitor IMS PDU session: docker logs -f smf | grep 'DNN\[ims\]'"
echo "3. Monitor P-CSCF logs: docker logs -f pcscf | grep REGISTER"
echo "4. Check IMS session: docker logs smf 2>&1 | grep -E 'IMSI.*imsi-999700000071627.*DNN\[ims\]'"
echo ""
echo "To capture IMS traffic:"
echo "  sudo tcpdump -i ogstun2 -n -vv"
echo ""
