# OpenCloud for Unraid

> Complete Unraid templates and configuration for deploying OpenCloud with document editing (Collabora Online) and calendar/contacts (Radicale) integration.

---

## 🌟 What's Included

| Component | Description |
|-----------|-------------|
| **OpenCloud** | Self-hosted cloud storage platform |
| **Collabora Online** | Real-time document editing (Word, Excel, PowerPoint) |
| **WOPI Server** | Bridges OpenCloud and Collabora for seamless integration |
| **Radicale** *(Optional)* | CalDAV/CardDAV server for calendar and contacts sync |

---

## 📋 Prerequisites

### Required Infrastructure

- ✅ **Unraid** 7.2.0 or newer
- ✅ **SWAG** reverse proxy ([linuxserver/swag](https://docs.linuxserver.io/general/swag))
- ✅ **Valid SSL certificates** (Let's Encrypt via SWAG)
- ✅ **Three subdomains** configured in DNS:
  - `opencloud.yourdomain.com`
  - `collabora.yourdomain.com`
  - `wopiserver.yourdomain.com`

### Recommended Setup

- 📦 **Community Applications** plugin installed
- 🔧 **User Scripts** plugin (for automated setup)
- 💾 Minimum **4GB RAM** allocated for all containers
- 💿 **20GB storage** space

---

## 🔧 Platform-Specific Configuration

### Pangolin Users

If you're running this on a **Pangolin server** with Traefik as your reverse proxy, you need to adjust your Traefik configuration:

#### Required Traefik Configuration

Add the following options to your **Traefik static configuration** in Pangolin:

```yaml
# In your Traefik static config (traefik.yml or via Pangolin UI)
entryPoints:
  web:
    address: :80
  websecure:
    address: :443
    http:
      middlewares:
        - crowdsec@file
        - nextcloud-hstsfile
  tls:
    certResolver: letsencrypt
    encodedCharacters:
      allowEncodedSlash: true
      allowEncodedHash: true
      allowEncodedQuestionMark: true
transport:
  respondingTimeouts:
    readTimeout: 30m
```

**Key settings for OpenCloud:**
- `allowEncodedSlash: true` - Required for WebDAV paths in CalDAV/CardDAV
- `allowEncodedQuestionMark: true` - Required for query parameters in Collabora

#### Steps to Apply:

1. **Access Pangolin UI** → Navigate to Traefik settings
2. **Edit static configuration** → Add the `encodedCharacters` section under `tls`
3. **Restart Traefik** → Apply changes via Pangolin interface
4. **Verify** → Check Traefik logs for successful restart

> **Note:** These settings are crucial for proper CalDAV/CardDAV functionality and Collabora document editing. Without them, you may experience authentication issues or broken file paths.

---

## 🚀 Quick Start

### Step 1: Run Pre-Installation Script

1. Install **User Scripts** plugin from Community Applications
2. Add a new script: `Settings` → `User Scripts` → `Add New Script`
3. Name it: `OpenCloud Setup`
4. Paste the contents of `Opencloud_pre_install_script.txt`
5. **Edit these variables at the top:**
   ```bash
   # Enable/disable features
   ENABLE_COLLABORA="true"    # Document editing
   ENABLE_RADICALE="true"     # Calendar/contacts
   
   # Your domains (no https://)
   OCIS_DOMAIN="opencloud.yourdomain.com"
   COLLABORA_DOMAIN="collabora.yourdomain.com"
   WOPISERVER_DOMAIN="wopiserver.yourdomain.com"
   
   # Installation Paths
   OCL_BASE="/mnt/user/appdata/opencloud"
   COL_BASE="/mnt/user/appdata/collabora"
   RAD_BASE="/mnt/user/appdata/radicale"
   ```
6. Click `Run Script` → `Run`
7. Check output: `View Log` to verify success

### Step 2: Configure SWAG Proxy

Copy the three configuration files to your SWAG container:

1. **OpenCloud config:**
   ```bash
   # Copy to: /mnt/user/appdata/swag/nginx/proxy-confs/
   opencloud.conf → opencloud.subdomain.conf
   ```

2. **Collabora config:**
   ```bash
   # Copy to: /mnt/user/appdata/swag/nginx/proxy-confs/
   collabora.conf → collabora.subdomain.conf
   ```

3. **WOPI Server config:**
   ```bash
   # Copy to: /mnt/user/appdata/swag/nginx/proxy-confs/
   collaboration.conf → wopiserver.subdomain.conf
   ```

4. **Restart SWAG:**
   ```bash
   docker restart swag
   ```

### Step 3: Install Unraid Templates

1. **Download templates** from this repository:
   - `my-opencloud.xml`
   - `my-collabora.xml`
   - `my-collaboration.xml`
   - `my-opencloud-radicale.xml` (if using Radicale)

2. **Copy to Unraid:**
   ```bash
   /boot/config/plugins/dockerMan/templates-user/
   ```

### Step 4: Configure Templates

For each template, update these key settings:

#### OpenCloud Container
- **Network:** `opencloud-net` (created by script)
- **OC_URL:** `https://opencloud.yourdomain.com`
- **IDM_ADMIN_PASSWORD:** Set a secure password
- **COLLABORA_DOMAIN:** `collabora.yourdomain.com`

#### Collabora Container
- **Network:** `opencloud-net`
- **aliasgroup1:** `https://wopiserver.yourdomain.com:443`
- **username:** `admin`
- **password:** Set a secure password
- **extra_params:** Update `net.frame_ancestors` and `net.lok_allow.host[14]` with your OpenCloud domain

#### Collaboration Container
- **Network:** `opencloud-net`
- **MICRO_REGISTRY_ADDRESS:** OpenCloud container IP:9233 (e.g., `192.168.178.10:9233`)
- **COLLABORATION_WOPI_SRC:** `https://wopiserver.yourdomain.com`
- **COLLABORATION_APP_ADDR:** `https://collabora.yourdomain.com`
- **OC_URL:** `https://opencloud.yourdomain.com`

#### Radicale Container (Optional)
- **Network:** `opencloud-net`
- **Data Directory:** `/mnt/user/appdata/radicale/data`
- **Config Directory:** `/mnt/user/appdata/radicale/config`

### Step 5: Start Containers

**IMPORTANT: Start in this exact order with delays between each:**

1. **Start OpenCloud**
   ```
   Wait 2-3 minutes for initialization
   Check logs: docker logs opencloud
   Look for: "all services are ready"
   ```

2. **Start Collabora**
   ```
   Wait 1-2 minutes for startup
   Check logs: docker logs collabora
   Look for: "Listening on port 9980"
   ```

3. **Start Collaboration**
   ```
   Wait 30 seconds
   Check logs: docker logs collaboration
   Look for: "successfully registered"
   ```

4. **Start Radicale** (if enabled)
   ```
   Wait 30 seconds
   Check logs: docker logs radicale
   ```

## 📝 Post-Installation

### Initial Login

1. Navigate to `https://opencloud.yourdomain.com`
2. Login with:
   - Username: `admin`
   - Password: (the one you set in IDM_ADMIN_PASSWORD)

### Test Document Editing

1. Upload a `.docx` or `.xlsx` file
2. Click to open it
3. Should open in Collabora Online editor
4. Try editing and saving

### Setup CalDAV/CardDAV (Radicale)

1. **In OpenCloud web interface:**
   - Go to `Settings` → `Personal` → `Security`
   - Click `+ New app password`
   - Name it: `CalDAV Client`
   - Copy the generated token

2. **Configure your client:**
   - **CalDAV URL:** `https://opencloud.yourdomain.com/caldav/`
   - **CardDAV URL:** `https://opencloud.yourdomain.com/carddav/`
   - **Username:** Your OpenCloud username
   - **Password:** The app token you just created

3. **Supported clients:**
   - **iOS:** Built-in Calendar and Contacts apps
   - **Android:** DAVx⁵ (recommended)
   - **Desktop:** Thunderbird with Lightning
   - **macOS:** Built-in Calendar and Contacts apps

## 🔧 Configuration Details

### Network Architecture

All containers run on a custom Docker network (`opencloud-net`) for internal communication:

```
Internet
    ↓
SWAG Proxy (443)
    ↓
┌─────────────────────────────────┐
│     opencloud-net network       │
│                                 │
│  OpenCloud:9200                 │
│  Collabora:9980                 │
│  Collaboration:9300             │
│  Radicale:5232                  │
└─────────────────────────────────┘
```

### Key Environment Variables

#### OpenCloud
- `OC_URL`: Your public OpenCloud URL
- `OC_INSECURE`: Set to `true` for self-signed certs
- `PROXY_HTTP_ADDR`: Internal HTTP listener (0.0.0.0:9200)
- `IDM_ADMIN_PASSWORD`: Admin account password

#### Collabora
- `aliasgroup1`: WOPI server URL for CORS
- `username/password`: Admin console credentials
- `extra_params`: Security and frame settings

#### Collaboration (WOPI)
- `MICRO_REGISTRY_ADDRESS`: OpenCloud NATS address
- `COLLABORATION_WOPI_SRC`: Public WOPI URL
- `COLLABORATION_APP_ADDR`: Public Collabora URL

### File Locations

```
/mnt/user/appdata/opencloud/
├── config/
│   ├── csp.yaml                 # Content Security Policy
│   ├── banned-password-list.txt # Password restrictions
│   └── proxy.yaml               # Radicale integration (optional)
├── data/                        # User files and metadata
└── apps/                        # Web extensions

/mnt/user/appdata/collabora/
└── config/                      # Collabora configuration

/mnt/user/appdata/radicale/
├── config/
│   ├── config                   # Radicale main config
│   └── rights                   # Access permissions
└── data/                        # Calendar/contact data
```

## 🐛 Troubleshooting

### OpenCloud won't start
```bash
# Check logs
docker logs opencloud

# Common issues:
# - Missing csp.yaml or banned-password-list.txt
#   Solution: Re-run pre-install script
# - Port conflict on 9200
#   Solution: Stop conflicting container
```

### Collabora can't connect
```bash
# Check logs
docker logs collabora

# Common issues:
# - Wrong aliasgroup1 URL
#   Solution: Must be https://wopiserver.yourdomain.com:443
# - CORS errors in browser console
#   Solution: Check extra_params frame_ancestors setting
```

### Documents won't open
```bash
# Check collaboration logs
docker logs collaboration

# Common issues:
# - "app provider not found"
#   Solution: Restart collaboration container
# - WOPI authentication failures
#   Solution: Check MICRO_REGISTRY_ADDRESS points to OpenCloud IP
```

### Radicale not syncing
```bash
# Check logs
docker logs radicale

# Common issues:
# - proxy.yaml not mounted in OpenCloud
#   Solution: Add mount to OpenCloud template and restart
# - Authentication failures
#   Solution: Use app tokens, not main password
# - Wrong URLs in client
#   Solution: URLs must be https://opencloud.domain.com/caldav/ (with trailing slash)
```

### Desktop app SSL errors
```bash
# If OpenCloud desktop client shows SSL errors:
# In opencloud.conf, ensure these lines exist:

# DON'T set these (causes desktop app issues):
# proxy_set_header X-Forwarded-Proto https;
# proxy_set_header X-Forwarded-Ssl on;

# Desktop app needs to see actual TLS connection
```

### Pangolin/Traefik Issues

If you're experiencing issues with CalDAV/CardDAV or Collabora on Pangolin:

1. **Verify Traefik configuration:**
   ```bash
   # Check if encoded characters are allowed
   grep -A5 "encodedCharacters" /path/to/traefik.yml
   ```

2. **Common symptoms of missing configuration:**
   - CalDAV/CardDAV URLs return 404 errors
   - Collabora documents fail to load
   - Authentication loops in sync clients

3. **Solution:** Ensure `allowEncodedSlash` and `allowEncodedQuestionMark` are set to `true` in Traefik static config (see Platform-Specific Configuration above)

## 🔒 Security Considerations

### Production Recommendations

1. **Change default passwords:**
   - OpenCloud admin password
   - Collabora admin password

2. **Enable password policies:**
   - Configured in OpenCloud template
   - Minimum 8 characters, mixed case, numbers, special chars

3. **Public share security:**
   - Require passwords for public shares (enabled by default)

4. **Network isolation:**
   - Keep `opencloud-net` internal only
   - Only SWAG should expose ports externally

5. **Radicale security:**
   - Always use app tokens for CalDAV/CardDAV clients
   - Never share your main OpenCloud password with sync clients

## 📚 Additional Resources

- **OpenCloud Documentation:** https://docs.opencloud.eu/
- **Collabora Documentation:** https://www.collaboraoffice.com/code/
- **SWAG Documentation:** https://docs.linuxserver.io/general/swag
- **Radicale Documentation:** https://radicale.org/v3.html
- **Pangolin Documentation:** https://pangolin.com/docs (for Traefik configuration)

## 🤝 Contributing

Issues and pull requests welcome! Please test thoroughly before submitting.

## 📄 License

These templates are provided as-is. OpenCloud, Collabora, and Radicale are subject to their respective licenses.

## ⭐ Support

If this helped you, consider:
- ⭐ Starring this repository
- 📢 Sharing with others running Unraid or Pangolin
- 🐛 Reporting issues you encounter

---

**Template Version:** 2024.12  
**Compatible with:** Unraid 7.2.0+, OpenCloud Rolling, Collabora Latest  
**Platform Support:** Unraid (SWAG), Pangolin (Traefik)
