#!/bin/bash
################################################################################
# OpenCloud Setup Script - Network, Folders & Configuration Files
# Creates Docker network, directory structure, CSP config, and banned password list
################################################################################
#name=OpenCloud Network & File Setup
#description=Creates Docker network, folders, and configuration files for OpenCloud
#arrayStarted=false

#######################################################################################
#                                USER CONFIGURATION                                   #
#######################################################################################

# ═══════════════════════════════════════════════════════════════════════════════════
#  FEATURE TOGGLES
# ═══════════════════════════════════════════════════════════════════════════════════
ENABLE_COLLABORA="true"        # Document editing (Collabora + WOPI)
ENABLE_RADICALE="true"         # Calendar/Contacts (CalDAV/CardDAV)
ENABLE_RADICALE_WEBUI="true"   # Radicale built-in web interface
                               # Accessible at https://yourdomain.com/caldav/.web/
                               # WARNING: Web UI has its own auth - keep disabled unless needed
ENABLE_POCKET_ID="false"       # Pocket-ID OIDC authentication (passkeys)

# ═══════════════════════════════════════════════════════════════════════════════════
#  DRY RUN MODE (only relevant when ENABLE_POCKET_ID="true")
# ═══════════════════════════════════════════════════════════════════════════════════
# Set to "true" for first run: shows ALL Pocket-ID setup instructions (groups,
# claims, OIDC clients, XML changes) WITHOUT creating any files or folders.
# After completing the Pocket-ID setup, set to "false" and run again to create
# the actual files, folders, and configs.
POCKET_ID_DRY_RUN="false"

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOCKER NETWORK
# ═══════════════════════════════════════════════════════════════════════════════════
CUSTOM_NETWORK="true"
NETWORK_NAME="opencloud-net"

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOMAIN CONFIGURATION (no https://, just the domain)
# ═══════════════════════════════════════════════════════════════════════════════════
OCIS_DOMAIN="opencloud.yourdomain.com"
COLLABORA_DOMAIN="collabora.yourdomain.com"
WOPISERVER_DOMAIN="wopi.yourdomain.com"

# ═══════════════════════════════════════════════════════════════════════════════════
#  POCKET-ID CONFIGURATION (only needed if ENABLE_POCKET_ID="true")
# ═══════════════════════════════════════════════════════════════════════════════════
# Your Pocket-ID instance URL (no https://, just the domain)
POCKET_ID_DOMAIN="pocke-id.yourdomain.com"

# The Client ID from Pocket-ID for the "web" OIDC client
# → Create an OIDC client in Pocket-ID first, then paste the Client ID here
# → Leave as default during DRY RUN — you'll get it from Pocket-ID setup
POCKET_ID_WEB_CLIENT_ID="Create and Change me"

# ═══════════════════════════════════════════════════════════════════════════════════
#  INSTALLATION PATHS
# ═══════════════════════════════════════════════════════════════════════════════════
OCL_BASE="/mnt/user/appdata/opencloud"
OCL_DATA_BASE="/mnt/user/appdata/opencloud"
COL_BASE="/mnt/user/appdata/collabora"
RAD_BASE="/mnt/user/appdata/radicale"


################################################################################
# SCRIPT START - DO NOT EDIT BELOW THIS LINE
################################################################################

OCL_CONFIG="${OCL_BASE}/config"
OCL_DATA="${OCL_DATA_BASE}/data"
OCL_APPS="${OCL_BASE}/apps"
COL_CONFIG="${COL_BASE}/config"
COLLAB_CONFIG="${OCL_BASE}/collaboration"
RAD_CONFIG="${RAD_BASE}/config"
RAD_DATA="${RAD_BASE}/data"

GITHUB_BASE="https://raw.githubusercontent.com/opencloud-eu/opencloud-compose/main"
BANNED_PW_URL="${GITHUB_BASE}/config/opencloud/banned-password-list.txt"

# Determine effective dry run state
IS_DRY_RUN="false"
if [ "${POCKET_ID_DRY_RUN}" = "true" ]; then
    IS_DRY_RUN="true"
fi

echo "================================================"
echo "OpenCloud Network & File Setup"
echo "================================================"
if [ "${IS_DRY_RUN}" = "true" ]; then
    echo ""
    echo "  *** DRY RUN MODE — No files or folders will be created ***"
    echo "  This run shows Pocket-ID instructions only."
    echo "  After completing setup, set POCKET_ID_DRY_RUN=\"false\""
    echo "  and run again."
fi
echo ""
echo "  OCIS Domain:    ${OCIS_DOMAIN}"
if [ "${ENABLE_COLLABORA}" = "true" ]; then
    echo "  Collabora:      ${COLLABORA_DOMAIN}"
    echo "  WOPI Server:    ${WOPISERVER_DOMAIN}"
fi
if [ "${ENABLE_RADICALE}" = "true" ]; then
    echo "  Radicale:        Enabled (CalDAV/CardDAV)"
    if [ "${ENABLE_RADICALE_WEBUI}" = "true" ]; then
        echo "  Radicale Web UI: Enabled"
    fi
fi
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    echo "  Pocket-ID:      ${POCKET_ID_DOMAIN}"
    echo "  Dry Run:        ${IS_DRY_RUN}"
fi
echo "  Install path:   ${OCL_BASE}"
if [ "${CUSTOM_NETWORK}" = "true" ]; then
    echo "  Docker Network: ${NETWORK_NAME}"
fi
echo "================================================"
echo ""

################################################################################
# Validation
################################################################################

VALIDATION_FAILED="false"

if [ "${OCIS_DOMAIN}" = "opencloud.yourdomain.com" ]; then
    echo "❌ ERROR: OCIS_DOMAIN is still set to default. Please configure it."
    VALIDATION_FAILED="true"
fi

if [ "${ENABLE_COLLABORA}" = "true" ]; then
    if [ "${COLLABORA_DOMAIN}" = "collabora.yourdomain.com" ]; then
        echo "❌ ERROR: COLLABORA_DOMAIN is still set to default. Please configure it."
        VALIDATION_FAILED="true"
    fi
    if [ "${WOPISERVER_DOMAIN}" = "wopi.yourdomain.com" ]; then
        echo "❌ ERROR: WOPISERVER_DOMAIN is still set to default. Please configure it."
        VALIDATION_FAILED="true"
    fi
fi

if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    if [ "${POCKET_ID_DOMAIN}" = "id.yourdomain.com" ]; then
        echo "❌ ERROR: POCKET_ID_DOMAIN is still set to default. Please configure it."
        VALIDATION_FAILED="true"
    fi
    # Only validate Client ID when NOT in dry run
    if [ "${IS_DRY_RUN}" = "false" ]; then
        if [ "${POCKET_ID_WEB_CLIENT_ID}" = "PASTE_YOUR_POCKET_ID_WEB_CLIENT_ID_HERE" ]; then
            echo "❌ ERROR: POCKET_ID_WEB_CLIENT_ID is not set."
            echo "   Run with POCKET_ID_DRY_RUN=\"true\" first to get setup instructions."
            VALIDATION_FAILED="true"
        fi
    fi
fi

if [ "${VALIDATION_FAILED}" = "true" ]; then
    echo ""
    echo "❌ Validation failed. Please fix the errors above and run again."
    exit 1
fi

################################################################################
# Pocket-ID Dry Run: Setup Instructions
################################################################################

if [ "${IS_DRY_RUN}" = "true" ]; then

    echo "================================================"
    echo "Pocket-ID Setup Instructions"
    echo "================================================"
    echo ""
    echo "Complete these steps in your Pocket-ID admin panel at:"
    echo "  https://${POCKET_ID_DOMAIN}"
    echo ""

    # ── STEP 1: Groups ──
    echo "── STEP 1: Create User Groups in Pocket-ID ──"
    echo ""
    echo "  Navigate to: User Groups → Add Group"
    echo "  Create these 4 groups (exact names matter!):"
    echo ""
    echo "    Friendly Name       Name (exact)"
    echo "    -------------------------------------------"
    echo "    OC Admin            opencloudAdmin"
    echo "    OC Space Admin      opencloudSpaceAdmin"
    echo "    OC User             opencloudUser"
    echo "    OC Guest            opencloudGuest"
    echo ""

    # ── STEP 2: Custom Claims ──
    echo "── STEP 2: Add Custom Claims to Each Group ──"
    echo ""
    echo "  For EACH group: Edit group → Custom Claims → Add Claim"
    echo ""
    echo "    Group            Key        Value"
    echo "    -------------------------------------------"
    echo "    opencloudAdmin          roles      opencloudAdmin"
    echo "    opencloudSpaceAdmin     roles      opencloudSpaceAdmin"
    echo "    opencloudUser           roles      opencloudUser"
    echo "    opencloudGuest          roles      opencloudGuest"
    echo ""
    echo "  NOTE: Custom claims are part of the 'profile' scope, which"
    echo "  all OpenCloud clients request. This is how roles work on"
    echo "  mobile/desktop without needing the 'groups' scope explicitly."
    echo ""

    # ── STEP 3: Assign Users ──
    echo "── STEP 3: Assign Users to Groups ──"
    echo ""
    echo "  Edit each group → Users → Add your Pocket-ID users:"
    echo "    - Add yourself       → opencloudAdmin"
    echo "    - Add users      → opencloudUser"
    echo "    - ... etc."
    echo ""

    # ── STEP 4: OIDC Clients ──
    echo "── STEP 4: Create OIDC Clients in Pocket-ID ──"
    echo ""
    echo "  Navigate to: OIDC Clients → Add OIDC Client"
    echo ""
    echo "  4a) WEB Client (browser access)"
    echo "     Name:           OpenCloud Web"
    echo "     Callback URLs:  https://${OCIS_DOMAIN}/"
    echo "                     https://${OCIS_DOMAIN}/oidc-callback.html"
    echo "                     https://${OCIS_DOMAIN}/oidc-silent-redirect.html"
    echo "     Public Client:  YES"
    echo "     Allowed Groups: opencloudAdmin, opencloudSpaceAdmin, opencloudUser, opencloudGuest"
    echo ""
    echo "     → After saving, COPY the auto-generated Client ID"
    echo "     → Paste it into POCKET_ID_WEB_CLIENT_ID in this script"
    echo ""
    echo "  4b) Desktop Client"
    echo "     Name:           OpenCloud Desktop"
    echo "     Client ID:      OpenCloudDesktop  (edit manually in Pocket-ID DB)"
    echo "     Callback URLs:  http://127.0.0.1"
    echo "                     http://localhost"
    echo "     Public Client:  YES"
    echo "     Allowed Groups: opencloudAdmin, opencloudSpaceAdmin, opencloudUser, opencloudGuest"
    echo ""
    echo "     NOTE: Desktop app uses dynamic ports on 127.0.0.1."
    echo "     If Pocket-ID supports RFC 8252 loopback redirect (PR #1012),"
    echo "     any port will be accepted. Otherwise leave callback URLs"
    echo "     empty and the desktop app will fill in the specific port."
    echo ""
    echo "  4c) Android Client"
    echo "     Name:           OpenCloud Android"
    echo "     Client ID:      OpenCloudAndroid  (edit manually in Pocket-ID DB)"
    echo "     Callback URLs:  oc://android.opencloud.eu"
    echo "     Public Client:  YES"
    echo "     Allowed Groups: opencloudAdmin, opencloudSpaceAdmin, opencloudUser, opencloudGuest"
    echo ""
    echo "  4d) iOS Client"
    echo "     Name:           OpenCloud iOS"
    echo "     Client ID:      OpenCloudIOS  (edit manually in Pocket-ID DB)"
    echo "     Callback URLs:  oc://ios.opencloud.eu"
    echo "     Public Client:  YES"
    echo "     Allowed Groups: opencloudAdmin, opencloudSpaceAdmin, opencloudUser, opencloudGuest"
    echo ""
    echo "  To set custom Client IDs in Pocket-ID:"
    echo "  See https://github.com/pocket-id/pocket-id/issues/83#issuecomment-2565226796"
    echo "  You may need to edit the Pocket-ID SQLite database directly."
    echo ""

    # ── STEP 5: XML Changes ──
    echo "── STEP 5: OpenCloud XML Template Changes ──"
    echo ""
    echo "  After creating the OIDC clients above, you need to modify your"
    echo "  opencloud.xml template."
    echo ""

    # Write XML snippet to a file (terminal can't display XML tags properly)
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
<Config Name="OC_ADMIN_USER_ID" Target="OC_ADMIN_USER_ID" Default="" Mode="" Description="Admin user ID (empty for external IDP)" Type="Variable" Display="advanced" Required="false" Mask="false"></Config>
<Config Name="FRONTEND_READONLY_USER_ATTRIBUTES" Target="FRONTEND_READONLY_USER_ATTRIBUTES" Default="" Mode="" Description="Read-only attributes (managed by IDP)" Type="Variable" Display="advanced" Required="false" Mask="false">user.onPremisesSamAccountName,user.displayName,user.mail,user.passwordProfile,user.accountEnabled,user.appRoleAssignments</Config>

XMLEOF

    echo "  NOTE: XML tags cannot be displayed in this terminal."
    echo "  The full XML snippet has been saved to:"
    echo ""
    echo "    ${SNIPPET_FILE}"
    echo ""
    echo "  Open that file, copy all lines, and paste them into your"
    echo "  opencloud.xml template before the closing tag."
    echo ""
    echo "  OC_OIDC_ISSUER: https://ChangeToYourPocket-IDdomain.com" 
    echo "  Replace WEB_OIDC_CLIENT_ID -> YOUR_CLIENT_ID_HERE with your actual Pocket-ID Web Client ID."
    echo ""
    echo "  Also REMOVE these from your XML template if present:"
    echo "    - IDM_ADMIN_PASSWORD (no longer needed, users come from Pocket-ID)"
    echo " leave the rest as is!"
    echo ""

    # ── Important Notes ──
    echo "================================================"
    echo "  IMPORTANT NOTES"
    echo "================================================"
    echo ""
    echo "  1. The built-in IDP is DISABLED (OC_EXCLUDE_RUN_SERVICES=idp)."
    echo "     The built-in IDM (LDAP) is KEPT for user storage."
    echo "     Users are auto-provisioned on first login via Pocket-ID."
    echo ""
    echo "  2. The FIRST user to log in with the 'ocAdmin' role claim"
    echo "     becomes the admin. MAKE SURE YOU LOG IN FIRST!"
    echo ""
    echo "  3. Mobile/Desktop Client IDs must match exactly:"
    echo "       Desktop:  OpenCloudDesktop"
    echo "       Android:  OpenCloudAndroid"
    echo "       iOS:      OpenCloudIOS"
    echo "     These are hardcoded in the OpenCloud clients."
    echo "     You may need to edit Pocket-ID's SQLite DB to set custom IDs."
    echo ""
    echo "  4. If Pocket-ID goes down, NO ONE can log in to OpenCloud."
    echo "     Keep Pocket-ID on reliable storage (NVMe) and back it up."
    echo ""
    echo "  5. Token verification is set to 'none' for Pocket-ID compatibility."
    echo "     This is safe because OpenCloud validates tokens via the OIDC"
    echo "     discovery endpoint (WEB_OIDC_METADATA_URL)."
    echo ""

    echo "================================================"
    echo "Dry Run Complete"
    echo "================================================"
    echo ""
    echo "  What to do next:"
    echo ""
    echo "  1. Complete Steps 1-5 above in Pocket-ID admin panel"
    echo "  2. Copy the Web Client ID from Pocket-ID"
    echo "  3. Edit this script:"
    echo "     - Paste Client ID into POCKET_ID_WEB_CLIENT_ID"
    echo "     - Set POCKET_ID_DRY_RUN=\"false\""
    echo "  4. Add the XML <Config> entries from Step 6 to your opencloud.xml"
    echo "  5. Run this script again to create files and folders"
    echo ""
    echo "✓ Dry run finished. No files or folders were created (except the XML snippet)."
    exit 0
fi

################################################################################
# FROM HERE ON: ACTUAL INSTALLATION (not reached during dry run)
################################################################################

################################################################################
# Create Docker Network (if enabled)
################################################################################

if [ "${CUSTOM_NETWORK}" = "true" ]; then
    echo ""
    echo "================================================"
    echo "[1/5] Configuring Docker Network"
    echo "================================================"
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "❌ ERROR: Docker command not found!"
        echo "   Please ensure Docker is installed and running."
        exit 1
    fi
    
    # Check if network already exists
    echo "Checking for existing network '${NETWORK_NAME}'..."
    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        echo "✓ Network '${NETWORK_NAME}' already exists - skipping creation"
    else
        echo "Creating new Docker network '${NETWORK_NAME}'..."
        if docker network create "${NETWORK_NAME}" &> /dev/null; then
            echo "✓ Docker network '${NETWORK_NAME}' created successfully"
        else
            echo "❌ ERROR: Failed to create Docker network!"
            echo "   Network name: ${NETWORK_NAME}"
            echo ""
            echo "   Possible causes:"
            echo "   - Network name already in use"
            echo "   - Insufficient Docker permissions"
            echo ""
            echo "   Try: docker network ls"
            exit 1
        fi
    fi
    echo "================================================"
fi

################################################################################
# Create Directories
################################################################################

echo ""
echo "[$([ "${CUSTOM_NETWORK}" = "true" ] && echo "2" || echo "1")/$([ "${CUSTOM_NETWORK}" = "true" ] && echo "5" || echo "4")] Creating directories..."
mkdir -p "${OCL_CONFIG}"
mkdir -p "${OCL_DATA}"
mkdir -p "${OCL_APPS}"

if [ "${ENABLE_COLLABORA}" = "true" ]; then
    mkdir -p "${COL_CONFIG}"
    mkdir -p "${COLLAB_CONFIG}"
fi

if [ "${ENABLE_RADICALE}" = "true" ]; then
    mkdir -p "${RAD_CONFIG}"
    mkdir -p "${RAD_DATA}"
fi

echo "✓ Directories created successfully"

################################################################################
# Create CSP Configuration
################################################################################

echo ""
echo "[$([ "${CUSTOM_NETWORK}" = "true" ] && echo "3" || echo "2")/$([ "${CUSTOM_NETWORK}" = "true" ] && echo "5" || echo "4")] Creating CSP configuration..."

# Ensure the file doesn't exist as a directory
if [ -d "${OCL_CONFIG}/csp.yaml" ]; then
    rm -rf "${OCL_CONFIG}/csp.yaml"
fi

if [ "${ENABLE_COLLABORA}" = "true" ]; then
    # Create CSP config with Collabora domains
    cat > "${OCL_CONFIG}/csp.yaml" <<EOF
directives:
  child-src:
    - '''self'''
  connect-src:
    - '''self'''
    - 'blob:'
    - 'https://${OCIS_DOMAIN}'
    - 'wss://${OCIS_DOMAIN}'
    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
    - 'https://update.opencloud.eu/'
  default-src:
    - '''none'''
  font-src:
    - '''self'''
  frame-ancestors:
    - '''self'''
  frame-src:
    - '''self'''
    - 'blob:'
    - 'https://embed.diagrams.net/'
    - 'https://${COLLABORA_DOMAIN}'
    - 'https://docs.opencloud.eu'
  img-src:
    - '''self'''
    - 'data:'
    - 'blob:'
    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
    - 'https://tile.openstreetmap.org/'
    - 'https://${COLLABORA_DOMAIN}'
  manifest-src:
    - '''self'''
  media-src:
    - '''self'''
  object-src:
    - '''self'''
    - 'blob:'
  script-src:
    - '''self'''
    - '''unsafe-inline'''
  style-src:
    - '''self'''
    - '''unsafe-inline'''
EOF
else
    # Create CSP config without Collabora domains
    cat > "${OCL_CONFIG}/csp.yaml" <<EOF
directives:
  child-src:
    - '''self'''
  connect-src:
    - '''self'''
    - 'blob:'
    - 'https://${OCIS_DOMAIN}'
    - 'wss://${OCIS_DOMAIN}'
    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
    - 'https://update.opencloud.eu/'
  default-src:
    - '''none'''
  font-src:
    - '''self'''
  frame-ancestors:
    - '''self'''
  frame-src:
    - '''self'''
    - 'blob:'
    - 'https://embed.diagrams.net/'
    - 'https://docs.opencloud.eu'
  img-src:
    - '''self'''
    - 'data:'
    - 'blob:'
    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'
    - 'https://tile.openstreetmap.org/'
  manifest-src:
    - '''self'''
  media-src:
    - '''self'''
  object-src:
    - '''self'''
    - 'blob:'
  script-src:
    - '''self'''
    - '''unsafe-inline'''
  style-src:
    - '''self'''
    - '''unsafe-inline'''
EOF
fi

# Add Pocket-ID entries to CSP if enabled
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    # Add Pocket-ID to connect-src (after the last connect-src entry)
    sed -i "/^  connect-src:/,/^  [a-z]/ {
        /^  [a-z].*-src:\|^  [a-z].*-ancestors:/ ! {
            /https:\/\/update\.opencloud\.eu/a\\
    - 'https://${POCKET_ID_DOMAIN}/'\n    - 'wss://${POCKET_ID_DOMAIN}/'
        }
    }" "${OCL_CONFIG}/csp.yaml"

    # Build form-action directive with Pocket-ID and optionally Collabora
    FORM_ACTION_BLOCK="  form-action:\n    - '''self'''\n    - 'https://${POCKET_ID_DOMAIN}/'"
    if [ "${ENABLE_COLLABORA}" = "true" ]; then
        FORM_ACTION_BLOCK="${FORM_ACTION_BLOCK}\n    - 'https://${COLLABORA_DOMAIN}/'"
    fi

    # Add form-action directive after font-src
    sed -i "/^  font-src:/,/^  frame-ancestors:/ {
        /^  frame-ancestors:/ i\\
${FORM_ACTION_BLOCK}
    }" "${OCL_CONFIG}/csp.yaml"

    echo "✓ CSP configuration created successfully (with Pocket-ID)"
else
    echo "✓ CSP configuration created successfully"
fi

################################################################################
# Create Banned Password List
################################################################################

echo ""
echo "[$([ "${CUSTOM_NETWORK}" = "true" ] && echo "4" || echo "3")/$([ "${CUSTOM_NETWORK}" = "true" ] && echo "5" || echo "4")] Creating banned password list..."

# Ensure the file doesn't exist as a directory
if [ -d "${OCL_CONFIG}/banned-password-list.txt" ]; then
    rm -rf "${OCL_CONFIG}/banned-password-list.txt"
fi

# Download banned passwords list or create default
curl -sL "${BANNED_PW_URL}" -o "${OCL_CONFIG}/banned-password-list.txt" 2>/dev/null || \
cat > "${OCL_CONFIG}/banned-password-list.txt" <<'EOF'
password
12345678
123
OpenCloud
OpenCloud-1
admin
EOF

echo "✓ Banned password list created successfully"

################################################################################
# Create Radicale Configuration Files
################################################################################

if [ "${ENABLE_RADICALE}" = "true" ]; then
    echo ""
    echo "[$([ "${CUSTOM_NETWORK}" = "true" ] && echo "4.5" || echo "3.5")/$([ "${CUSTOM_NETWORK}" = "true" ] && echo "5" || echo "4")] Creating Radicale configuration files..."
    
    # Create proxy.yaml for OpenCloud
    if [ "${ENABLE_RADICALE_WEBUI}" = "true" ]; then
        # Include Web UI route UNCOMMENTED (enabled)
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
        # Include Web UI route COMMENTED OUT
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

    # Create Radicale config file
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
    echo "✓ Radicale configuration files created successfully"
fi
