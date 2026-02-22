# Native Open5GS + Standalone IMS VoNR Setup - Quick Reference

## System Configuration Summary

### Network Configuration
- **5G Core Network**: 192.168.50.0/24 (WiFi hotspot on wlp4s0)
- **IMS Docker Network**: 172.22.0.0/24 (br-ims)
- **Internet PDU**: 10.45.0.0/16 (ogstun)
- **IMS PDU**: 10.46.0.0/16 (ogstun2)

### Key IP Addresses
- **AMF**: 192.168.50.2
- **SMF**: 192.168.50.4
- **UPF**: 192.168.50.7
- **DNS**: 192.168.50.15 (also on 10.46.0.1 for IMS)
- **P-CSCF**: 192.168.50.21 (host network)
- **RTPEngine**: 192.168.50.16 (host network)
- **PyHSS**: 172.22.0.18 (IMS network)
- **ICSCF**: 172.22.0.19 (IMS network)
- **SCSCF**: 172.22.0.20 (IMS network)

### Subscriber Configuration
- **IMSI**: 262010000071630
- **MSISDN**: 1234567891
- **Ki**: 9CC9FEB9781836A846ABDAC37D5F0F4B
- **OPc**: 08A2E68EC6E4F690C9CEAF048D741A52
- **AMF**: 8000

## Starting the System

### After Reboot
```bash
sudo /usr/local/bin/start-ims-system.sh
```

This script will:
1. Start all Open5GS services
2. Configure ogstun2 interface
3. Start IMS Docker containers
4. Restart CSCF components to establish Diameter connections

### Manual Startup (if needed)

```bash
# 1. Start Open5GS
sudo systemctl start open5gs-nrfd
sudo systemctl start open5gs-scpd open5gs-amfd open5gs-smfd open5gs-upfd
sudo systemctl start open5gs-ausfd open5gs-udmd open5gs-udrd open5gs-pcfd

# 2. Setup ogstun2
sudo systemctl start ogstun2-setup.service

# 3. Start IMS
cd /etc/open5gs/IMS
docker-compose -f ims-standalone-deploy.yaml up -d

# 4. Wait 10 seconds, then restart CSCF
docker restart ims_icscf ims_scscf
```

## Verification Commands

### Check Open5GS Status
```bash
systemctl status open5gs-amfd open5gs-smfd open5gs-upfd
```

### Check IMS Containers
```bash
docker ps | grep ims_
```

### Check Interfaces
```bash
ip addr show ogstun2  # Should show 10.46.0.1/16
ip addr show ogstun   # Should show 10.45.0.1/16
```

### Check IMS Registration
```bash
# P-CSCF logs (should show REGISTER messages)
docker logs ims_pcscf --tail 50 | grep REGISTER

# SCSCF logs
docker logs ims_scscf --tail 30

# PyHSS logs
docker logs ims_pyhss --tail 30
```

### Monitor IMS Traffic
```bash
# Watch ogstun2 for IMS traffic
sudo tcpdump -i ogstun2 -n not multicast

# Watch for SIP signaling
sudo tcpdump -i any port 5060 -n
```

## Troubleshooting

### If IMS registration fails:

1. **Check ogstun2 is up**:
   ```bash
   sudo ip link set ogstun2 up
   sudo ip addr add 10.46.0.1/16 dev ogstun2
   ```

2. **Restart PyHSS and CSCF**:
   ```bash
   docker restart ims_pyhss
   sleep 15
   docker restart ims_icscf ims_scscf
   ```

3. **Check DNS resolution from IMS network**:
   ```bash
   dig @10.46.0.1 pcscf.ims.mnc001.mcc262.3gppnetwork.org
   ```

4. **Verify subscriber in PyHSS**:
   ```bash
   docker exec ims_mysql mysql -u root -proot ims_hss_db -e "SELECT imsi, msisdn, ifc_path, scscf_realm FROM ims_subscriber WHERE imsi='262010000071630';"
   ```

### If UE doesn't get IMS session:

1. **Check SMF DNS configuration** (should be 10.46.0.1):
   ```bash
   grep -A5 "dnn: ims" /etc/open5gs/smf.yaml
   ```

2. **Restart SMF**:
   ```bash
   sudo systemctl restart open5gs-smfd
   ```

## Important Files

- **SMF Config**: `/etc/open5gs/smf.yaml`
- **IMS Deployment**: `/etc/open5gs/IMS/ims-standalone-deploy.yaml`
- **IMS Environment**: `/etc/open5gs/IMS/.env`
- **Startup Script**: `/usr/local/bin/start-ims-system.sh`
- **ogstun2 Service**: `/etc/systemd/system/ogstun2-setup.service`
- **Iptables Rules**: `/etc/iptables/rules.v4` (auto-restored on boot)

## Database Locations

- **Open5GS Subscriber DB**: MongoDB (native)
- **IMS HSS DB**: MySQL in `ims_mysql` container
  - Database: `ims_hss_db`
  - Volume: `ims_dbdata` (persistent)

## Key Configuration Points

1. **SMF** sends DNS=10.46.0.1 to IMS UE (not 192.168.50.15)
2. **PyHSS** subscriber must have:
   - `ifc_path` = 'default_ifc.xml'
   - `scscf_realm` = 'ims.mnc001.mcc262.3gppnetwork.org'
   - Valid `sqn` value (not NULL)
3. **iptables** forwarding between br-ims, ogstun2, and wlp4s0
4. **ogstun2** must be up with 10.46.0.1/16 before UE registration
