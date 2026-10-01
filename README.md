# OpenCloud for Unraid — Templates, SWAG configs and setup scripts

> Complete Unraid templates and configuration for deploying **OpenCloud 7.5+ / 8.x** with document editing (Collabora Online or Euro-Office), real-time collaborative editing (Yjs) and calendar/contacts (Radicale).

---

## 🌟 What's Included

| Component | Description |
|-----------|-------------|
| **OpenCloud** | Self-hosted cloud storage platform |
| **Collabora Online** | Document editing (Word, Excel, PowerPoint) — officially supported |
| **Euro-Office** | Document editing, OnlyOffice fork — community supported only |
| **Yjs** *(Optional)* | Real-time collaborative editing in the built-in Editor |
| **Radicale** *(Optional)* | CalDAV/CardDAV server for calendar and contacts sync |
| **Pocket-ID** *(Optional)* | OIDC provider with passkey login, replaces the built-in IDM |

---

## ⚠️ Architecture: OpenCloud 7.5 and newer

This is the single most important thing to understand, and it changed in 7.5:

**There is no separate WOPI/Collaboration container any more.** The collaboration service
runs *inside* the OpenCloud container (`OC_ADD_RUN_SERVICES=collaboration`) and is served
on the **main OpenCloud domain** under `/wopi` and `/collaboration`.

That means:

- ❌ No `wopiserver.yourdomain.com` subdomain
- ❌ No `opencloud-collaboration.xml` template
- ✅ Two subdomains only: `opencloud.*` and your web office (`collabora.*` or `euro-office.*`)

---

## 📦 Repository Layout

```
templates/
  opencloud.xml                  # OpenCloud container
  opencloud-for-euro-office.xml  # OpenCloud container, Euro-Office variant
  opencloud-collabora.xml        # Collabora container
  opencloud-euro-office.xml      # Euro-Office container
  opencloud-yjs.xml              # Yjs relay (optional)
  opencloud-radicale.xml         # Radicale (optional)
  Pocket-ID.xml                  # Pocket-ID OIDC (optional)
  docker-icons/                  # Icons used by the templates

SWAG-conf/
  opencloud.conf              # → opencloud.subdomain.conf
  collabora.conf              # → collabora.subdomain.conf
  euro-office.conf            # → euro-office.subdomain.conf

scripts/
  opencloud_pre_install_script.sh   # generates configs + templates
  opencloud_v75_migration.sh        # migrates an existing install to 7.5+/8.x
  opencloud-enable-yjs.sh           # retrofits Yjs on an install created before
```

---

## 📋 Prerequisites

### Required Infrastructure

- ✅ **Unraid** 7.2.0 or newer
- ✅ **SWAG** reverse proxy ([linuxserver/swag](https://docs.linuxserver.io/general/swag))
- ✅ **Valid SSL certificates** (Let's Encrypt via SWAG)
- ✅ **Two subdomains** configured in DNS:
  - `opencloud.yourdomain.com`
  - `collabora.yourdomain.com` — or `euro-office.yourdomain.com`

Optional: `pocket-id.yourdomain.com` if you use Pocket-ID.

### Recommended Setup

- 📦 **Community Applications** plugin installed
- 🔧 **User Scripts** plugin (for the setup script)
- 💾 Minimum **4GB RAM** for all containers (add 2–4GB if you run Euro-Office)
- 💿 **20GB storage** space

---

## 🔄 Upgrading an existing install from 7.x to 8.x

OpenCloud 8.x is a **rolling release** and upstream describes it as *not intended for
production environments*. Read the release notes before you upgrade.

The migration is otherwise one command, but it is **mandatory** — the search index format
changed, and skipping it leaves search broken:

```bash
docker exec OpenCloud opencloud search index --all-spaces --force-rescan --insecure
```

Notes:

- `--insecure` is needed because `OC_GRPC_CLIENT_TLS_MODE` defaults to `off`.
- Once search works again, remove the **old** index so it is not rebuilt:
  - Bleve: delete the unversioned `bleve` directory, keep `bleve-v5`
  - OpenSearch: `curl -X DELETE "http://localhost:9200/opencloud-resources"`
- Check for configuration drift with `docker exec OpenCloud opencloud init --diff`.
  Upstream also versions the index name (`opencloud-resources-v5`).

`scripts/opencloud_v75_migration.sh` automates this for Unraid templates.

---

## 🔧 Platform-Specific Configuration

### Pangolin Users

If you're running this on a **Pangolin server** with Traefik as your reverse proxy, you need to adjust your Traefik configuration:

#### Required Traefik Configuration

Add the following options to your **Traefik static configuration** in Pangolin:

```yaml
# In your Traefik static config (traefik.yml or via Pangolin UI)
entryPoints:
  web:...
    ...
  tls:
    certResolver: letsencrypt
    encodedCharacters:
   ❗ allowEncodedSlash: true
      allowEncodedHash:  true
   ❗ allowEncodedQuestionMark: true
transport:
  respondingTimeouts:
    ...
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

### Step 1: Run the setup script

1. Install the **User Scripts** plugin from Community Applications
2. `Settings` → `User Scripts` → `Add New Script`, name it `OpenCloud Setup`
3. Paste the contents of `scripts/opencloud_pre_install_script.sh`
4. **Edit these variables at the top:**

   ```bash
   # Which web office (MUTUALLY EXCLUSIVE - pick one)
   ENABLE_COLLABORA="true"        # Collabora Online (officially supported)
   ENABLE_EURO_OFFICE="false"     # Euro-Office (community supported only)

   # Other features
   ENABLE_RADICALE="true"         # Calendar/Contacts (CalDAV/CardDAV)
   ENABLE_YJS="true"              # Real-time collaborative editing (8.x)
   ENABLE_POCKET_ID="false"       # Pocket-ID OIDC (passkeys)

   # Your domains (no https://)
   OCIS_DOMAIN="opencloud.yourdomain.com"
   COLLABORA_DOMAIN="collabora.yourdomain.com"

   # Optional: generate the SWAG configs as well
   GENERATE_SWAG_CONFS="true"

   # true = show the plan, write nothing. Flip to "false" to apply.
   DRY_RUN="true"
   ```

5. `Run Script` → `Run` — it starts in **DRY RUN**, so nothing is written yet.
   Review the output under `View Log`, then set `DRY_RUN="false"` and run again.

The script creates the Docker network, the appdata folders, `csp.yaml`, `proxy.yaml`
(including the `/yjs` route), the secrets and the Unraid XML templates. It does **not**
create or start any container.

> **Upgrading instead of installing?** Use `scripts/opencloud_v75_migration.sh`.

### Step 2: Configure SWAG

Copy the configs to your SWAG container and **rename them**:

| From this repo | Copy to `.../swag/nginx/proxy-confs/` as |
|---|---|
| `SWAG-conf/opencloud.conf` | `opencloud.subdomain.conf` |
| `SWAG-conf/collabora.conf` | `collabora.subdomain.conf` |
| `SWAG-conf/euro-office.conf` | `euro-office.subdomain.conf` |

The `server_name` must match your subdomain (`opencloud.*`, `collabora.*`).

Then:

```bash
docker restart swag
```

The configs use the container names as upstreams, so **SWAG must share the
`opencloud-net` Docker network**. If your SWAG reaches containers through the host
instead, replace `set $upstream_app ...` with your Unraid IP.

### Step 3: Install the Unraid templates

Copy the templates you need to `/boot/config/plugins/dockerMan/templates-user/`:

| Template | When |
|---|---|
| `templates/opencloud.xml` | using Collabora (default) |
| `templates/opencloud-for-euro-office.xml` | using Euro-Office — import this **instead of** `opencloud.xml` |
| `templates/opencloud-collabora.xml` | using Collabora |
| `templates/opencloud-euro-office.xml` | using Euro-Office |
| `templates/opencloud-yjs.xml` | `ENABLE_YJS="true"` |
| `templates/opencloud-radicale.xml` | `ENABLE_RADICALE="true"` |
| `templates/Pocket-ID.xml` | `ENABLE_POCKET_ID="true"` |

### Step 4: Configure the templates

#### OpenCloud Container
- **Network:** `opencloud-net`
- **OC_URL:** `https://opencloud.yourdomain.com`
- **IDM_ADMIN_PASSWORD:** set a strong password (leave empty to let OpenCloud
  generate one — it is printed in the container log on first start)
- **OC_ADD_RUN_SERVICES:** must contain `collaboration`
- **WEB_OPTION_YJS_SERVER_URL:** `wss://opencloud.yourdomain.com/yjs`
- The `COLLABORATION_APP_*` fields must match your web office — see below

#### Collabora Container
- **Network:** `opencloud-net`
- **aliasgroup1:** `https://opencloud.yourdomain.com` — in 7.5+ WOPI is served by
  OpenCloud, so this is the **OpenCloud URL**, not a wopiserver URL
- **WOPI Proof Key:** generate it once on the host (see below)
- **username / password:** Collabora admin console. Leave the password empty to
  disable the console
- **extra_params:** `net.frame_ancestors` and `net.lok_allow.host[14]` must be your
  OpenCloud domain

#### Euro-Office Container
- **Network:** `opencloud-net`
- **WOPI_ENABLED:** `true`
- **JWT_SECRET:** generate one with `openssl rand -hex 32`

#### Yjs Container
- **Network:** `opencloud-net`
- **OPENCLOUD_URL:** `http://OpenCloud:9200`
- **PORT:** `1234` — must match the `/yjs` route in OpenCloud's `proxy.yaml`
- No volume, no port to publish: it is a stateless WebSocket relay

#### Radicale Container
- **Network:** `opencloud-net`
- **Data / Config Directory:** `/mnt/user/appdata/radicale/data` and `.../config`

### Step 5: Start the containers — ORDER MATTERS

**Start the web office FIRST**, then OpenCloud. This is the reverse of the pre-7.5
behaviour, and getting it wrong crash-loops OpenCloud.

1. **Start the web office** (Collabora or Euro-Office)
   ```
   Wait 1-2 minutes
   Verify: https://collabora.yourdomain.com/hosting/discovery   → must return HTTP 200
   ```
   If OpenCloud starts while the web office is unreachable, the collaboration service
   panics (`nil pointer in parseWopiDiscovery`) and takes the whole OpenCloud process
   down in a crash loop.

2. **Start OpenCloud**
   ```
   Wait 2-3 minutes for initialization
   docker logs OpenCloud   → look for "all services are ready"
   ```

3. **Start Yjs** (if enabled)
   ```
   Any time — it does not block OpenCloud. Check: docker logs YJS
   ```

4. **Start Radicale** (if enabled)
   ```
   Needs the OpenCloud container up, with proxy.yaml in its config directory
   ```

## 🧩 Choosing your web office

Import **one** web office template, and set the matching env vars in the OpenCloud
template. A ready-made Euro-Office variant is included as
`templates/opencloud-for-euro-office.xml` — import it instead of `opencloud.xml` and
nothing has to be edited by hand.

| Setting | Collabora | Euro-Office |
|---|---|---|
| `COLLABORATION_APP_NAME` | `CollaboraOnline` | `Euro-Office` |
| `COLLABORATION_APP_PRODUCT` | `Collabora` | `OnlyOffice` |
| `COLLABORATION_APP_ADDR` | `https://collabora.yourdomain.com` | `https://euro-office.yourdomain.com` |
| `COLLABORATION_APP_ICON` | `https://collabora.yourdomain.com/favicon.ico` | `https://euro-office.yourdomain.com/web-apps/apps/documenteditor/main/resources/img/favicon.ico` |
| domain variable | `COLLABORA_DOMAIN` | `EURO_OFFICE_DOMAIN` |
| `COLLABORATION_APP_PROOF_DISABLE` | *(leave unset)* | `true` |

The matching domain must also be present in the `csp.yaml` `frame-src` and
`connect-src` lists — the setup script writes this for you.

### The Collabora proof key

The key is generated on the host and mounted read-only. Create it once:

```bash
openssl genrsa -traditional -out /mnt/user/appdata/collabora/proof/proof_key 4096
chown 1001:1001 /mnt/user/appdata/collabora/proof/proof_key
chmod 400 /mnt/user/appdata/collabora/proof/proof_key
```

## 📝 Post-Installation

### Initial Login

1. Navigate to `https://opencloud.yourdomain.com`
2. Login with username `admin` and the password from `IDM_ADMIN_PASSWORD`
   (or the one printed in the container log)

### Test Document Editing

1. Upload a `.docx` or `.xlsx` file
2. Click to open it
3. It should open in Collabora/Euro-Office
4. Edit and save

### Test Real-Time Collaboration (Yjs)

Collaboration works for **Markdown and `.ocnote` files only**, and not for public
links or end-to-end-encrypted vaults.

1. Create a `.md` file in OpenCloud
2. Open it in two browsers (two different users)
3. Type in one — the text should appear in the other within a second

If nothing syncs, check `docker logs YJS` and confirm the `/yjs` route exists in
`proxy.yaml`.

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
┌──────────────────────────────────────────┐
│           opencloud-net network          │
│                                          │
│  OpenCloud:9200                          │
│    ├── web UI                            │
│    ├── /wopi, /collaboration (built-in)  │
│    ├── /yjs      → Yjs:1234              │
│    └── /caldav, /carddav → Radicale:5232 │
│                                          │
│  Collabora:9980   (or Euro-Office:80)    │
│  Yjs:1234                                │
│  Radicale:5232                           │
│  Pocket-ID:1411  (optional)              │
└──────────────────────────────────────────┘
```

### Key Environment Variables

#### OpenCloud
- `OC_URL`: Your public OpenCloud URL
- `OC_ADD_RUN_SERVICES`: `collaboration` = built-in WOPI service
- `WEB_OPTION_YJS_SERVER_URL`: `wss://opencloud.yourdomain.com/yjs` — empty disables Yjs
- `OC_INSECURE`: Set to `true` for self-signed certs
- `PROXY_HTTP_ADDR`: Internal HTTP listener (0.0.0.0:9200)
- `IDM_ADMIN_PASSWORD`: Admin account password

#### Collabora
- `aliasgroup1`: The OpenCloud URL (the WOPI host allowlist)
- `username/password`: Admin console credentials
- `extra_params`: Security and frame settings

#### Euro-Office
- `JWT_SECRET`: Shared secret for the document server
- `WOPI_ENABLED`: Must be `true`

#### Yjs
- `OPENCLOUD_URL`: `http://OpenCloud:9200` — how the relay reaches OpenCloud
- `PORT`: `1234` — must match the `/yjs` route in `proxy.yaml`

### File Locations

```
/mnt/user/appdata/opencloud/
├── config/
│   ├── opencloud.yaml           # generated by `opencloud init`
│   ├── csp.yaml                 # Content Security Policy
│   ├── proxy.yaml               # /yjs and /caldav,/carddav routes
│   ├── apps.yaml
│   ├── app-registry.yaml        # Euro-Office only
│   └── banned-password-list.txt
├── data/                        # User files and metadata
└── apps/                        # Web extensions

/mnt/user/appdata/collabora/
├── config/
└── proof/
    └── proof_key                # WOPI proof key (chmod 400)

/mnt/user/appdata/radicale/
├── config/
│   └── config
└── data/                        # Calendar/contact data
```

### proxy.yaml

All OpenCloud routes must live in **one** `additional_policies` block — a second
`additional_policies:` key silently drops the first one:

```yaml
additional_policies:
  - name: default
    routes:
      - endpoint: /yjs
        backend: http://YJS:1234
        unprotected: true
      - endpoint: /caldav/
        backend: http://radicale:5232
        # ...
```

## 🐛 Troubleshooting

### OpenCloud won't start
```bash
docker logs OpenCloud

# Common issues:
# - Missing csp.yaml / proxy.yaml / banned-password-list.txt in the config directory
#   Solution: Re-run the setup script (DRY_RUN="false")
# - Crash loop mentioning parseWopiDiscovery or nil pointer
#   Solution: the web office is not reachable. Start it first and confirm
#             https://<weboffice>/hosting/discovery returns HTTP 200
# - Port conflict on 9200
#   Solution: Stop the conflicting container
```

### Collabora can't connect
```bash
docker logs Collabora

# Common issues:
# - Wrong aliasgroup1 URL
#   Solution: must be the OpenCloud URL, https://opencloud.yourdomain.com
# - CORS errors in the browser console
#   Solution: check extra_params frame_ancestors + lok_allow.host
# - Documents open blank / proof key errors
#   Solution: regenerate /mnt/user/appdata/collabora/proof/proof_key
#             and make sure it is owned by 1001:1001 with mode 400
```

### Documents won't open
```bash
docker logs OpenCloud | grep -i collabora

# Common issues:
# - "app provider not found"
#   Solution: OC_ADD_RUN_SERVICES must contain "collaboration"
# - The collaboration service is not registered
#   Solution: restart OpenCloud with the web office already running
# - COLLABORATION_APP_* points at the wrong container
#   Solution: see "Choosing your web office"
```

### Yjs collaboration not syncing
```bash
docker logs YJS

# Common issues:
# - No /yjs route in proxy.yaml
#   Solution: add it to the existing additional_policies block, then restart OpenCloud
# - WEB_OPTION_YJS_SERVER_URL not set on the OpenCloud container
#   Solution: set it to wss://opencloud.yourdomain.com/yjs
# - WebSocket blocked by the reverse proxy
#   Solution: SWAG needs the /yjs location block from SWAG-conf/opencloud.conf
# - The file type does not support it
#   Solution: only Markdown and .ocnote files are collaborative
```

### Radicale not syncing
```bash
docker logs Radicale

# Common issues:
# - proxy.yaml not mounted in OpenCloud
#   Solution: the config directory mount already covers it; check the file exists
# - Authentication failures
#   Solution: use app tokens, not the main password
# - Wrong URLs in client
#   Solution: URLs must be https://opencloud.domain.com/caldav/ (with trailing slash)
```

### Desktop app SSL errors

The shipped configs deliberately avoid hard-coding TLS headers:

- ✅ `proxy.conf` sets `X-Forwarded-Proto $scheme`
- ❌ Do **not** add a second `proxy_set_header X-Forwarded-Proto https;` — duplicated
  headers are what breaks the desktop client
- ❌ Do not set `X-Forwarded-Ssl on`

### Uploads fail at ~10MB

Check `client_max_body_size` in your SWAG config. It must be `0` (unlimited) for
OpenCloud — a `10M` value caps every upload that goes through that subdomain.

### Pangolin/Traefik Issues

If you're experiencing issues with CalDAV/CardDAV or Collabora on Pangolin:

1. **Verify Traefik configuration:**
   ```bash
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
   - Configured in the OpenCloud template
   - Minimum 8 characters, mixed case, numbers, special chars

3. **Public share security:**
   - Require passwords for public shares (enabled by default)

4. **Network isolation:**
   - Keep `opencloud-net` internal only
   - Only SWAG should expose ports externally
   - Yjs and Radicale publish no ports on purpose

5. **Radicale security:**
   - Always use app tokens for CalDAV/CardDAV clients
   - Never share your main OpenCloud password with sync clients

6. **Never commit secrets:**
   - `opencloud-secrets.txt` lives in the config directory, not in this repo
   - The templates ship with empty secret fields on purpose

## 📚 Additional Resources

- **OpenCloud Documentation:** https://docs.opencloud.eu/
- **OpenCloud 8.x upgrade guide:** https://docs.opencloud.eu/docs/next/admin/maintenance/upgrade/upgrade-8.x.x/
- **Collabora Documentation:** https://www.collaboraoffice.com/code/
- **SWAG Documentation:** https://docs.linuxserver.io/general/swag
- **Radicale Documentation:** https://radicale.org/v3.html
- **Pangolin Documentation:** https://pangolin.com/docs (for Traefik configuration)

## 🤝 Contributing

Issues and pull requests welcome! Please test thoroughly before submitting.

## 📄 License

These templates are provided as-is. OpenCloud, Collabora, Euro-Office, Yjs, Radicale and Pocket-ID are subject to their respective licenses.

## ⭐ Support

If this helped you, consider:
- ⭐ Starring this repository
- 📢 Sharing with others running Unraid or Pangolin
- 🐛 Reporting issues you encounter

---

**Template Version:** OpenCloud 7.5+ / 8.x
**Compatible with:** Unraid 7.2.0+, OpenCloud Rolling, Collabora Latest
**Platform Support:** Unraid (SWAG), Pangolin (Traefik)
