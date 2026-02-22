# IMS Standalone Setup Guide

This guide explains how to run the IMS components separately alongside your native Open5GS installation.

## Overview

The `ims-standalone-deploy.yaml` file contains only the IMS-specific components:
- **DNS** - IMS domain resolution
- **RTPEngine** - Media relay for voice calls
- **MySQL** - IMS database
- **PyHSS** - Home Subscriber Server
- **I-CSCF** - Interrogating CSCF
- **S-CSCF** - Serving CSCF
- **P-CSCF** - Proxy CSCF (UE-facing)
- **SMSC** - SMS Center

## Prerequisites

1. Native Open5GS installation running on your host
2. Docker and Docker Compose installed
3. Same `.env` file with all required environment variables
4. All IMS component directories (dns, rtpengine, mysql, pyhss, icscf, scscf, pcscf, smsc)

## Network Architecture

Since Open5GS is running natively:
- IMS containers use a bridge network `ims_network`
- All IMS ports are exposed to the host
- Your native Open5GS can reach IMS components via host IP
- UEs can reach P-CSCF via the exposed ports

## Configuration Steps

### 1. Build Required Images

First, ensure you have the necessary Docker images built:

```bash
# Build IMS base images if needed
docker-compose -f ims-standalone-deploy.yaml build
```

### 2. Start IMS Components

```bash
docker-compose -f ims-standalone-deploy.yaml up -d
```

### 3. Configure Native Open5GS to Connect to IMS

Your native Open5GS SMF needs to know about the P-CSCF. Update your SMF configuration:

**Location**: Usually `/etc/open5gs/smf.yaml` or similar

Add/modify the IMS section:

```yaml
smf:
  sbi:
    # ... your existing SBI config
  
  pfcp:
    # ... your existing PFCP config
  
  subnet:
    - addr: 10.45.0.1/16     # Internet APN
      dnn: internet
    - addr: 10.46.0.1/16     # IMS APN
      dnn: ims
      dns:
        - ${DNS_IP}          # Use the IP from your .env
        - 8.8.8.8
      pcscf:
        - ${PCSCF_IP}        # P-CSCF IP from your .env
```

### 4. Configure UE Routing

Your native UPF needs routes to the IMS network. Add these iptables rules:

```bash
# Get your main network interface name (replace enx00e04c0266c9)
ip addr

# Add NAT for IMS APN traffic
sudo iptables -t nat -A POSTROUTING -s 10.46.0.0/16 -o <YOUR_INTERFACE> -j MASQUERADE

# Save iptables rules
sudo netfilter-persistent save
```

### 5. Verify IMS Components

Check that all IMS containers are running:

```bash
docker-compose -f ims-standalone-deploy.yaml ps
```

Check IMS component logs:

```bash
# P-CSCF logs (most important for UE connectivity)
docker logs ims_pcscf

# PyHSS logs
docker logs ims_pyhss

# Check all services
docker-compose -f ims-standalone-deploy.yaml logs -f
```

### 6. Configure Subscribers

Add IMS subscriber data via PyHSS web interface:
- URL: `http://<HOST_IP>:8080`
- Configure IMPI, IMPU, and IMS credentials for your UEs

## Network Connectivity

### From Native Open5GS to IMS:
- Use the container IPs defined in `.env` file
- Access via Docker bridge network gateway or exposed ports on `localhost`

### From UE to IMS:
- UE gets P-CSCF address from SMF during PDU session establishment
- UE reaches P-CSCF via UPF routing
- P-CSCF IP should be reachable from IMS APN subnet (10.46.0.0/16)

## Testing

### 1. Check P-CSCF Reachability

From a UE with IMS APN connected:
```bash
ping <PCSCF_IP>
```

### 2. Test SIP Registration

Monitor P-CSCF logs while UE attempts IMS registration:
```bash
docker logs -f ims_pcscf
```

### 3. Check DNS Resolution

Test IMS domain resolution:
```bash
docker exec ims_pcscf nslookup ims.mnc001.mcc001.3gppnetwork.org ${DNS_IP}
```

## Stopping IMS Components

```bash
docker-compose -f ims-standalone-deploy.yaml down
```

To remove volumes as well:
```bash
docker-compose -f ims-standalone-deploy.yaml down -v
```

## Troubleshooting

### IMS containers can't start
- Check that ports aren't already in use: `sudo netstat -tulpn | grep -E '(3306|5060|8080)'`
- Verify `.env` file has all required variables
- Check Docker network isn't conflicting: `docker network ls`

### UE can't reach P-CSCF
- Verify SMF is providing P-CSCF address in PCO (check SMF logs)
- Check UPF has route to P-CSCF IP
- Verify firewall rules allow traffic to P-CSCF ports

### SIP Registration fails
- Check PyHSS has subscriber configured
- Verify P-CSCF can reach I-CSCF: `docker exec ims_pcscf ping ${ICSCF_IP}`
- Check DNS is resolving IMS domains correctly
- Review P-CSCF, I-CSCF, and S-CSCF logs

### No audio in calls
- Check RTPEngine is running: `docker logs ims_rtpengine`
- Verify RTP port range (49000-50000) is accessible
- Check NAT configuration for media traffic

## Integration Notes

### Native SMF Configuration
The key integration point is your native SMF configuration. It must:
1. Define the IMS DNN/APN (typically "ims")
2. Provide DNS server (IMS DNS container IP)
3. Provide P-CSCF address in PCO during PDU session setup

### Alternative: Host Network Mode
If you have issues with bridge networking, you can modify the deployment to use `network_mode: host` for P-CSCF:

```yaml
pcscf:
  network_mode: host
  # Remove ports and networks sections
```

This makes P-CSCF directly accessible on host IP, but you lose container network isolation.

## Environment Variables Required

Ensure your `.env` file has these IMS-related variables:
```bash
# Network
TEST_NETWORK=10.53.1.0/24

# IMS Component IPs
DNS_IP=10.53.1.200
RTPENGINE_IP=10.53.1.201
MYSQL_IP=10.53.1.202
PYHSS_IP=10.53.1.203
ICSCF_IP=10.53.1.204
SCSCF_IP=10.53.1.205
PCSCF_IP=10.53.1.206
SMSC_IP=10.53.1.207

# IMS Bind Ports
PYHSS_BIND_PORT=3868
ICSCF_BIND_PORT=3869
SCSCF_BIND_PORT=3870
PCSCF_BIND_PORT=3871

# UE Networks (for routing)
UE_IPV4_IMS=10.46.0.0/16
UE_IPV4_INTERNET=10.45.0.0/16
```

## Next Steps

After IMS is running:
1. Configure your native SMF with IMS DNN and P-CSCF info
2. Add subscriber IMS credentials in PyHSS
3. Configure UE with IMS settings (IMPI, IMPU, domain)
4. Test IMS registration
5. Test VoNR calls between UEs
