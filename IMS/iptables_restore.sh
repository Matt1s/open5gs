#!/bin/bash
# Restore iptables rules with updated interface names
# wlp4s0 -> eno1
# enx00e04c0266c9 -> enx00e04c026225

echo "Applying iptables rules..."

# === FILTER Table - INPUT Chain ===
sudo iptables -A INPUT -i eno1 -j ACCEPT
sudo iptables -A INPUT -i ogstun -j ACCEPT
# rtpengine chain will be created by rtpengine itself
# sudo iptables -A INPUT -p udp -j rtpengine

# === FILTER Table - FORWARD Chain ===
sudo iptables -P FORWARD DROP
sudo iptables -A FORWARD -j DOCKER-USER
# DOCKER-FORWARD chain will be created by Docker
# sudo iptables -A FORWARD -j DOCKER-FORWARD
sudo iptables -A FORWARD -i ogstun -j ACCEPT
sudo iptables -A FORWARD -i eno1 -o enx00e04c026225 -j ACCEPT
sudo iptables -A FORWARD -i enx00e04c026225 -o eno1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i enx00e04c026225 -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eno1 -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eno1 -o ogstun2 -m state --state RELATED,ESTABLISHED -j ACCEPT

# === FILTER Table - OUTPUT Chain ===
sudo iptables -A OUTPUT -o eno1 -j ACCEPT

# === FILTER Table - DOCKER-USER Chain ===
sudo iptables -N DOCKER-USER 2>/dev/null
sudo iptables -A DOCKER-USER -j RETURN

# === FILTER Table - DOCKER-FORWARD Chain ===
# These chains are created by Docker when it starts
# sudo iptables -N DOCKER-FORWARD 2>/dev/null
# sudo iptables -A DOCKER-FORWARD -j DOCKER-CT
# sudo iptables -A DOCKER-FORWARD -j DOCKER-INTERNAL
# sudo iptables -A DOCKER-FORWARD -j DOCKER-BRIDGE

# === NAT Table - PREROUTING Chain ===
sudo iptables -t nat -N DOCKER 2>/dev/null
sudo iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER

# === NAT Table - POSTROUTING Chain ===
sudo iptables -t nat -A POSTROUTING -s 172.22.0.0/24 ! -o br-b3e662ee1e47 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.46.0.0/16 ! -o ogstun2 -j MASQUERADE

# === NAT Table - OUTPUT Chain ===
sudo iptables -t nat -A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER

echo "iptables rules applied successfully!"
echo ""
echo "=== Current iptables rules ==="
sudo iptables -L -v -n
echo ""
echo "=== Current NAT rules ==="
sudo iptables -t nat -L -v -n
