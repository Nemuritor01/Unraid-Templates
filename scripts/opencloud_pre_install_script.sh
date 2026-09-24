#!/bin/bash
################################################################################
# OpenCloud Setup Script - Network, Folders & Configuration Files
# For OpenCloud 7.5.0+ (NEW WOPI architecture)
################################################################################
#name=OpenCloud Network & File Setup
#description=Creates Docker network, folders, and config files for OpenCloud 7.5+
#arrayStarted=false
#
# WHAT CHANGED IN 7.5 (vs. earlier versions of this script)
# ---------------------------------------------------------
#  * The separate "Collaboration" (WOPI) container is GONE. The collaboration
#    service now runs INSIDE the main OpenCloud process
#    (OC_ADD_RUN_SERVICES=collaboration) and is served by the OpenCloud proxy
#    on the MAIN domain under /wopi and /collaboration.
#    -> No wopiserver subdomain, no wopi SWAG conf, no wopi DNS entry.
#  * Collabora no longer uses "--entrypoint=/bin/bash" + coolconfig.
#    The WOPI proof key is generated OUTSIDE the container and mounted
#    read-only at /etc/coolwsd/proof_key. This script generates it.
#  * Collabora uses cap_add SYS_ADMIN + unconfined seccomp/apparmor
#    instead of Privileged.
#  * NEW: Euro-Office (OnlyOffice-based) as an ALTERNATIVE to Collabora.
#    They are mutually exclusive - both use the same collaboration service.
#  * New apps.yaml is mounted by upstream; created here.
################################################################################

#######################################################################################
#                                USER CONFIGURATION                                   #
#######################################################################################

# ═══════════════════════════════════════════════════════════════════════════════════
#  WEB OFFICE  (Collabora and Euro-Office are MUTUALLY EXCLUSIVE - pick ONE)
# ═══════════════════════════════════════════════════════════════════════════════════
ENABLE_COLLABORA="true"        # Document editing via Collabora Online
ENABLE_EURO_OFFICE="false"     # Document editing via Euro-Office (OnlyOffice)

# ═══════════════════════════════════════════════════════════════════════════════════
#  OTHER FEATURES
# ═══════════════════════════════════════════════════════════════════════════════════
ENABLE_RADICALE="true"         # Calendar/Contacts (CalDAV/CardDAV)
ENABLE_RADICALE_WEBUI="true"   # Radicale built-in web interface
ENABLE_POCKET_ID="false"       # Pocket-ID OIDC authentication (passkeys)

POCKET_ID_DRY_RUN="false"

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOCKER NETWORK
# ═══════════════════════════════════════════════════════════════════════════════════
CUSTOM_NETWORK="true"
NETWORK_NAME="opencloud-net"

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOMAIN CONFIGURATION (no https://, just the domain)
#  NOTE: there is NO wopiserver domain anymore in 7.5+
# ═══════════════════════════════════════════════════════════════════════════════════
OCIS_DOMAIN="opencloud.yourdomain.com"
COLLABORA_DOMAIN="collabora.yourdomain.com"
EURO_OFFICE_DOMAIN="euro-office.yourdomain.com"

# ═══════════════════════════════════════════════════════════════════════════════════
#  POCKET-ID CONFIGURATION (only if ENABLE_POCKET_ID="true")
# ═══════════════════════════════════════════════════════════════════════════════════
POCKET_ID_DOMAIN="pocket-id.yourdomain.com"
POCKET_ID_WEB_CLIENT_ID="Create and Change me"

# ═══════════════════════════════════════════════════════════════════════════════════
#  INSTALLATION PATHS
# ═══════════════════════════════════════════════════════════════════════════════════
OCL_BASE="/mnt/user/appdata/opencloud"
OCL_DATA_BASE="/mnt/user/appdata/opencloud"
COL_BASE="/mnt/user/appdata/collabora"
RAD_BASE="/mnt/user/appdata/radicale"
EUO_BASE="/mnt/user/appdata/euro-office"

################################################################################
# SCRIPT START - DO NOT EDIT BELOW THIS LINE
################################################################################

OCL_CONFIG="${OCL_BASE}/config"
OCL_DATA="${OCL_DATA_BASE}/data"
OCL_APPS="${OCL_BASE}/apps"
COL_CONFIG="${COL_BASE}/config"
COL_PROOF="${COL_BASE}/proof"
RAD_CONFIG="${RAD_BASE}/config"
RAD_DATA="${RAD_BASE}/data"

GITHUB_BASE="https://raw.githubusercontent.com/opencloud-eu/opencloud-compose/main"
BANNED_PW_URL="${GITHUB_BASE}/config/opencloud/banned-password-list.txt"

IS_DRY_RUN="false"
[ "${POCKET_ID_DRY_RUN}" = "true" ] && IS_DRY_RUN="true"

echo "================================================"
echo "OpenCloud 7.5+ Network & File Setup"
echo "================================================"
[ "${IS_DRY_RUN}" = "true" ] && echo "  *** DRY RUN - no files or folders will be created ***"
echo ""
echo "  OCIS Domain:    ${OCIS_DOMAIN}"
[ "${ENABLE_COLLABORA}" = "true" ]   && echo "  Collabora:      ${COLLABORA_DOMAIN}"
[ "${ENABLE_EURO_OFFICE}" = "true" ] && echo "  Euro-Office:    ${EURO_OFFICE_DOMAIN}"
if [ "${ENABLE_COLLABORA}" = "true" ] || [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    echo "  WOPI:           served by OpenCloud on ${OCIS_DOMAIN}/wopi (no own domain)"
fi
if [ "${ENABLE_RADICALE}" = "true" ]; then
    echo "  Radicale:       Enabled (CalDAV/CardDAV)"
    [ "${ENABLE_RADICALE_WEBUI}" = "true" ] && echo "  Radicale WebUI: Enabled"
fi
[ "${ENABLE_POCKET_ID}" = "true" ] && echo "  Pocket-ID:      ${POCKET_ID_DOMAIN}"
echo "  Install path:   ${OCL_BASE}"
[ "${CUSTOM_NETWORK}" = "true" ] && echo "  Docker Network: ${NETWORK_NAME}"
echo "================================================"
echo ""

################################################################################
# Validation
################################################################################

VALIDATION_FAILED="false"

if [ "${ENABLE_COLLABORA}" = "true" ] && [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    echo "ERROR: Collabora and Euro-Office are mutually exclusive."
    echo "       Both use the same 'collaboration' (WOPI) service."
    VALIDATION_FAILED="true"
fi
if [ "${OCIS_DOMAIN}" = "opencloud.yourdomain.com" ]; then
    echo "ERROR: OCIS_DOMAIN is still the default. Configure it."
    VALIDATION_FAILED="true"
fi
if [ "${ENABLE_COLLABORA}" = "true" ] && [ "${COLLABORA_DOMAIN}" = "collabora.yourdomain.com" ]; then
    echo "ERROR: COLLABORA_DOMAIN is still the default. Configure it."
    VALIDATION_FAILED="true"
fi
if [ "${ENABLE_EURO_OFFICE}" = "true" ] && [ "${EURO_OFFICE_DOMAIN}" = "euro-office.yourdomain.com" ]; then
    echo "ERROR: EURO_OFFICE_DOMAIN is still the default. Configure it."
    VALIDATION_FAILED="true"
fi
if [ "${ENABLE_POCKET_ID}" = "true" ] && [ "${POCKET_ID_DOMAIN}" = "pocket-id.yourdomain.com" ]; then
    echo "ERROR: POCKET_ID_DOMAIN is still the default. Configure it."
    VALIDATION_FAILED="true"
fi

if [ "${VALIDATION_FAILED}" = "true" ]; then
    echo ""
    echo "Validation failed. Fix the errors above and run again."
    exit 1
fi

################################################################################
# Pocket-ID Dry Run
################################################################################

if [ "${IS_DRY_RUN}" = "true" ]; then
    echo "================================================"
    echo "Pocket-ID Setup Instructions"
    echo "================================================"
    echo ""
    echo "Complete these steps at: https://${POCKET_ID_DOMAIN}"
    echo ""
    echo "-- STEP 1: Create these User Groups (exact names) --"
    echo "    OC Admin        -> opencloudAdmin"
    echo "    OC Space Admin  -> opencloudSpaceAdmin"
    echo "    OC User         -> opencloudUser"
    echo "    OC Guest        -> opencloudGuest"
    echo ""
    echo "-- STEP 2: Add a Custom Claim to EACH group --"
    echo "    Key: roles   Value: <the exact group name>"
    echo ""
    echo "-- STEP 3: Assign your users to the groups --"
    echo ""
    echo "-- STEP 4: Create OIDC Clients (all public, all 4 groups allowed) --"
    echo "  Web:     https://${OCIS_DOMAIN}/"
    echo "           https://${OCIS_DOMAIN}/oidc-callback.html"
    echo "           https://${OCIS_DOMAIN}/oidc-silent-redirect.html"
    echo "  Desktop: ClientID OpenCloudDesktop, callbacks http://127.0.0.1 http://localhost"
    echo "  Android: ClientID OpenCloudAndroid, callback oc://android.opencloud.eu"
    echo "  iOS:     ClientID OpenCloudIOS,     callback oc://ios.opencloud.eu"
    echo ""
    SNIPPET_FILE="${OCL_CONFIG}/pocket-id-xml-snippet.txt"
    mkdir -p "${OCL_CONFIG}" 2>/dev/null
    cat > "${SNIPPET_FILE}" << XMLEOF
<Config Name="OC_OIDC_ISSUER" Target="OC_OIDC_ISSUER" Default="" Mode="" Description="External OIDC issuer URL (Pocket-ID)" Type="Variable" Display="always" Required="true" Mask="false">https://${POCKET_ID_DOMAIN}</Config>
<Config Name="OC_EXCLUDE_RUN_SERVICES" Target="OC_EXCLUDE_RUN_SERVICES" Default="" Mode="" Description="Disable built-in IDP" Type="Variable" Display="always" Required="true" Mask="false">idp</Config>
<Config Name="PROXY_OIDC_REWRITE_WELLKNOWN" Target="PROXY_OIDC_REWRITE_WELLKNOWN" Default="true" Mode="" Description="Rewrite OIDC well-known endpoint" Type="Variable" Display="advanced" Required="false" Mask="false">true</Config>
<Config Name="PROXY_USER_OIDC_CLAIM" Target="PROXY_USER_OIDC_CLAIM" Default="preferred_username" Mode="" Description="OIDC claim for user mapping" Type="Variable" Display="advanced" Required="false" Mask="false">preferred_username</Config>
<Config Name="PROXY_USER_CS3_CLAIM" Target="PROXY_USER_CS3_CLAIM" Default="username" Mode="" Description="CS3 claim for user mapping" Type="Variable" Display="advanced" Required="false" Mask="false">username</Config>
<Config Name="PROXY_AUTOPROVISION_ACCOUNTS" Target="PROXY_AUTOPROVISION_ACCOUNTS" Default="true" Mode="" Description="Auto-create accounts on first OIDC login" Type="Variable" Display="advanced" Required="false" Mask="false">true</Config>
<Config Name="PROXY_AUTOPROVISION_CLAIM_USERNAME" Target="PROXY_AUTOPROVISION_CLAIM_USERNAME" Default="preferred_username" Mode="" Description="Claim for auto-provisioned username" Type="Variable" Display="advanced" Required="false" Mask="false">preferred_username</Config>
<Config Name="PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD" Target="PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD" Default="none" Mode="" Description="Token verification method (none for Pocket-ID)" Type="Variable" Display="advanced" Required="false" Mask="false">none</Config>
<Config Name="GRAPH_USERNAME_MATCH" Target="GRAPH_USERNAME_MATCH" Default="none" Mode="" Description="Username matching mode" Type="Variable" Display="advanced" Required="false" Mask="false">none</Config>
<Config Name="GRAPH_ASSIGN_DEFAULT_USER_ROLE" Target="GRAPH_ASSIGN_DEFAULT_USER_ROLE" Default="false" Mode="" Description="Assign default role (false for OIDC roles)" Type="Variable" Display="advanced" Required="false" Mask="false">false</Config>
<Config Name="PROXY_ROLE_ASSIGNMENT_DRIVER" Target="PROXY_ROLE_ASSIGNMENT_DRIVER" Default="oidc" Mode="" Description="Role assignment via OIDC claims" Type="Variable" Display="advanced" Required="false" Mask="false">oidc</Config>
<Config Name="WEB_OIDC_CLIENT_ID" Target="WEB_OIDC_CLIENT_ID" Default="" Mode="" Description="OIDC client ID for web (from Pocket-ID)" Type="Variable" Display="always" Required="true" Mask="false">YOUR_CLIENT_ID_HERE</Config>
<Config Name="WEB_OIDC_SCOPE" Target="WEB_OIDC_SCOPE" Default="openid profile email groups" Mode="" Description="OIDC scopes to request" Type="Variable" Display="advanced" Required="false" Mask="false">openid profile email groups</Config>
<Config Name="WEB_OIDC_METADATA_URL" Target="WEB_OIDC_METADATA_URL" Default="" Mode="" Description="OIDC discovery endpoint URL" Type="Variable" Display="advanced" Required="false" Mask="false">https://${POCKET_ID_DOMAIN}/.well-known/openid-configuration</Config>
<Config Name="SETTINGS_SETUP_DEFAULT_ASSIGNMENTS" Target="SETTINGS_SETUP_DEFAULT_ASSIGNMENTS" Default="false" Mode="" Description="Default role assignments" Type="Variable" Display="advanced" Required="false" Mask="false">false</Config>
<Config Name="FRONTEND_READONLY_USER_ATTRIBUTES" Target="FRONTEND_READONLY_USER_ATTRIBUTES" Default="" Mode="" Description="Read-only attributes (managed by IDP)" Type="Variable" Display="advanced" Required="false" Mask="false">user.onPremisesSamAccountName,user.displayName,user.mail,user.passwordProfile,user.accountEnabled,user.appRoleAssignments</Config>
XMLEOF
    echo "  XML snippet saved to: ${SNIPPET_FILE}"
    echo "  Remove IDM_ADMIN_PASSWORD from your XML when using Pocket-ID."
    echo ""
    echo "  Then set POCKET_ID_DRY_RUN=\"false\" and run again."
    exit 0
fi

################################################################################
# [1] Docker Network
################################################################################

if [ "${CUSTOM_NETWORK}" = "true" ]; then
    echo "[1] Configuring Docker network..."
    if ! command -v docker &> /dev/null; then
        echo "ERROR: docker command not found."
        exit 1
    fi
    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        echo "    Network '${NETWORK_NAME}' already exists - skipping"
    else
        if docker network create "${NETWORK_NAME}" &> /dev/null; then
            echo "    Network '${NETWORK_NAME}' created"
        else
            echo "ERROR: failed to create Docker network '${NETWORK_NAME}'"
            exit 1
        fi
    fi
fi

################################################################################
# [2] Directories
################################################################################

echo "[2] Creating directories..."
mkdir -p "${OCL_CONFIG}" "${OCL_DATA}" "${OCL_APPS}"
[ "${ENABLE_COLLABORA}" = "true" ]   && mkdir -p "${COL_CONFIG}" "${COL_PROOF}"
[ "${ENABLE_EURO_OFFICE}" = "true" ] && mkdir -p "${EUO_BASE}"
[ "${ENABLE_RADICALE}" = "true" ]    && mkdir -p "${RAD_CONFIG}" "${RAD_DATA}"
echo "    Directories created"

################################################################################
# [3] CSP configuration
################################################################################

echo "[3] Creating CSP configuration..."
[ -d "${OCL_CONFIG}/csp.yaml" ] && rm -rf "${OCL_CONFIG}/csp.yaml"

WEBOFFICE_FRAME=""
WEBOFFICE_IMG=""
WEBOFFICE_CONNECT=""
if [ "${ENABLE_COLLABORA}" = "true" ]; then
    WEBOFFICE_FRAME="    - 'https://${COLLABORA_DOMAIN}/'"
    WEBOFFICE_IMG="    - 'https://${COLLABORA_DOMAIN}/'"
fi
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    WEBOFFICE_FRAME="    - 'https://${EURO_OFFICE_DOMAIN}/'"
    WEBOFFICE_IMG="    - 'https://${EURO_OFFICE_DOMAIN}/'"
    WEBOFFICE_CONNECT="    - 'https://${EURO_OFFICE_DOMAIN}/'
    - 'wss://${EURO_OFFICE_DOMAIN}/'"
fi

POCKETID_CONNECT=""
POCKETID_FRAME=""
POCKETID_SCRIPT=""
FORM_ACTION=""
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    POCKETID_CONNECT="    - 'https://${POCKET_ID_DOMAIN}/'
    - 'wss://${POCKET_ID_DOMAIN}/'"
    POCKETID_FRAME="    - 'https://${POCKET_ID_DOMAIN}/'"
    POCKETID_SCRIPT="    - 'https://${POCKET_ID_DOMAIN}/'"
    FORM_ACTION="  form-action:
    - '''self'''
    - 'https://${POCKET_ID_DOMAIN}/'"
    [ "${ENABLE_COLLABORA}" = "true" ] && FORM_ACTION="${FORM_ACTION}
    - 'https://${COLLABORA_DOMAIN}/'"
    [ "${ENABLE_EURO_OFFICE}" = "true" ] && FORM_ACTION="${FORM_ACTION}
    - 'https://${EURO_OFFICE_DOMAIN}/'"
fi

{
echo "directives:"
echo "  child-src:"
echo "    - '''self'''"
echo "  connect-src:"
echo "    - '''self'''"
echo "    - 'blob:'"
echo "    - 'https://${OCIS_DOMAIN}'"
echo "    - 'wss://${OCIS_DOMAIN}'"
echo "    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'"
echo "    - 'https://update.opencloud.eu/'"
echo "    - 'https://tile.openstreetmap.org/'"
[ -n "${WEBOFFICE_CONNECT}" ] && echo "${WEBOFFICE_CONNECT}"
[ -n "${POCKETID_CONNECT}" ] && echo "${POCKETID_CONNECT}"
echo "  default-src:"
echo "    - '''none'''"
echo "  font-src:"
echo "    - '''self'''"
[ -n "${FORM_ACTION}" ] && echo "${FORM_ACTION}"
echo "  frame-ancestors:"
echo "    - '''self'''"
echo "  frame-src:"
echo "    - '''self'''"
echo "    - 'blob:'"
echo "    - 'https://embed.diagrams.net/'"
echo "    - 'https://docs.opencloud.eu'"
[ -n "${WEBOFFICE_FRAME}" ] && echo "${WEBOFFICE_FRAME}"
[ -n "${POCKETID_FRAME}" ] && echo "${POCKETID_FRAME}"
echo "  img-src:"
echo "    - '''self'''"
echo "    - 'data:'"
echo "    - 'blob:'"
echo "    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'"
echo "    - 'https://tile.openstreetmap.org/'"
[ -n "${WEBOFFICE_IMG}" ] && echo "${WEBOFFICE_IMG}"
echo "  manifest-src:"
echo "    - '''self'''"
echo "  media-src:"
echo "    - '''self'''"
echo "  object-src:"
echo "    - '''self'''"
echo "    - 'blob:'"
echo "  script-src:"
echo "    - '''self'''"
echo "    - '''unsafe-inline'''"
[ -n "${POCKETID_SCRIPT}" ] && echo "${POCKETID_SCRIPT}"
echo "  style-src:"
echo "    - '''self'''"
echo "    - '''unsafe-inline'''"
echo "    - 'blob:'"
echo "  worker-src:"
echo "    - '''self'''"
echo "    - 'blob:'"
} > "${OCL_CONFIG}/csp.yaml"

echo "    CSP configuration created"

################################################################################
# [4] apps.yaml (mounted by upstream compose since 7.x)
################################################################################

echo "[4] Creating apps.yaml..."
[ -d "${OCL_CONFIG}/apps.yaml" ] && rm -rf "${OCL_CONFIG}/apps.yaml"
if [ ! -f "${OCL_CONFIG}/apps.yaml" ]; then
    cat > "${OCL_CONFIG}/apps.yaml" <<'EOF'
maps:
  config:
    folderViewEnabled: false
EOF
    echo "    apps.yaml created"
else
    echo "    apps.yaml already exists - keeping it"
fi

################################################################################
# [5] Banned password list
################################################################################

echo "[5] Creating banned password list..."
[ -d "${OCL_CONFIG}/banned-password-list.txt" ] && rm -rf "${OCL_CONFIG}/banned-password-list.txt"
curl -sL "${BANNED_PW_URL}" -o "${OCL_CONFIG}/banned-password-list.txt" 2>/dev/null || \
cat > "${OCL_CONFIG}/banned-password-list.txt" <<'EOF'
password
12345678
123
OpenCloud
OpenCloud-1
admin
EOF
echo "    Banned password list created"

################################################################################
# [6] Collabora WOPI proof key
#     Collabora no longer generates this itself via an overridden entrypoint.
#     Upstream generates it in a one-shot container; on Unraid we generate it
#     here and bind-mount the file read-only into the container.
################################################################################

if [ "${ENABLE_COLLABORA}" = "true" ]; then
    echo "[6] Preparing Collabora WOPI proof key..."
    PROOF_KEY="${COL_PROOF}/proof_key"
    if [ -s "${PROOF_KEY}" ]; then
        echo "    Proof key already exists - keeping it"
    elif ! command -v openssl &> /dev/null; then
        echo "    WARNING: openssl not found - skipping proof key generation."
    else
        if openssl genrsa -traditional -out "${PROOF_KEY}.tmp" 4096 2>/dev/null \
           || openssl genrsa -out "${PROOF_KEY}.tmp" 4096 2>/dev/null; then
            chown 1001:1001 "${PROOF_KEY}.tmp" 2>/dev/null
            chmod 400 "${PROOF_KEY}.tmp"
            mv "${PROOF_KEY}.tmp" "${PROOF_KEY}"
            echo "    Proof key generated: ${PROOF_KEY}"
        else
            rm -f "${PROOF_KEY}.tmp"
            echo "    WARNING: proof key generation failed."
        fi
    fi
    echo ""
    echo "    Mount into the Collabora container as:"
    echo "      Host:      ${PROOF_KEY}"
    echo "      Container: /etc/coolwsd/proof_key    (Read Only)"
fi

################################################################################
# [7] Euro-Office app-registry + JWT secret
################################################################################

if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    echo "[7] Preparing Euro-Office configuration..."
    cat > "${OCL_CONFIG}/app-registry.yaml" <<'EOF'
app_registry:
  mimetypes:
    - mime_type: application/pdf
      extension: pdf
      name: PDF
      description: PDF document
      icon: ''
      default_app: ''
      allow_creation: false
    - mime_type: application/vnd.oasis.opendocument.text
      extension: odt
      name: OpenDocument
      description: OpenDocument text document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
    - mime_type: application/vnd.oasis.opendocument.spreadsheet
      extension: ods
      name: OpenSpreadsheet
      description: OpenDocument spreadsheet document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
    - mime_type: application/vnd.oasis.opendocument.presentation
      extension: odp
      name: OpenPresentation
      description: OpenDocument presentation document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
    - mime_type: application/vnd.openxmlformats-officedocument.wordprocessingml.document
      extension: docx
      name: Microsoft Word
      description: Microsoft Word document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
    - mime_type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      extension: xlsx
      name: Microsoft Excel
      description: Microsoft Excel document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
    - mime_type: application/vnd.openxmlformats-officedocument.presentationml.presentation
      extension: pptx
      name: Microsoft PowerPoint
      description: Microsoft PowerPoint document
      icon: ''
      default_app: Euro-Office
      allow_creation: true
EOF
    echo "    app-registry.yaml created: ${OCL_CONFIG}/app-registry.yaml"
    echo "    Mount it as /etc/opencloud/app-registry.yaml in the OpenCloud container."

    JWT_FILE="${OCL_CONFIG}/euro-office-jwt-secret.txt"
    if [ -s "${JWT_FILE}" ]; then
        echo "    Existing Euro-Office JWT secret kept: ${JWT_FILE}"
    else
        EUO_JWT=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        [ -z "${EUO_JWT}" ] && EUO_JWT=$(openssl rand -hex 16 2>/dev/null)
        printf 'EURO_OFFICE_JWT_SECRET=%s\n' "${EUO_JWT}" > "${JWT_FILE}"
        chmod 600 "${JWT_FILE}"
        echo "    JWT secret generated: ${JWT_FILE}"
        echo "      ${EUO_JWT}"
        echo "    Set this as JWT_SECRET on the Euro-Office container."
    fi
fi

################################################################################
# [8] Radicale configuration
################################################################################

if [ "${ENABLE_RADICALE}" = "true" ]; then
    echo "[8] Creating Radicale configuration..."
    if [ "${ENABLE_RADICALE_WEBUI}" = "true" ]; then
        cat > "${OCL_CONFIG}/proxy.yaml" <<'EOF'
additional_policies:
  - name: default
    routes:
      - endpoint: /caldav/
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /caldav
      - endpoint: /.well-known/caldav
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /caldav
      - endpoint: /carddav/
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /carddav
      - endpoint: /.well-known/carddav
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /carddav
      - endpoint: /caldav/.web/
        backend: http://radicale:5232/
        unprotected: true
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /caldav
EOF
    else
        cat > "${OCL_CONFIG}/proxy.yaml" <<'EOF'
additional_policies:
  - name: default
    routes:
      - endpoint: /caldav/
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /caldav
      - endpoint: /.well-known/caldav
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /caldav
      - endpoint: /carddav/
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /carddav
      - endpoint: /.well-known/carddav
        backend: http://radicale:5232
        remote_user_header: X-Remote-User
        skip_x_access_token: true
        additional_headers:
          - X-Script-Name: /carddav
EOF
    fi

    cat > "${RAD_CONFIG}/config" <<'EOF'
[server]
hosts = 0.0.0.0:5232

[auth]
type = http_x_remote_user

[storage]
predefined_collections = {
    "def-addressbook": {
       "D:displayname": "Personal Address Book",
       "tag": "VADDRESSBOOK"
    },
    "def-calendar": {
       "C:supported-calendar-component-set": "VEVENT,VJOURNAL,VTODO",
       "D:displayname": "Personal Calendar",
       "tag": "VCALENDAR"
    }
  }

[web]
type = internal
EOF
    echo "    Radicale configuration created"
fi

################################################################################
# Summary
################################################################################

echo ""
echo "================================================"
echo "Setup complete"
echo "================================================"
echo ""
echo "  IMPORTANT for OpenCloud 7.5+:"
echo ""
echo "  1. There is NO separate 'Collaboration' (WOPI) container anymore."
echo "     On the OpenCloud container set:"
echo "        OC_ADD_RUN_SERVICES=collaboration"
echo "     If you also use email notifications:"
echo "        OC_ADD_RUN_SERVICES=notifications,collaboration"
echo ""
echo "  2. WOPI is served on https://${OCIS_DOMAIN}/wopi and /collaboration."
echo "     Delete the wopiserver SWAG conf and its DNS record - both unused."
echo ""
if [ "${ENABLE_COLLABORA}" = "true" ]; then
echo "  3. Collabora template changes:"
echo "     - REMOVE ExtraParams '--entrypoint=/bin/bash' and the PostArgs"
echo "       'coolconfig generate-proof-key ...'"
echo "     - Set ExtraParams:"
echo "         --cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined"
echo "     - Privileged: OFF"
echo "     - Mount proof key read-only at /etc/coolwsd/proof_key"
echo "     - aliasgroup1 = https://${OCIS_DOMAIN}   (NOT a wopi domain)"
fi
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
echo "  3. Euro-Office: on the OpenCloud container set"
echo "       COLLABORATION_APP_NAME=Euro-Office"
echo "       COLLABORATION_APP_PRODUCT=OnlyOffice"
echo "       COLLABORATION_APP_PROOF_DISABLE=true"
echo "       COLLABORATION_APP_ADDR=https://${EURO_OFFICE_DOMAIN}"
echo "     and mount app-registry.yaml at /etc/opencloud/app-registry.yaml"
fi
echo ""
