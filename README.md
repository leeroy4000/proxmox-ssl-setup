# Proxmox VE SSL/TLS Certificate Setup with Let's Encrypt & Cloudflare

**Automated SSL certificate management for Proxmox Virtual Environment using Let's Encrypt and Cloudflare DNS validation.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Why This Guide?

By default, Proxmox uses a self-signed SSL certificate, which triggers browser security warnings and can't be verified. This guide eliminates those warnings by implementing trusted SSL certificates from Let's Encrypt that automatically renew.

**Benefits:**
- ✅ No more browser security warnings
- ✅ Trusted certificates from Let's Encrypt
- ✅ Automatic renewal every 60 days
- ✅ DNS validation (no need to expose port 80)
- ✅ Works behind firewalls and NAT

**Use Cases:**
- Home lab Proxmox servers accessed remotely
- Small business virtualization environments  
- Development/testing infrastructure
- Any Proxmox installation requiring secure HTTPS access

---

## Overview

This setup uses:  
- **Let's Encrypt** for free, trusted SSL certificates
- **Cloudflare DNS validation** to prove domain ownership
- **Built-in ACME client** in Proxmox VE (version 6.1+)
- **Automatic certificate renewal** every 60 days

---

## Getting Started

### First Time? Start Here

**What you'll need:**
- A computer to connect from (Windows, Mac, or Linux)
- Your Proxmox server's IP address
- Root password for Proxmox

### Step 1: Connect to Your Proxmox Server via SSH

#### On Windows:
1. Open **PowerShell** or download **PuTTY**
2. If using PowerShell, type:
   ```powershell
   ssh root@YOUR_PROXMOX_IP
   ```
   Replace `YOUR_PROXMOX_IP` with your actual Proxmox IP (e.g., `192.168.1.100`)
3. When prompted "Are you sure you want to continue connecting?", type `yes`
4. Enter your root password when prompted

#### On Mac or Linux:
1. Open **Terminal**
2. Type:
   ```bash
   ssh root@YOUR_PROXMOX_IP
   ```
   Replace `YOUR_PROXMOX_IP` with your actual Proxmox IP (e.g., `192.168.1.100`)
3. When prompted "Are you sure you want to continue connecting?", type `yes`
4. Enter your root password when prompted

**How to find your Proxmox IP:**
- Log into the Proxmox web interface
- Look at the URL bar - it's the part before `:8006`
- Or click on your node name → System → Network

**You're connected when you see:**
```
root@pve:~#
```

### Step 2: Download and Run the Validator

Now that you're connected via SSH, copy and paste these commands:

```bash
# Download the validator script
wget https://raw.githubusercontent.com/leeroy4000/proxmox-ssl-setup/main/proxmox-ssl-validator.sh

# Make it executable
chmod +x proxmox-ssl-validator.sh

# Run pre-installation checks
./proxmox-ssl-validator.sh --pre-check
```

**What these commands do:**
- `wget` downloads the script from GitHub
- `chmod +x` makes the script executable (runnable)
- `./proxmox-ssl-validator.sh --pre-check` runs the validation

The script will ask you for:
- Your Cloudflare API Token (from Step 1 below)
- Your Cloudflare Zone ID (from Step 2 below)
- Your domain name (e.g., `example.com`)
- Your Proxmox subdomain (e.g., `proxmox.example.com`)

---

## Quick Start

### Overview of the Process

1. **Connect to Proxmox** (via SSH - see "Getting Started" above)
2. **Run pre-checks** to validate your setup is ready
3. **Get Cloudflare credentials** (API token and Zone ID)
4. **Create DNS record** for your Proxmox server
5. **Configure certificates in Proxmox web interface** (GUI steps)
6. **Run post-checks** to verify everything works

### 1. Connect and Run Pre-Checks

**First time?** See the "Getting Started" section above for detailed SSH instructions.

**Already connected via SSH?** Run:

```bash
./proxmox-ssl-validator.sh --pre-check
```

This validates:
- Proxmox version compatibility
- Internet connectivity
- Cloudflare credentials (you'll need these from steps below)
- DNS configuration
- Port accessibility

### 2. Get Your Cloudflare Credentials

You'll need these for the pre-check script and for Proxmox configuration.

**See Steps 1-2 in the detailed setup below** for how to get:
- Cloudflare API Token
- Cloudflare Zone ID

### 3. Follow the Manual Setup Steps

Complete **Steps 1-7** in the "Manual Setup" section below (using the Proxmox web interface).

### 4. Verify Installation

**Connect to Proxmox via SSH again** and run:

```bash
./proxmox-ssl-validator.sh --post-check
```

This verifies:
- Certificate installation
- Certificate validity
- Auto-renewal configuration
- Web interface accessibility

---

## Prerequisites

- Proxmox VE 6.1 or newer
- Domain managed by Cloudflare
- Subdomain pointing to Proxmox (e.g., `proxmox.yourdomain.com`)
- Cloudflare API Token with DNS edit permissions
- Cloudflare Zone ID for your domain

---

## Manual Setup (Detailed Steps)

The following steps are performed in the **Proxmox web interface** (not SSH).  
Access it by opening a browser and going to: `https://YOUR_PROXMOX_IP:8006`

### Step 1: Get Cloudflare API Token

1. Log into **Cloudflare Dashboard**
2. Go to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use **Edit zone DNS** template
5. Configure permissions:
   - **Permissions**: 
     - Zone → DNS → Edit
     - Zone → Zone → Read (recommended)
   - **Zone Resources**: Include → Specific zone → `yourdomain.com`
6. Click **Continue to summary** → **Create Token**
7. **Copy the API token** (save it - you won't see it again!)

---

## Step 2: Get Cloudflare Zone ID

1. In **Cloudflare Dashboard**, click on your domain
2. Go to **Overview** page
3. Scroll down on the right side
4. Copy the **Zone ID** (looks like: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`)
5. Save this - you'll need it for Proxmox

---

## Step 3: Create DNS Record

1. In **Cloudflare Dashboard** → **DNS**
2. Add new **A record**:
   - **Name**: `proxmox` (or `pve`, `hypervisor`, etc.)
   - **IPv4 address**: Your public IP address
   - **Proxy status**: Orange cloud **OFF** ⚪ (gray cloud)
   - **TTL**: Auto
3. Click **Save**

Result: `proxmox.yourdomain.com`

> **Important**: Disable Cloudflare proxy (gray cloud) for Proxmox. The orange cloud (proxy enabled) will break the connection.

---

## Step 4: Configure ACME Account in Proxmox

1. Log into **Proxmox web interface** (`https://proxmox-ip:8006`)
2. Click on **Datacenter** (top left in tree)
3. Navigate to **ACME** section
4. Click **Add** button under "Accounts"
5. Configure account: 
   - **Account Name**: `letsencrypt-production`
   - **E-Mail**: Your email address
   - **ACME Directory**: `Let's Encrypt V2`
   - **Accept TOS**: ✅ Check the box
6. Click **Register**
7. Should see success message

---

## Step 5: Add Cloudflare DNS Challenge Plugin

1. Still in **Datacenter** → **ACME**
2. Switch to **Challenge Plugins** tab
3. Click **Add**
4. Configure plugin:
   - **Plugin ID**: `cloudflare`
   - **DNS API**: `Cloudflare Managed DNS` (or `dns_cf`)
   - **API Data**: Enter in this format:
     ```
     CF_Token=your_cloudflare_api_token_here
     CF_Zone_ID=your_zone_id_here
     ```
     ⚠️ **Both are required!** Replace with your actual token and Zone ID from Steps 1 & 2
5. Click **Add**

---

## Step 6: Configure Certificate for Proxmox Node

1. In the tree, click on your **Proxmox node** (e.g., `pve`)
2. Go to **System** → **Certificates**
3. Click **Add** button under "ACME"
4. Configure domain:
   - **Challenge Type**: `DNS`
   - **Plugin**: `cloudflare` (select from dropdown)
   - **Domain**: `proxmox.yourdomain.com` (your full subdomain)
5. Click **Add**

---

## Step 7: Order/Issue Certificate

1. Still in **System** → **Certificates** view
2. Click **Order Certificates Now** button at the top
3. Wait 20-30 seconds for the process to complete
4. Should see success message showing certificate details
5. Web interface will automatically reload with new certificate

---

## Step 8: Verify HTTPS Works

### Option 1: Browser Test

1. **Close browser completely** (clear cache)
2. Navigate to: `https://proxmox.yourdomain.com:8006`
3. Should see:  
   - ✅ Secure lock icon
   - ✅ Valid certificate from Let's Encrypt
   - ✅ No certificate warnings
4. Click the lock icon to verify: 
   - **Issued to**: proxmox.yourdomain.com
   - **Issued by**: Let's Encrypt (R10, R11, or similar)
   - **Valid until**: ~90 days from issue date

### Option 2: Automated Validation (Recommended)

**Connect to Proxmox via SSH** (see "Getting Started" section) and run:

```bash
./proxmox-ssl-validator.sh --post-check
```

This will comprehensively test:
- Certificate installation
- Certificate validity
- Let's Encrypt issuer
- Domain name match
- Auto-renewal configuration
- HTTPS accessibility

---

## Validation Script Features

The included `proxmox-ssl-validator.sh` script provides comprehensive validation:

### Pre-Installation Mode (`--pre-check`)
- Verifies Proxmox version supports ACME
- Tests internet connectivity to Let's Encrypt
- Validates Cloudflare API credentials
- Checks DNS record configuration
- Verifies port 8006 accessibility

### Post-Installation Mode (`--post-check`)
- Confirms certificate installation
- Verifies certificate validity via HTTPS
- Checks certificate issuer (Let's Encrypt)
- Validates domain name match
- Tests auto-renewal configuration
- Confirms web interface accessibility

### Usage Examples

```bash
# Before setup - check prerequisites
./proxmox-ssl-validator.sh --pre-check

# After certificate installation - verify everything works
./proxmox-ssl-validator.sh --post-check

# Run complete validation (both modes)
./proxmox-ssl-validator.sh --full

# Show help
./proxmox-ssl-validator.sh --help
```

---

## Certificate Renewal

### Automatic Renewal
- Proxmox automatically renews certificates **30 days before expiry**
- Renewal runs via cron job
- No manual intervention needed

### Manual Renewal
If you need to renew manually:
1. Go to **Node** → **System** → **Certificates**
2. Click **Order Certificates Now**
3. New certificate will be issued and applied

### Check Certificate Status
- **Node** → **System** → **Certificates**
- Shows current certificate and expiration date

Or use command line:
```bash
pvenode cert info
```

---

## Cluster Configuration (Multiple Nodes)

If you have a Proxmox cluster with multiple nodes: 

### Option 1: Individual Certificates (Recommended)
Each node gets its own subdomain and certificate: 
- `pve1.yourdomain.com` → Node 1
- `pve2.yourdomain.com` → Node 2
- `pve3.yourdomain.com` → Node 3

Repeat Steps 3-7 for each node.

### Option 2: Subject Alternative Names (SANs)
One certificate with multiple domains:
1. When adding domains in Step 6, click **Add** multiple times
2. Add each node's domain name
3. All nodes can use the same certificate

---

## Troubleshooting

### Error: "invalid domain" or "Error add txt for domain"

**Problem**: Missing Zone ID or incorrect API token

**Solution**: 
1. Verify you added **both** `CF_Token` AND `CF_Zone_ID` to the plugin
2. Check the format in plugin data: 
   ```
   CF_Token=your_token
   CF_Zone_ID=your_zone_id
   ```
3. Verify API token has correct permissions (Zone → DNS → Edit)
4. Edit plugin: **Datacenter** → **ACME** → **Challenge Plugins** → **Edit**

**Quick validation:**
```bash
./proxmox-ssl-validator.sh --pre-check
```
This will test your Cloudflare credentials before you configure Proxmox.

### Certificate not showing as valid in browser

**Problem**: Browser cached old self-signed certificate

**Solution**: 
- Close browser completely and reopen
- Hard refresh: `Ctrl + Shift + R` (Windows/Linux) or `Cmd + Shift + R` (Mac)
- Try incognito/private window
- Try different browser
- Clear browser SSL state

### Cannot access Proxmox after certificate install

**Problem**: DNS not resolving or firewall blocking

**Solution**:
- Can still access via IP: `https://PROXMOX_IP:8006` (certificate warning is normal)
- Check DNS resolves: `nslookup proxmox.yourdomain.com`
- Verify port 8006 is open (if accessing from outside network)
- Check pfSense firewall rules if accessing through VPN

**Automated check:**
```bash
./proxmox-ssl-validator.sh --post-check
```

### ACME order fails immediately

**Problem**: Proxmox can't reach Let's Encrypt servers

**Solution**:
- Check Proxmox has internet access: `ping 8.8.8.8` from shell
- Check DNS resolution: `ping letsencrypt.org`
- Verify firewall allows outbound HTTPS (port 443)
- Check proxy settings if using one

**Automated check:**
```bash
./proxmox-ssl-validator.sh --pre-check
```

### API token permissions error

**Problem**: Token doesn't have required permissions

**Solution**:
1. Create new token in Cloudflare with these permissions:
   - Zone → DNS → Edit ✅
   - Zone → Zone → Read ✅
2. Scope to specific zone (your domain)
3. Update Proxmox plugin with new token

---

## Security Best Practices

### Access Control
- ✅ Access Proxmox through **VPN only** (most secure)
- ⚠️ If exposing to internet, use **strong passwords** and **2FA**
- ✅ Limit access by IP in pfSense firewall rules
- ✅ Use **non-standard port** (change from 8006 to something else)

### Port Forwarding
Only forward port 8006 if you need external access:
- Better: Use **VPN** and access over private network
- Alternative: Use **reverse proxy** (Caddy, nginx) on port 443

### Certificate Security
- ✅ Let's Encrypt certificates auto-renew (no expired certs!)
- ✅ Private keys stay on Proxmox server (never shared)
- ✅ Use DNS validation (no need to expose port 80)

### API Token Security
- ✅ Use **API tokens** (not Global API Key)
- ✅ Scope tokens to **specific zones only**
- ✅ Use **minimal permissions** needed (DNS Edit only)
- ✅ Rotate tokens periodically

---

## Alternative: Access via Reverse Proxy

Instead of exposing Proxmox directly, use Caddy or nginx: 

### Benefits:
- Standard HTTPS port (443) instead of 8006
- Reverse proxy handles SSL automatically
- Can add authentication layer
- Single entry point for multiple services

### Basic Caddy Config:
```
proxmox.yourdomain.com {
    reverse_proxy https://PROXMOX_INTERNAL_IP:8006 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

Then access via: `https://proxmox.yourdomain.com` (no port number!)

---

## Useful Commands

### Check certificate details from CLI:
```bash
pvenode cert info
```

### View ACME account info:
```bash
pvenode acme account list
```

### Manually trigger certificate renewal:
```bash
pvenode acme cert renew
```

### View certificate files:
```bash
ls -la /etc/pve/nodes/$(hostname)/pveproxy-ssl.*
```

### Test Cloudflare API token:
```bash
curl -X GET "https://api.cloudflare.com/client/v4/zones?name=yourdomain.com" \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json"
```

### Run validation script:
```bash
# Pre-installation checks
./proxmox-ssl-validator.sh --pre-check

# Post-installation verification
./proxmox-ssl-validator.sh --post-check
```

---

## Architecture Diagram

```
┌─────────────────┐
│   Your Browser  │
└────────┬────────┘
         │ HTTPS (Port 8006)
         │
         ▼
┌─────────────────┐      DNS Query       ┌──────────────┐
│   Cloudflare    │◄────────────────────►│ DNS Resolver │
│   DNS Server    │                      └──────────────┘
└────────┬────────┘
         │ Resolves to Proxmox IP
         │
         ▼
┌─────────────────────────────────────────┐
│         Proxmox VE Server               │
│  ┌───────────────────────────────────┐  │
│  │  Built-in ACME Client             │  │
│  │  • Requests cert from Let's Enc.  │  │
│  │  • Uses Cloudflare DNS validation │  │
│  │  • Auto-renews every 60 days      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  SSL Certificate (Let's Encrypt)  │  │
│  │  • Trusted by all browsers        │  │
│  │  • 90-day validity                │  │
│  │  • Stored in /etc/pve/            │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
         ▲
         │ ACME Challenge
         │
┌────────┴────────┐
│  Let's Encrypt  │
│  CA Servers     │
└─────────────────┘
```

---

## Project Background

This setup was developed for my home lab environment running Proxmox VE on multiple nodes. The goal was to eliminate browser security warnings while maintaining secure access via VPN and ensuring certificates automatically renew.

**Environment:**
- 3-node Proxmox cluster
- pfSense firewall with site-to-site VPN
- Cloudflare-managed domains
- Remote access via WireGuard VPN

The validation script was added to ensure reliable certificate deployment and to catch configuration issues early in the setup process.

---

## Files in This Repository

- `README.md` - This comprehensive setup guide
- `proxmox-ssl-validator.sh` - Automated validation script
  - Pre-installation checks
  - Post-installation verification
  - Certificate validation
  - Auto-renewal testing

---

## Contributing

Issues and pull requests welcome! If you find bugs or have suggestions for improving the setup process or validation script, please open an issue.

---

## License

MIT License - Feel free to use and modify for your own projects.

---

## Reference Links

- **Proxmox Wiki**: https://pve.proxmox.com/wiki/Certificate_Management
- **Let's Encrypt**: https://letsencrypt.org/
- **Cloudflare API Docs**: https://developers.cloudflare.com/api/
- **ACME Protocol**: https://tools.ietf.org/html/rfc8555

---

## Summary

✅ **Proxmox now has valid SSL certificate from Let's Encrypt**  
✅ **Auto-renewal every 60 days (30 days before expiry)**  
✅ **DNS validation via Cloudflare (no ports to open)**  
✅ **Secure access to Proxmox web interface**  
✅ **Automated validation and verification**

---

**Last Updated**: January 2026  
**Tested On**: Proxmox VE 7.x, 8.x  
**Author**: Lee Roy
