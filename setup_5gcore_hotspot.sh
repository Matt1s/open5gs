#!/bin/bash

# Script to update iptables rules from wlp4s0 to enx00e04c0266c9

# Configuration
OLD_INTERFACE="wlp4s0"
NEW_INTERFACE="enx00e04c0266c9"
TUNNEL_INTERFACE="ogstun"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
}

# Check if interfaces exist
check_interfaces() {
    print_status "Checking interfaces..."
    
    if ! ip link show "$NEW_INTERFACE" &> /dev/null; then
        print_error "Interface $NEW_INTERFACE not found"
        print_status "Available interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk '{print "  " $2}' | sed 's/://'
        exit 1
    fi
    
    if ! ip link show "$TUNNEL_INTERFACE" &> /dev/null; then
        print_warning "Interface $TUNNEL_INTERFACE not found (this might be okay if not created yet)"
    fi
    
    print_success "Target interface $NEW_INTERFACE found"
}

# Show current relevant iptables rules
show_current_rules() {
    print_status "Current FORWARD chain rules involving $OLD_INTERFACE and $TUNNEL_INTERFACE:"
    echo
    
    # Show rules with line numbers
    sudo iptables -L FORWARD --line-numbers -v | grep -E "$OLD_INTERFACE|$TUNNEL_INTERFACE|Chain FORWARD" || {
        print_warning "No existing rules found"
    }
    echo
}

# Backup current iptables rules
backup_iptables() {
    BACKUP_FILE="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
    print_status "Backing up current iptables rules to $BACKUP_FILE"
    
    sudo iptables-save > "$BACKUP_FILE"
    print_success "Backup created: $BACKUP_FILE"
}

# Remove old rules
remove_old_rules() {
    print_status "Removing old rules with interface $OLD_INTERFACE..."
    
    # Find and remove rules (we need to be careful about the order)
    # Remove rules involving wlp4s0 and ogstun
    
    # Method 1: Remove by specification (safer)
    sudo iptables -D FORWARD -i "$TUNNEL_INTERFACE" -o "$OLD_INTERFACE" -j ACCEPT 2>/dev/null && \
        print_success "Removed: $TUNNEL_INTERFACE -> $OLD_INTERFACE ACCEPT" || \
        print_warning "Rule not found: $TUNNEL_INTERFACE -> $OLD_INTERFACE ACCEPT"
    
    sudo iptables -D FORWARD -i "$OLD_INTERFACE" -o "$TUNNEL_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && \
        print_success "Removed: $OLD_INTERFACE -> $TUNNEL_INTERFACE RELATED,ESTABLISHED" || \
        print_warning "Rule not found: $OLD_INTERFACE -> $TUNNEL_INTERFACE RELATED,ESTABLISHED"
    
    # Try again in case there are duplicates
    sudo iptables -D FORWARD -i "$TUNNEL_INTERFACE" -o "$OLD_INTERFACE" -j ACCEPT 2>/dev/null && \
        print_success "Removed duplicate: $TUNNEL_INTERFACE -> $OLD_INTERFACE ACCEPT" || true
    
    sudo iptables -D FORWARD -i "$OLD_INTERFACE" -o "$TUNNEL_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && \
        print_success "Removed duplicate: $OLD_INTERFACE -> $TUNNEL_INTERFACE RELATED,ESTABLISHED" || true
}

# Add new rules
add_new_rules() {
    print_status "Adding new rules with interface $NEW_INTERFACE..."
    
    # Add rules for the new interface
    sudo iptables -I FORWARD 1 -i "$TUNNEL_INTERFACE" -o "$NEW_INTERFACE" -j ACCEPT
    print_success "Added: $TUNNEL_INTERFACE -> $NEW_INTERFACE ACCEPT"
    
    sudo iptables -I FORWARD 2 -i "$NEW_INTERFACE" -o "$TUNNEL_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    print_success "Added: $NEW_INTERFACE -> $TUNNEL_INTERFACE RELATED,ESTABLISHED"
}

# Show updated rules
show_updated_rules() {
    print_status "Updated FORWARD chain rules:"
    echo
    sudo iptables -L FORWARD --line-numbers -v | grep -E "$NEW_INTERFACE|$TUNNEL_INTERFACE|Chain FORWARD"
    echo
}

# Make rules persistent
make_persistent() {
    print_status "Making iptables rules persistent..."
    
    if command -v iptables-persistent >/dev/null 2>&1 || dpkg -l | grep -q iptables-persistent; then
        sudo netfilter-persistent save
        print_success "Rules saved with netfilter-persistent"
    elif command -v iptables-save >/dev/null 2>&1; then
        # Create a simple script to restore rules on boot
        RULES_FILE="/etc/iptables/rules.v4"
        sudo mkdir -p /etc/iptables
        sudo iptables-save > "$RULES_FILE"
        print_success "Rules saved to $RULES_FILE"
        
        print_status "To make persistent across reboots, install iptables-persistent:"
        echo "  sudo apt update && sudo apt install iptables-persistent"
    else
        print_warning "No persistence method found. Rules will be lost on reboot."
        print_status "Install iptables-persistent to make rules persistent:"
        echo "  sudo apt update && sudo apt install iptables-persistent"
    fi
}

# Restore from backup function
restore_backup() {
    if [ -n "$1" ] && [ -f "$1" ]; then
        print_status "Restoring from backup: $1"
        sudo iptables-restore < "$1"
        print_success "Backup restored"
    else
        print_error "Backup file not found or not specified"
    fi
}

# Main function
main() {
    echo "========================================"
    echo "    iptables Interface Update Script"
    echo "========================================"
    echo "Changing rules from: $OLD_INTERFACE -> $NEW_INTERFACE"
    echo "Tunnel interface: $TUNNEL_INTERFACE"
    echo "========================================"
    echo
    
    check_privileges
    check_interfaces
    show_current_rules
    
    read -p "Do you want to proceed with updating the rules? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_iptables
        remove_old_rules
        add_new_rules
        show_updated_rules
        make_persistent
        
        print_success "iptables rules updated successfully!"
        echo
        print_status "Summary of changes:"
        echo "  - Removed rules using interface: $OLD_INTERFACE"
        echo "  - Added rules using interface: $NEW_INTERFACE"
        echo "  - Rules allow traffic between $TUNNEL_INTERFACE and $NEW_INTERFACE"
    else
        print_status "Operation cancelled"
        exit 0
    fi
}

# Handle script arguments
case "${1:-}" in
    --restore)
        restore_backup "$2"
        ;;
    --help|-h)
        echo "Usage: $0 [--restore backup_file] [--help]"
        echo "  --restore: Restore from a backup file"
        echo "  --help: Show this help"
        ;;
    *)
        main
        ;;
esac
