#!/bin/bash
###############################################################################
#  OpenCloud 7.5+  -  Unraid Setup Generator
#
#  Creates EVERYTHING needed for a fresh OpenCloud install on Unraid:
#    * Docker network
#    * appdata folder structure
#    * config files   (csp.yaml, apps.yaml, proxy.yaml, app-registry.yaml,
#                      banned-password-list.txt, radicale config)
#    * secrets        (Collabora WOPI proof key, Euro-Office JWT,
#                      Pocket-ID encryption key, admin password)
#    * Unraid XML templates, with YOUR domains already filled in
#    * optional SWAG proxy configs
#
#  It does NOT create or start any container. After running, go to
#  Docker -> Add Container -> pick the template under "User templates"
#  -> review -> Apply.
#
#  ARCHITECTURE NOTE (7.5+):
#    The collaboration (WOPI) service runs INSIDE the OpenCloud container
#    (OC_ADD_RUN_SERVICES=collaboration) and is served on the MAIN domain
#    under /wopi and /collaboration. There is no separate Collaboration
#    container and no wopiserver subdomain anymore.
#
#  ORDER OF INSTALLATION (wrong order crashes OpenCloud):
#    1. Run this script
#    2. Create + start the web office container (Collabora or Euro-Office)
#    3. Verify https://<weboffice-domain>/hosting/discovery returns HTTP 200
#    4. Only then create + start the OpenCloud container
#    If OpenCloud starts while the web office is unreachable, the
#    collaboration service panics (nil pointer in parseWopiDiscovery) and
#    takes the WHOLE OpenCloud process down in a crash loop.
###############################################################################
#name=OpenCloud Setup Generator
#description=Creates folders, configs, secrets and ready-to-use Unraid XML templates for OpenCloud 7.5+
#arrayStarted=false

#######################################################################################
#                                USER CONFIGURATION                                   #
#######################################################################################

# ═══════════════════════════════════════════════════════════════════════════════════
#  WEB OFFICE  (Collabora and Euro-Office are MUTUALLY EXCLUSIVE - pick ONE)
# ═══════════════════════════════════════════════════════════════════════════════════
ENABLE_COLLABORA="true"        # Collabora Online (officially supported)
ENABLE_EURO_OFFICE="false"     # Euro-Office / OnlyOffice fork

# ═══════════════════════════════════════════════════════════════════════════════════
#  OTHER FEATURES
# ═══════════════════════════════════════════════════════════════════════════════════
ENABLE_RADICALE="true"         # Calendar/Contacts (CalDAV/CardDAV)
ENABLE_RADICALE_WEBUI="true"   # Radicale built-in web interface
ENABLE_POCKET_ID="false"       # Pocket-ID OIDC authentication (passkeys)

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOMAINS  (no https://, just the domain)
# ═══════════════════════════════════════════════════════════════════════════════════
OCIS_DOMAIN="opencloud.yourdomain.com"
COLLABORA_DOMAIN="collabora.yourdomain.com"
EURO_OFFICE_DOMAIN="euro-office.yourdomain.com"
POCKET_ID_DOMAIN="pocket-id.yourdomain.com"

# Pocket-ID web client ID (create the OIDC client in Pocket-ID first).
# Leave as-is on the first run, then re-run the script once you have it.
POCKET_ID_WEB_CLIENT_ID="CHANGE_ME"

# ═══════════════════════════════════════════════════════════════════════════════════
#  WHERE THE UNRAID TEMPLATES GO
# ═══════════════════════════════════════════════════════════════════════════════════
TEMPLATE_DIR="/boot/config/plugins/dockerMan/templates-user"

# ═══════════════════════════════════════════════════════════════════════════════════
#  TEMPLATE OVERWRITE CONTROL
#
#  OVERWRITE_TEMPLATES is the master switch:
#    false = NO template is ever overwritten. Existing ones are written as
#            <name>.xml.new so you can diff them manually.
#    true  = per-template flags below decide what gets overwritten.
#
#  Per-template flags (only used when OVERWRITE_TEMPLATES="true"):
#    true  = the existing template is backed up (.bak-<timestamp>) and replaced
#    false = a <name>.xml.new is written instead (existing file kept untouched)
# ═══════════════════════════════════════════════════════════════════════════════════
OVERWRITE_TEMPLATES="true"

OVERWRITE_OPENCLOUD="true"
OVERWRITE_COLLABORA="false"
OVERWRITE_EURO_OFFICE="false"
OVERWRITE_RADICALE="false"
OVERWRITE_POCKET_ID="false"

# ═══════════════════════════════════════════════════════════════════════════════════
#  DOCKER NETWORK
# ═══════════════════════════════════════════════════════════════════════════════════
CUSTOM_NETWORK="true"
NETWORK_NAME="opencloud-net"

# ═══════════════════════════════════════════════════════════════════════════════════
#  INSTALLATION PATHS
# ═══════════════════════════════════════════════════════════════════════════════════
OCL_BASE="/mnt/user/appdata/opencloud"
OCL_DATA_BASE="/mnt/user/appdata/opencloud"
COL_BASE="/mnt/user/appdata/collabora"
RAD_BASE="/mnt/user/appdata/radicale"
EUO_BASE="/mnt/user/appdata/euro-office"
PID_BASE="/mnt/user/appdata/pocket-id"

# ═══════════════════════════════════════════════════════════════════════════════════
#  SWAG (optional). Leave "false" if you use another reverse proxy.
# ═══════════════════════════════════════════════════════════════════════════════════
GENERATE_SWAG_CONFS="false"
SWAG_PROXY_CONFS="/mnt/user/appdata/swag/nginx/proxy-confs"

# SWAG config overwrite control (same logic as templates above)
OVERWRITE_SWAG_CONFS="true"
OVERWRITE_SWAG_OPENCLOUD="true"
OVERWRITE_SWAG_WEBOFFICE="false"

# ═══════════════════════════════════════════════════════════════════════════════════
#  ADMIN PASSWORD - leave empty to auto-generate (printed + saved to a file)
# ═══════════════════════════════════════════════════════════════════════════════════
IDM_ADMIN_PASSWORD=""

# true = show what would be done, write nothing
DRY_RUN="true"

###############################################################################
#  DO NOT EDIT BELOW THIS LINE
###############################################################################

OCL_CONFIG="${OCL_BASE}/config"
OCL_DATA="${OCL_DATA_BASE}/data"
OCL_APPS="${OCL_BASE}/apps"
COL_CONFIG="${COL_BASE}/config"
COL_PROOF="${COL_BASE}/proof"
RAD_CONFIG="${RAD_BASE}/config"
RAD_DATA="${RAD_BASE}/data"
PROOF_KEY="${COL_PROOF}/proof_key"
SECRETS_FILE="${OCL_CONFIG}/opencloud-secrets.txt"
BANNED_PW_URL="https://raw.githubusercontent.com/opencloud-eu/opencloud-compose/main/config/opencloud/banned-password-list.txt"
TS="$(date +%Y%m%d-%H%M%S)"

live() { [ "${DRY_RUN}" != "true" ]; }
say()  { echo "$@"; }
act()  { echo "    -> $1"; }

# XML-escape a value
xesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
# random secret: alphanumeric only (safe in XML, shell and env vars)
gen_secret() { head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "${1:-32}"; }
# password satisfying OpenCloud's default policy
gen_password() { printf '%s%s' "$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)" 'Aa1!'; }

# write_template <filename> <content>
#
# Decides whether to overwrite an existing template based on the master switch
# OVERWRITE_TEMPLATES and the per-template flag OVERWRITE_<NAME>. When a
# template is not allowed to be overwritten, a .new file is written instead.
write_template() {
    local name="$1" content="$2" target="${TEMPLATE_DIR}/$1"
    local overwrite="false"

    if [ "${OVERWRITE_TEMPLATES}" != "true" ]; then
        overwrite="false"
    else
        case "${name}" in
            my-OpenCloud.xml)   overwrite="${OVERWRITE_OPENCLOUD}" ;;
            my-Collabora.xml)   overwrite="${OVERWRITE_COLLABORA}" ;;
            my-Euro-Office.xml) overwrite="${OVERWRITE_EURO_OFFICE}" ;;
            my-Radicale.xml)    overwrite="${OVERWRITE_RADICALE}" ;;
            my-Pocket-ID.xml)   overwrite="${OVERWRITE_POCKET_ID}" ;;
            *)                  overwrite="false" ;;
        esac
    fi

    if [ -f "${target}" ] && [ "${overwrite}" != "true" ]; then
        act "${name} exists -> writing ${name}.new instead (existing kept)"
        live && printf '%s\n' "${content}" > "${target}.new"
    else
        if [ -f "${target}" ]; then
            act "${name} exists -> backup ${name}.bak-${TS}, then overwrite"
            live && cp "${target}" "${target}.bak-${TS}"
        else
            act "create ${name}"
        fi
        live && printf '%s\n' "${content}" > "${target}"
    fi
}

# write_swag_conf <filename> <content> <per-config-overwrite-flag>
#
# Same logic as write_template, but for SWAG proxy-confs. The master switch is
# OVERWRITE_SWAG_CONFS; the per-config flag is passed as the third argument.
write_swag_conf() {
    local name="$1" content="$2" per_flag="$3"
    local target="${SWAG_PROXY_CONFS}/${name}"
    local overwrite="false"

    if [ "${OVERWRITE_SWAG_CONFS}" = "true" ] && [ "${per_flag}" = "true" ]; then
        overwrite="true"
    fi

    if [ -f "${target}" ] && [ "${overwrite}" != "true" ]; then
        act "${name} exists -> writing ${name}.new instead (existing kept)"
        live && printf '%s\n' "${content}" > "${target}.new"
    else
        if [ -f "${target}" ]; then
            act "${name} exists -> backup ${name}.bak-${TS}, then overwrite"
            live && cp "${target}" "${target}.bak-${TS}"
        else
            act "create ${name}"
        fi
        live && printf '%s\n' "${content}" > "${target}"
    fi
}

say "============================================================"
say " OpenCloud 7.5+ Setup Generator"
[ "${DRY_RUN}" = "true" ] && say " MODE: DRY RUN - nothing will be written" || say " MODE: LIVE"
say "============================================================"

###############################################################################
# Validation
###############################################################################
FAIL="false"
if [ "${ENABLE_COLLABORA}" = "true" ] && [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    say "ERROR: Collabora and Euro-Office are mutually exclusive (same WOPI service)."; FAIL="true"
fi
case "${OCIS_DOMAIN}" in ""|opencloud.yourdomain.com) say "ERROR: set OCIS_DOMAIN"; FAIL="true";; esac
if [ "${ENABLE_COLLABORA}" = "true" ]; then
    case "${COLLABORA_DOMAIN}" in ""|collabora.yourdomain.com) say "ERROR: set COLLABORA_DOMAIN"; FAIL="true";; esac
fi
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    case "${EURO_OFFICE_DOMAIN}" in ""|euro-office.yourdomain.com) say "ERROR: set EURO_OFFICE_DOMAIN"; FAIL="true";; esac
fi
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    case "${POCKET_ID_DOMAIN}" in ""|pocket-id.yourdomain.com) say "ERROR: set POCKET_ID_DOMAIN"; FAIL="true";; esac
fi
if [ ! -d "${TEMPLATE_DIR}" ]; then
    if live; then
        mkdir -p "${TEMPLATE_DIR}" 2>/dev/null || { say "ERROR: cannot create TEMPLATE_DIR ${TEMPLATE_DIR}"; FAIL="true"; }
    else
        say "NOTE: TEMPLATE_DIR ${TEMPLATE_DIR} does not exist yet - it will be created."
    fi
fi
[ "${FAIL}" = "true" ] && { say ""; say "Validation failed. Nothing was changed."; exit 1; }

# Derived values
OC_URL="https://${OCIS_DOMAIN}"
if [ "${ENABLE_COLLABORA}" = "true" ]; then
    WEBOFFICE_DOMAIN="${COLLABORA_DOMAIN}"; WEBOFFICE_NAME="CollaboraOnline"; WEBOFFICE_PRODUCT="Collabora"
elif [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    WEBOFFICE_DOMAIN="${EURO_OFFICE_DOMAIN}"; WEBOFFICE_NAME="Euro-Office"; WEBOFFICE_PRODUCT="OnlyOffice"
else
    WEBOFFICE_DOMAIN=""; WEBOFFICE_NAME=""; WEBOFFICE_PRODUCT=""
fi
WEBOFFICE_URL="${WEBOFFICE_DOMAIN:+https://${WEBOFFICE_DOMAIN}}"

say ""
say "  OpenCloud    : ${OC_URL}"
[ -n "${WEBOFFICE_URL}" ] && say "  Web office   : ${WEBOFFICE_URL}  (${WEBOFFICE_NAME})"
[ -n "${WEBOFFICE_URL}" ] && say "  WOPI         : ${OC_URL}/wopi  (inside OpenCloud, no own domain)"
[ "${ENABLE_RADICALE}" = "true" ]  && say "  Radicale     : enabled"
[ "${ENABLE_POCKET_ID}" = "true" ] && say "  Pocket-ID    : https://${POCKET_ID_DOMAIN}"
say "  Templates    : ${TEMPLATE_DIR}"
say "  Network      : ${NETWORK_NAME}"
say ""

###############################################################################
# [1] Docker network
###############################################################################
say "[1] Docker network"
if [ "${CUSTOM_NETWORK}" != "true" ]; then
    say "    skipped (CUSTOM_NETWORK=false)"
elif ! command -v docker >/dev/null 2>&1; then
    say "    WARNING: docker not found - create '${NETWORK_NAME}' yourself"
elif docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    say "    '${NETWORK_NAME}' already exists"
else
    act "create docker network '${NETWORK_NAME}'"
    live && { docker network create "${NETWORK_NAME}" >/dev/null 2>&1 && say "    created" || say "    ERROR creating network"; }
fi
say ""

###############################################################################
# [2] Directories
###############################################################################
say "[2] Directories"
DIR_SPECS="${OCL_CONFIG}: : "
DIR_SPECS="${DIR_SPECS}
${OCL_DATA}: : "
DIR_SPECS="${DIR_SPECS}
${OCL_APPS}: : "
if [ "${ENABLE_COLLABORA}" = "true" ]; then
    DIR_SPECS="${DIR_SPECS}
${COL_CONFIG}: : "
    DIR_SPECS="${DIR_SPECS}
${COL_PROOF}: : "
fi
[ "${ENABLE_EURO_OFFICE}" = "true" ] && DIR_SPECS="${DIR_SPECS}
${EUO_BASE}/data: : "
if [ "${ENABLE_RADICALE}" = "true" ]; then
    DIR_SPECS="${DIR_SPECS}
${RAD_CONFIG}:1000:1000"
    DIR_SPECS="${DIR_SPECS}
${RAD_DATA}:1000:1000"
fi
[ "${ENABLE_POCKET_ID}" = "true" ] && DIR_SPECS="${DIR_SPECS}
${PID_BASE}/data:99:100"

echo "${DIR_SPECS}" | while IFS=: read -r d owner group; do
    [ -z "${d}" ] && continue
    d="$(echo "${d}" | xargs)"; owner="$(echo "${owner}" | xargs)"; group="$(echo "${group}" | xargs)"
    if [ -n "${owner}" ] && [ -n "${group}" ]; then
        act "mkdir -p ${d}  (chown ${owner}:${group})"
        if live; then
            mkdir -p "${d}"
            chown -R "${owner}:${group}" "${d}" 2>/dev/null \
                || say "    WARNING: chown ${owner}:${group} ${d} failed - fix manually"
        fi
    else
        act "mkdir -p ${d}"
        live && mkdir -p "${d}"
    fi
done
say ""

###############################################################################
# [3] Secrets
###############################################################################
say "[3] Secrets"
ADMIN_PW="${IDM_ADMIN_PASSWORD}"
if [ -z "${ADMIN_PW}" ]; then
    ADMIN_PW="$(gen_password)"
    act "generate admin password"
fi
EUO_JWT=""
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    EUO_JWT="$(gen_secret 32)"; act "generate Euro-Office JWT secret"
fi
PID_KEY=""
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    PID_KEY="$(gen_secret 32)"; act "generate Pocket-ID encryption key"
fi

if [ "${ENABLE_COLLABORA}" = "true" ]; then
    if [ -s "${PROOF_KEY}" ]; then
        say "    proof key already exists - keeping it"
    elif ! command -v openssl >/dev/null 2>&1; then
        say "    WARNING: openssl missing - cannot generate the WOPI proof key"
    else
        act "generate 4096-bit WOPI proof key -> ${PROOF_KEY}"
        if live; then
            if openssl genrsa -traditional -out "${PROOF_KEY}.tmp" 4096 2>/dev/null \
               || openssl genrsa -out "${PROOF_KEY}.tmp" 4096 2>/dev/null; then
                chown 1001:1001 "${PROOF_KEY}.tmp" 2>/dev/null
                chmod 400 "${PROOF_KEY}.tmp"
                mv "${PROOF_KEY}.tmp" "${PROOF_KEY}"
            else
                rm -f "${PROOF_KEY}.tmp"; say "    ERROR: proof key generation failed"
            fi
        fi
    fi
fi

act "write ${SECRETS_FILE}"
if live; then
    {
        echo "# OpenCloud secrets - generated ${TS}"
        echo "# Keep private. These values are already filled into the templates."
        echo "IDM_ADMIN_PASSWORD=${ADMIN_PW}"
        [ -n "${EUO_JWT}" ] && echo "EURO_OFFICE_JWT_SECRET=${EUO_JWT}"
        [ -n "${PID_KEY}" ] && echo "POCKET_ID_ENCRYPTION_KEY=${PID_KEY}"
        [ "${ENABLE_COLLABORA}" = "true" ] && echo "COLLABORA_PROOF_KEY=${PROOF_KEY}"
    } > "${SECRETS_FILE}"
    chmod 600 "${SECRETS_FILE}"
fi
say ""

###############################################################################
# [4] Config files
###############################################################################
say "[4] Config files"

# ---- csp.yaml -------------------------------------------------------------
act "write ${OCL_CONFIG}/csp.yaml"
if live; then
    [ -d "${OCL_CONFIG}/csp.yaml" ] && rm -rf "${OCL_CONFIG}/csp.yaml"
    {
    echo "directives:"
    echo "  child-src:"
    echo "    - '''self'''"
    echo "  connect-src:"
    echo "    - '''self'''"
    echo "    - 'blob:'"
    echo "    - '${OC_URL}'"
    echo "    - 'wss://${OCIS_DOMAIN}'"
    echo "    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'"
    echo "    - 'https://update.opencloud.eu/'"
    echo "    - 'https://tile.openstreetmap.org/'"
    if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
        echo "    - '${WEBOFFICE_URL}/'"
        echo "    - 'wss://${WEBOFFICE_DOMAIN}/'"
    fi
    if [ "${ENABLE_POCKET_ID}" = "true" ]; then
        echo "    - 'https://${POCKET_ID_DOMAIN}/'"
        echo "    - 'wss://${POCKET_ID_DOMAIN}/'"
    fi
    echo "  default-src:"
    echo "    - '''none'''"
    echo "  font-src:"
    echo "    - '''self'''"
    if [ "${ENABLE_POCKET_ID}" = "true" ]; then
        echo "  form-action:"
        echo "    - '''self'''"
        echo "    - 'https://${POCKET_ID_DOMAIN}/'"
        [ -n "${WEBOFFICE_URL}" ] && echo "    - '${WEBOFFICE_URL}/'"
    fi
    echo "  frame-ancestors:"
    echo "    - '''self'''"
    echo "  frame-src:"
    echo "    - '''self'''"
    echo "    - 'blob:'"
    echo "    - 'https://embed.diagrams.net/'"
    echo "    - 'https://docs.opencloud.eu'"
    [ -n "${WEBOFFICE_URL}" ] && echo "    - '${WEBOFFICE_URL}/'"
    [ "${ENABLE_POCKET_ID}" = "true" ] && echo "    - 'https://${POCKET_ID_DOMAIN}/'"
    echo "  img-src:"
    echo "    - '''self'''"
    echo "    - 'data:'"
    echo "    - 'blob:'"
    echo "    - 'https://raw.githubusercontent.com/opencloud-eu/awesome-apps/'"
    echo "    - 'https://tile.openstreetmap.org/'"
    [ -n "${WEBOFFICE_URL}" ] && echo "    - '${WEBOFFICE_URL}/'"
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
    [ "${ENABLE_POCKET_ID}" = "true" ] && echo "    - 'https://${POCKET_ID_DOMAIN}/'"
    echo "  style-src:"
    echo "    - '''self'''"
    echo "    - '''unsafe-inline'''"
    echo "    - 'blob:'"
    echo "  worker-src:"
    echo "    - '''self'''"
    echo "    - 'blob:'"
    } > "${OCL_CONFIG}/csp.yaml"
fi

# ---- apps.yaml ------------------------------------------------------------
act "write ${OCL_CONFIG}/apps.yaml"
live && printf 'maps:\n  config:\n    folderViewEnabled: false\n' > "${OCL_CONFIG}/apps.yaml"

# ---- banned password list -------------------------------------------------
act "write ${OCL_CONFIG}/banned-password-list.txt"
if live; then
    [ -d "${OCL_CONFIG}/banned-password-list.txt" ] && rm -rf "${OCL_CONFIG}/banned-password-list.txt"
    curl -sL "${BANNED_PW_URL}" -o "${OCL_CONFIG}/banned-password-list.txt" 2>/dev/null \
      || printf 'password\n12345678\n123\nOpenCloud\nOpenCloud-1\nadmin\n' > "${OCL_CONFIG}/banned-password-list.txt"
fi

# ---- app-registry.yaml (Euro-Office only) ---------------------------------
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
    act "write ${OCL_CONFIG}/app-registry.yaml"
    if live; then
        {
        echo "app_registry:"
        echo "  mimetypes:"
        echo "    - mime_type: application/pdf"
        echo "      extension: pdf"
        echo "      name: PDF"
        echo "      description: PDF document"
        echo "      icon: ''"
        echo "      default_app: ''"
        echo "      allow_creation: false"
        for entry in \
            "application/vnd.oasis.opendocument.text|odt|OpenDocument|OpenDocument text document" \
            "application/vnd.oasis.opendocument.spreadsheet|ods|OpenSpreadsheet|OpenDocument spreadsheet document" \
            "application/vnd.oasis.opendocument.presentation|odp|OpenPresentation|OpenDocument presentation document" \
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document|docx|Microsoft Word|Microsoft Word document" \
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet|xlsx|Microsoft Excel|Microsoft Excel document" \
            "application/vnd.openxmlformats-officedocument.presentationml.presentation|pptx|Microsoft PowerPoint|Microsoft PowerPoint document"
        do
            mt="${entry%%|*}"; rest="${entry#*|}"
            ext="${rest%%|*}"; rest="${rest#*|}"
            nm="${rest%%|*}"; desc="${rest#*|}"
            echo "    - mime_type: ${mt}"
            echo "      extension: ${ext}"
            echo "      name: ${nm}"
            echo "      description: ${desc}"
            echo "      icon: ''"
            echo "      default_app: Euro-Office"
            echo "      allow_creation: true"
        done
        } > "${OCL_CONFIG}/app-registry.yaml"
    fi
fi

# ---- Radicale -------------------------------------------------------------
if [ "${ENABLE_RADICALE}" = "true" ]; then
    act "write ${OCL_CONFIG}/proxy.yaml"
    if live; then
        {
        echo "additional_policies:"
        echo "  - name: default"
        echo "    routes:"
        for ep in "/caldav/|/caldav" "/.well-known/caldav|/caldav" "/carddav/|/carddav" "/.well-known/carddav|/carddav"; do
            endpoint="${ep%%|*}"; script="${ep#*|}"
            echo "      - endpoint: ${endpoint}"
            echo "        backend: http://radicale:5232"
            echo "        remote_user_header: X-Remote-User"
            echo "        skip_x_access_token: true"
            echo "        additional_headers:"
            echo "          - X-Script-Name: ${script}"
        done
        if [ "${ENABLE_RADICALE_WEBUI}" = "true" ]; then
            echo "      - endpoint: /caldav/.web/"
            echo "        backend: http://radicale:5232/"
            echo "        unprotected: true"
            echo "        skip_x_access_token: true"
            echo "        additional_headers:"
            echo "          - X-Script-Name: /caldav"
        fi
        } > "${OCL_CONFIG}/proxy.yaml"
    fi

    act "write ${RAD_CONFIG}/config"
    if live; then
        cat > "${RAD_CONFIG}/config" <<'RADEOF'
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
RADEOF
    fi
fi
say ""

###############################################################################
# [5] Unraid templates
###############################################################################
say "[5] Unraid templates -> ${TEMPLATE_DIR}"

ICON_BASE="https://raw.githubusercontent.com/Nemuritor01/Unraid-Templates/refs/heads/main/templates/docker-icons"

# ---------------------------------------------------------------- OpenCloud
OC_SERVICES=""
[ -n "${WEBOFFICE_URL}" ] && OC_SERVICES="collaboration"

OC_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>OpenCloud</Name>
  <Repository>opencloudeu/opencloud-rolling:latest</Repository>
  <Registry>https://hub.docker.com/r/opencloudeu/opencloud-rolling</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support>https://docs.opencloud.eu/</Support>
  <Project>https://github.com/opencloud-eu/opencloud</Project>
  <Overview>OpenCloud 7.5+ - file sync, sharing and collaboration.&#13;&#10;&#13;&#10;The WOPI/collaboration service runs INSIDE this container and is served on ${OC_URL}/wopi - there is no separate Collaboration container and no wopiserver subdomain.&#13;&#10;&#13;&#10;IMPORTANT: start the web office container FIRST and confirm that its /hosting/discovery answers, otherwise OpenCloud panics at startup and crash-loops.</Overview>
  <Category>Cloud: Productivity: Tools:</Category>
  <WebUI>${OC_URL}</WebUI>
  <TemplateURL/>
  <Icon>${ICON_BASE}/opencloud.png</Icon>
  <ExtraParams>--entrypoint=/bin/sh</ExtraParams>
  <PostArgs>-c \"opencloud init || true; opencloud server\"</PostArgs>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name=\"WebUI Port\" Target=\"9200\" Default=\"9200\" Mode=\"tcp\" Description=\"HTTP port. Also serves /wopi and /collaboration.\" Type=\"Port\" Display=\"always\" Required=\"true\" Mask=\"false\">9200</Config>
  <Config Name=\"Config Directory\" Target=\"/etc/opencloud\" Default=\"${OCL_CONFIG}\" Mode=\"rw\" Description=\"Holds opencloud.yaml, csp.yaml, apps.yaml, proxy.yaml, app-registry.yaml\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${OCL_CONFIG}</Config>
  <Config Name=\"Data Directory\" Target=\"/var/lib/opencloud\" Default=\"${OCL_DATA}\" Mode=\"rw\" Description=\"User data\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${OCL_DATA}</Config>
  <Config Name=\"Apps Directory\" Target=\"/var/lib/opencloud/web/assets/apps\" Default=\"${OCL_APPS}\" Mode=\"rw\" Description=\"Web extensions\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${OCL_APPS}</Config>
  <Config Name=\"OC_URL\" Target=\"OC_URL\" Default=\"${OC_URL}\" Mode=\"\" Description=\"Public URL\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${OC_URL}</Config>
  <Config Name=\"OC_ADD_RUN_SERVICES\" Target=\"OC_ADD_RUN_SERVICES\" Default=\"${OC_SERVICES}\" Mode=\"\" Description=\"Extra services. 'collaboration' = built-in WOPI. Add notifications for e-mail: notifications,collaboration\" Type=\"Variable\" Display=\"always\" Required=\"false\" Mask=\"false\">${OC_SERVICES}</Config>"

if [ "${ENABLE_POCKET_ID}" = "true" ]; then
OC_XML="${OC_XML}
  <Config Name=\"OC_OIDC_ISSUER\" Target=\"OC_OIDC_ISSUER\" Default=\"https://${POCKET_ID_DOMAIN}\" Mode=\"\" Description=\"External OIDC issuer (Pocket-ID)\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">https://${POCKET_ID_DOMAIN}</Config>
  <Config Name=\"OC_EXCLUDE_RUN_SERVICES\" Target=\"OC_EXCLUDE_RUN_SERVICES\" Default=\"idp\" Mode=\"\" Description=\"Disable the built-in IDP (Pocket-ID replaces it)\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">idp</Config>
  <Config Name=\"WEB_OIDC_CLIENT_ID\" Target=\"WEB_OIDC_CLIENT_ID\" Default=\"\" Mode=\"\" Description=\"Client ID of the 'OpenCloud Web' OIDC client in Pocket-ID\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">$(xesc "${POCKET_ID_WEB_CLIENT_ID}")</Config>
  <Config Name=\"WEB_OIDC_METADATA_URL\" Target=\"WEB_OIDC_METADATA_URL\" Default=\"\" Mode=\"\" Description=\"OIDC discovery endpoint\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">https://${POCKET_ID_DOMAIN}/.well-known/openid-configuration</Config>
  <Config Name=\"WEB_OIDC_SCOPE\" Target=\"WEB_OIDC_SCOPE\" Default=\"openid profile email groups\" Mode=\"\" Description=\"Requested OIDC scopes\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">openid profile email groups</Config>
  <Config Name=\"PROXY_OIDC_REWRITE_WELLKNOWN\" Target=\"PROXY_OIDC_REWRITE_WELLKNOWN\" Default=\"true\" Mode=\"\" Description=\"Rewrite the well-known endpoint\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"PROXY_USER_OIDC_CLAIM\" Target=\"PROXY_USER_OIDC_CLAIM\" Default=\"preferred_username\" Mode=\"\" Description=\"OIDC claim used for user mapping\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">preferred_username</Config>
  <Config Name=\"PROXY_USER_CS3_CLAIM\" Target=\"PROXY_USER_CS3_CLAIM\" Default=\"username\" Mode=\"\" Description=\"CS3 claim used for user mapping\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">username</Config>
  <Config Name=\"PROXY_AUTOPROVISION_ACCOUNTS\" Target=\"PROXY_AUTOPROVISION_ACCOUNTS\" Default=\"true\" Mode=\"\" Description=\"Create accounts on first OIDC login\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"PROXY_AUTOPROVISION_CLAIM_USERNAME\" Target=\"PROXY_AUTOPROVISION_CLAIM_USERNAME\" Default=\"preferred_username\" Mode=\"\" Description=\"Claim for the auto-provisioned username\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">preferred_username</Config>
  <Config Name=\"PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD\" Target=\"PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD\" Default=\"none\" Mode=\"\" Description=\"Token verification method (none works with Pocket-ID)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">none</Config>
  <Config Name=\"PROXY_ROLE_ASSIGNMENT_DRIVER\" Target=\"PROXY_ROLE_ASSIGNMENT_DRIVER\" Default=\"oidc\" Mode=\"\" Description=\"Assign roles from OIDC claims\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">oidc</Config>
  <Config Name=\"PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM\" Target=\"PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM\" Default=\"opencloud_role\" Mode=\"\" Description=\"OIDC claim name that carries the OpenCloud role from Pocket-ID group custom claims\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">opencloud_role</Config>
  <Config Name=\"GRAPH_USERNAME_MATCH\" Target=\"GRAPH_USERNAME_MATCH\" Default=\"none\" Mode=\"\" Description=\"Username matching mode\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">none</Config>
  <Config Name=\"GRAPH_ASSIGN_DEFAULT_USER_ROLE\" Target=\"GRAPH_ASSIGN_DEFAULT_USER_ROLE\" Default=\"false\" Mode=\"\" Description=\"Roles come from OIDC instead\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"SETTINGS_SETUP_DEFAULT_ASSIGNMENTS\" Target=\"SETTINGS_SETUP_DEFAULT_ASSIGNMENTS\" Default=\"false\" Mode=\"\" Description=\"No default role assignments\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"FRONTEND_READONLY_USER_ATTRIBUTES\" Target=\"FRONTEND_READONLY_USER_ATTRIBUTES\" Default=\"\" Mode=\"\" Description=\"Attributes managed by the IDP\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">user.onPremisesSamAccountName,user.displayName,user.mail,user.passwordProfile,user.accountEnabled,user.appRoleAssignments</Config>"
else
OC_XML="${OC_XML}
  <Config Name=\"IDM_ADMIN_PASSWORD\" Target=\"IDM_ADMIN_PASSWORD\" Default=\"\" Mode=\"\" Description=\"Admin password for the built-in IDM (also saved in ${SECRETS_FILE})\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"true\">$(xesc "${ADMIN_PW}")</Config>"
fi

if [ -n "${WEBOFFICE_URL}" ]; then
OC_XML="${OC_XML}
  <Config Name=\"COLLABORATION_WOPI_SRC\" Target=\"COLLABORATION_WOPI_SRC\" Default=\"${OC_URL}\" Mode=\"\" Description=\"WOPI public URL = main OpenCloud URL (7.5+)\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${OC_URL}</Config>
  <Config Name=\"COLLABORATION_APP_NAME\" Target=\"COLLABORATION_APP_NAME\" Default=\"${WEBOFFICE_NAME}\" Mode=\"\" Description=\"Web office app name\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${WEBOFFICE_NAME}</Config>
  <Config Name=\"COLLABORATION_APP_PRODUCT\" Target=\"COLLABORATION_APP_PRODUCT\" Default=\"${WEBOFFICE_PRODUCT}\" Mode=\"\" Description=\"Web office product\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${WEBOFFICE_PRODUCT}</Config>
  <Config Name=\"COLLABORATION_APP_ADDR\" Target=\"COLLABORATION_APP_ADDR\" Default=\"${WEBOFFICE_URL}\" Mode=\"\" Description=\"Public URL of the web office. It MUST serve /hosting/discovery before OpenCloud starts.\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${WEBOFFICE_URL}</Config>
  <Config Name=\"COLLABORATION_APP_INSECURE\" Target=\"COLLABORATION_APP_INSECURE\" Default=\"true\" Mode=\"\" Description=\"Skip TLS verification towards the web office\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"COLLABORATION_CS3API_DATAGATEWAY_INSECURE\" Target=\"COLLABORATION_CS3API_DATAGATEWAY_INSECURE\" Default=\"true\" Mode=\"\" Description=\"Skip TLS verification for the CS3 data gateway\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"FRONTEND_APP_HANDLER_SECURE_VIEW_APP_ADDR\" Target=\"FRONTEND_APP_HANDLER_SECURE_VIEW_APP_ADDR\" Default=\"eu.opencloud.api.collaboration\" Mode=\"\" Description=\"Secure view app address\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">eu.opencloud.api.collaboration</Config>"
if [ "${ENABLE_COLLABORA}" = "true" ]; then
OC_XML="${OC_XML}
  <Config Name=\"COLLABORATION_APP_ICON\" Target=\"COLLABORATION_APP_ICON\" Default=\"${WEBOFFICE_URL}/favicon.ico\" Mode=\"\" Description=\"App icon URL\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">${WEBOFFICE_URL}/favicon.ico</Config>
  <Config Name=\"COLLABORA_DOMAIN\" Target=\"COLLABORA_DOMAIN\" Default=\"${WEBOFFICE_DOMAIN}\" Mode=\"\" Description=\"Collabora domain (used in the CSP header)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">${WEBOFFICE_DOMAIN}</Config>"
else
OC_XML="${OC_XML}
  <Config Name=\"COLLABORATION_APP_ICON\" Target=\"COLLABORATION_APP_ICON\" Default=\"\" Mode=\"\" Description=\"App icon URL\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">${WEBOFFICE_URL}/web-apps/apps/documenteditor/main/resources/img/favicon.ico</Config>
  <Config Name=\"COLLABORATION_APP_PROOF_DISABLE\" Target=\"COLLABORATION_APP_PROOF_DISABLE\" Default=\"true\" Mode=\"\" Description=\"Euro-Office does not use WOPI proof keys\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"EURO_OFFICE_DOMAIN\" Target=\"EURO_OFFICE_DOMAIN\" Default=\"${WEBOFFICE_DOMAIN}\" Mode=\"\" Description=\"Euro-Office domain (used in the CSP header)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">${WEBOFFICE_DOMAIN}</Config>"
fi
fi

OC_XML="${OC_XML}
  <Config Name=\"OC_INSECURE\" Target=\"OC_INSECURE\" Default=\"true\" Mode=\"\" Description=\"Skip certificate validation (TLS terminates at your reverse proxy)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"PROXY_HTTP_ADDR\" Target=\"PROXY_HTTP_ADDR\" Default=\"0.0.0.0:9200\" Mode=\"\" Description=\"HTTP listen address\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">0.0.0.0:9200</Config>
  <Config Name=\"PROXY_TLS\" Target=\"PROXY_TLS\" Default=\"false\" Mode=\"\" Description=\"TLS between proxy and OpenCloud\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"PROXY_CSP_CONFIG_FILE_LOCATION\" Target=\"PROXY_CSP_CONFIG_FILE_LOCATION\" Default=\"/etc/opencloud/csp.yaml\" Mode=\"\" Description=\"CSP file inside the container\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">/etc/opencloud/csp.yaml</Config>
  <Config Name=\"Micro Registry Port\" Target=\"9233\" Default=\"9233\" Mode=\"tcp\" Description=\"NATS registry port\" Type=\"Port\" Display=\"advanced\" Required=\"false\" Mask=\"false\">9233</Config>
  <Config Name=\"Gateway gRPC Port\" Target=\"9142\" Default=\"9142\" Mode=\"tcp\" Description=\"Gateway gRPC port\" Type=\"Port\" Display=\"advanced\" Required=\"false\" Mask=\"false\">9142</Config>
  <Config Name=\"GATEWAY_GRPC_ADDR\" Target=\"GATEWAY_GRPC_ADDR\" Default=\"0.0.0.0:9142\" Mode=\"\" Description=\"Gateway gRPC address\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">0.0.0.0:9142</Config>
  <Config Name=\"NATS_NATS_HOST\" Target=\"NATS_NATS_HOST\" Default=\"0.0.0.0\" Mode=\"\" Description=\"NATS host address\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">0.0.0.0</Config>
  <Config Name=\"OC_LOG_LEVEL\" Target=\"OC_LOG_LEVEL\" Default=\"info\" Mode=\"\" Description=\"debug, info, warn, error\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">info</Config>
  <Config Name=\"OC_LOG_COLOR\" Target=\"OC_LOG_COLOR\" Default=\"false\" Mode=\"\" Description=\"Coloured logs\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"IDM_CREATE_DEMO_USERS\" Target=\"IDM_CREATE_DEMO_USERS\" Default=\"false\" Mode=\"\" Description=\"Never enable in production\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"FRONTEND_ARCHIVER_MAX_SIZE\" Target=\"FRONTEND_ARCHIVER_MAX_SIZE\" Default=\"10000000000\" Mode=\"\" Description=\"Max archive size in bytes\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">10000000000</Config>
  <Config Name=\"OC_PASSWORD_POLICY_BANNED_PASSWORDS_LIST\" Target=\"OC_PASSWORD_POLICY_BANNED_PASSWORDS_LIST\" Default=\"banned-password-list.txt\" Mode=\"\" Description=\"Banned password list\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">banned-password-list.txt</Config>
  <Config Name=\"OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD\" Target=\"OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD\" Default=\"true\" Mode=\"\" Description=\"Require a password on public links\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">true</Config>
  <Config Name=\"NOTIFICATIONS_SMTP_HOST\" Target=\"NOTIFICATIONS_SMTP_HOST\" Default=\"\" Mode=\"\" Description=\"SMTP host, e.g. smtp.gmail.com. Also add notifications to OC_ADD_RUN_SERVICES.\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\"/>
  <Config Name=\"NOTIFICATIONS_SMTP_PORT\" Target=\"NOTIFICATIONS_SMTP_PORT\" Default=\"\" Mode=\"\" Description=\"587 with starttls, or 465 with ssltls\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\"/>
  <Config Name=\"NOTIFICATIONS_SMTP_SENDER\" Target=\"NOTIFICATIONS_SMTP_SENDER\" Default=\"\" Mode=\"\" Description=\"Sender address\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\"/>
  <Config Name=\"NOTIFICATIONS_SMTP_USERNAME\" Target=\"NOTIFICATIONS_SMTP_USERNAME\" Default=\"\" Mode=\"\" Description=\"SMTP username\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\"/>
  <Config Name=\"NOTIFICATIONS_SMTP_PASSWORD\" Target=\"NOTIFICATIONS_SMTP_PASSWORD\" Default=\"\" Mode=\"\" Description=\"SMTP password. For Gmail use an App Password.\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"true\"/>
  <Config Name=\"NOTIFICATIONS_SMTP_AUTHENTICATION\" Target=\"NOTIFICATIONS_SMTP_AUTHENTICATION\" Default=\"login\" Mode=\"\" Description=\"Authentication method\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">login</Config>
  <Config Name=\"NOTIFICATIONS_SMTP_ENCRYPTION\" Target=\"NOTIFICATIONS_SMTP_ENCRYPTION\" Default=\"none\" Mode=\"\" Description=\"none, starttls or ssltls\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">none</Config>
  <TailscaleStateDir/>
</Container>"
write_template "my-OpenCloud.xml" "${OC_XML}"

# ---------------------------------------------------------------- Collabora
if [ "${ENABLE_COLLABORA}" = "true" ]; then
COL_ADMIN_PW="$(gen_secret 20)"
COL_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>Collabora</Name>
  <Repository>collabora/code:latest</Repository>
  <Registry>https://hub.docker.com/r/collabora/code</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support>https://www.collaboraonline.com/</Support>
  <Project>https://www.collaboraoffice.com/</Project>
  <Overview>Collabora Online for OpenCloud 7.5+.&#13;&#10;&#13;&#10;Start this container BEFORE OpenCloud and check that ${WEBOFFICE_URL}/hosting/discovery returns HTTP 200.&#13;&#10;&#13;&#10;The entrypoint is NOT overridden anymore. The WOPI proof key is generated on the host by the setup script and mounted read-only.</Overview>
  <Category>Productivity: Tools:</Category>
  <WebUI/>
  <TemplateURL/>
  <Icon>${ICON_BASE}/collabora-opencloud.png</Icon>
  <ExtraParams>--cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined</ExtraParams>
  <PostArgs/>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name=\"HTTP Port\" Target=\"9980\" Default=\"9980\" Mode=\"tcp\" Description=\"Collabora HTTP port\" Type=\"Port\" Display=\"always\" Required=\"true\" Mask=\"false\">9980</Config>
  <Config Name=\"aliasgroup1\" Target=\"aliasgroup1\" Default=\"${OC_URL}\" Mode=\"\" Description=\"WOPI host allowlist. In 7.5+ WOPI is served by OpenCloud, so this is the OpenCloud URL.\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">${OC_URL}</Config>
  <Config Name=\"WOPI Proof Key\" Target=\"/etc/coolwsd/proof_key\" Default=\"${PROOF_KEY}\" Mode=\"ro\" Description=\"Proof key generated by the setup script\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${PROOF_KEY}</Config>
  <Config Name=\"username\" Target=\"username\" Default=\"admin\" Mode=\"\" Description=\"Collabora admin console user\" Type=\"Variable\" Display=\"always\" Required=\"false\" Mask=\"false\">admin</Config>
  <Config Name=\"password\" Target=\"password\" Default=\"\" Mode=\"\" Description=\"Collabora admin console password\" Type=\"Variable\" Display=\"always\" Required=\"false\" Mask=\"true\">$(xesc "${COL_ADMIN_PW}")</Config>
  <Config Name=\"DONT_GEN_SSL_CERT\" Target=\"DONT_GEN_SSL_CERT\" Default=\"YES\" Mode=\"\" Description=\"TLS terminates at your reverse proxy\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">YES</Config>
  <Config Name=\"extra_params\" Target=\"extra_params\" Default=\"\" Mode=\"\" Description=\"Collabora parameters. frame_ancestors and lok_allow.host are your OpenCloud domain.\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">--o:ssl.enable=false --o:ssl.ssl_verification=true --o:ssl.termination=true --o:welcome.enable=false --o:net.frame_ancestors=${OCIS_DOMAIN} --o:net.lok_allow.host[14]=${OCIS_DOMAIN} --o:home_mode.enable=false</Config>
  <Config Name=\"TrueType Fonts\" Target=\"/usr/share/fonts/truetype/more\" Default=\"/usr/share/fonts/truetype\" Mode=\"ro\" Description=\"Host fonts\" Type=\"Path\" Display=\"advanced\" Required=\"false\" Mask=\"false\">/usr/share/fonts/truetype</Config>
  <TailscaleStateDir/>
</Container>"
write_template "my-Collabora.xml" "${COL_XML}"
fi

# -------------------------------------------------------------- Euro-Office
if [ "${ENABLE_EURO_OFFICE}" = "true" ]; then
EUO_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>Euro-Office</Name>
  <Repository>ghcr.io/euro-office/documentserver:latest</Repository>
  <Registry>https://github.com/EURO-office/DocumentServer</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/EURO-office/DocumentServer/issues</Support>
  <Project>https://github.com/EURO-office/DocumentServer</Project>
  <Overview>Euro-Office Document Server (OnlyOffice fork) for OpenCloud 7.5+.&#13;&#10;&#13;&#10;COMMUNITY SUPPORTED ONLY - upstream describes the project as early stage with possible stability issues.&#13;&#10;&#13;&#10;Start this container BEFORE OpenCloud and check that ${WEBOFFICE_URL}/hosting/discovery returns HTTP 200. Needs roughly 2-4 GB RAM and about 2 minutes on first start.</Overview>
  <Category>Productivity: Tools:</Category>
  <WebUI/>
  <TemplateURL/>
  <Icon>https://raw.githubusercontent.com/opencloud-eu/opencloud/main/docs/assets/logo.svg</Icon>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name=\"HTTP Port\" Target=\"80\" Default=\"9900\" Mode=\"tcp\" Description=\"Document server HTTP port\" Type=\"Port\" Display=\"always\" Required=\"true\" Mask=\"false\">9900</Config>
  <Config Name=\"WOPI_ENABLED\" Target=\"WOPI_ENABLED\" Default=\"true\" Mode=\"\" Description=\"Must be true for OpenCloud\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">true</Config>
  <Config Name=\"JWT_SECRET\" Target=\"JWT_SECRET\" Default=\"\" Mode=\"\" Description=\"JWT secret (also saved in ${SECRETS_FILE})\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"true\">$(xesc "${EUO_JWT}")</Config>
  <Config Name=\"USE_UNAUTHORIZED_STORAGE\" Target=\"USE_UNAUTHORIZED_STORAGE\" Default=\"false\" Mode=\"\" Description=\"Only true with self-signed certificates\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">false</Config>
  <Config Name=\"Data Directory\" Target=\"/var/lib/onlyoffice\" Default=\"${EUO_BASE}/data\" Mode=\"rw\" Description=\"Document server data\" Type=\"Path\" Display=\"advanced\" Required=\"false\" Mask=\"false\">${EUO_BASE}/data</Config>
  <Config Name=\"TrueType Fonts\" Target=\"/usr/share/fonts/truetype/more\" Default=\"/usr/share/fonts/truetype\" Mode=\"ro\" Description=\"Host fonts\" Type=\"Path\" Display=\"advanced\" Required=\"false\" Mask=\"false\">/usr/share/fonts/truetype</Config>
  <TailscaleStateDir/>
</Container>"
write_template "my-Euro-Office.xml" "${EUO_XML}"
fi

# ----------------------------------------------------------------- Radicale
if [ "${ENABLE_RADICALE}" = "true" ]; then
RAD_WEBUI_NOTE=""
[ "${ENABLE_RADICALE_WEBUI}" = "true" ] && RAD_WEBUI_NOTE="&#13;&#10;&#13;&#10;Web UI enabled at ${OC_URL}/caldav/.web/ - it has its own authentication."
RAD_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>Radicale</Name>
  <Repository>opencloudeu/radicale:latest</Repository>
  <Registry>https://hub.docker.com/r/opencloudeu/radicale</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support>https://radicale.org/</Support>
  <Project>https://github.com/opencloud-eu/container-radicale</Project>
  <Overview>Radicale CalDAV/CardDAV server for OpenCloud.&#13;&#10;&#13;&#10;Reached through the OpenCloud proxy at ${OC_URL}/caldav/ and /carddav/ - it needs no own domain and no published port. Authentication uses OpenCloud app tokens.${RAD_WEBUI_NOTE}</Overview>
  <Category>Productivity: Tools:</Category>
  <WebUI/>
  <TemplateURL/>
  <Icon>${ICON_BASE}/radicale-opencloud.png</Icon>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires>Needs the OpenCloud container on the same Docker network, with proxy.yaml in its config directory.</Requires>
  <Config Name=\"Data Directory\" Target=\"/var/lib/radicale\" Default=\"${RAD_DATA}\" Mode=\"rw\" Description=\"Calendars and contacts\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${RAD_DATA}</Config>
  <Config Name=\"Config Directory\" Target=\"/etc/radicale\" Default=\"${RAD_CONFIG}\" Mode=\"rw\" Description=\"Must contain the 'config' file created by the setup script\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${RAD_CONFIG}</Config>
  <Config Name=\"RADICALE_LOG_LEVEL\" Target=\"RADICALE_LOG_LEVEL\" Default=\"info\" Mode=\"\" Description=\"debug, info, warning, error\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">info</Config>
  <TailscaleStateDir/>
</Container>"
write_template "my-Radicale.xml" "${RAD_XML}"
fi

# ---------------------------------------------------------------- Pocket-ID
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
PID_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>Pocket-ID</Name>
  <Repository>ghcr.io/pocket-id/pocket-id:v2</Repository>
  <Registry>https://ghcr.io/pocket-id/pocket-id</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/pocket-id/pocket-id/discussions</Support>
  <Project>https://github.com/pocket-id/pocket-id</Project>
  <ReadMe>https://pocket-id.org/docs</ReadMe>
  <Overview>Pocket-ID OIDC provider with passkey authentication, used as the identity provider for OpenCloud.&#13;&#10;&#13;&#10;Create the groups opencloudAdmin, opencloudSpaceAdmin, opencloudUser and opencloudGuest, give each a custom claim 'opencloud_role' whose value is the group name, then create the OIDC clients. Paste the web client ID into the OpenCloud template as WEB_OIDC_CLIENT_ID.</Overview>
  <Category>Network:Privacy Security: Tools:</Category>
  <WebUI>https://${POCKET_ID_DOMAIN}</WebUI>
  <TemplateURL/>
  <Icon>${ICON_BASE}/pocket-id-icon.png</Icon>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name=\"WebUI Port\" Target=\"1411\" Default=\"1411\" Mode=\"tcp\" Description=\"Pocket-ID web interface port\" Type=\"Port\" Display=\"always\" Required=\"true\" Mask=\"false\">1411</Config>
  <Config Name=\"APP_URL\" Target=\"APP_URL\" Default=\"https://${POCKET_ID_DOMAIN}\" Mode=\"\" Description=\"Public URL. Must be HTTPS for passkeys.\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">https://${POCKET_ID_DOMAIN}</Config>
  <Config Name=\"ENCRYPTION_KEY\" Target=\"ENCRYPTION_KEY\" Default=\"\" Mode=\"\" Description=\"Required in v2. Also saved in ${SECRETS_FILE}.\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"true\">$(xesc "${PID_KEY}")</Config>
  <Config Name=\"TRUST_PROXY\" Target=\"TRUST_PROXY\" Default=\"true\" Mode=\"\" Description=\"True when running behind a reverse proxy\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">true</Config>
  <Config Name=\"Data Path\" Target=\"/app/data\" Default=\"${PID_BASE}/data\" Mode=\"rw\" Description=\"Database, uploads and configuration\" Type=\"Path\" Display=\"always\" Required=\"true\" Mask=\"false\">${PID_BASE}/data</Config>
  <Config Name=\"PUID\" Target=\"PUID\" Default=\"99\" Mode=\"\" Description=\"User ID (99 = nobody on Unraid)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">99</Config>
  <Config Name=\"PGID\" Target=\"PGID\" Default=\"100\" Mode=\"\" Description=\"Group ID (100 = users on Unraid)\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">100</Config>
  <TailscaleStateDir/>
</Container>"
write_template "my-Pocket-ID.xml" "${PID_XML}"
fi
say ""

###############################################################################
# [6] SWAG configs (optional)
###############################################################################
say "[6] SWAG proxy configs"
if [ "${GENERATE_SWAG_CONFS}" != "true" ]; then
    say "    skipped (GENERATE_SWAG_CONFS=false)"
elif [ ! -d "${SWAG_PROXY_CONFS}" ]; then
    say "    ${SWAG_PROXY_CONFS} not found - skipped"
else
    OC_SUB="${OCIS_DOMAIN%%.*}"
    OC_CONF_NAME="${OC_SUB}.subdomain.conf"
    OC_CONF_CONTENT="## OpenCloud 7.5+ - generated ${TS}
## Serves the web UI plus /wopi and /collaboration on the same domain.
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${OC_SUB}.*;

    include /config/nginx/ssl.conf;

    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;

    location / {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;

        set \$upstream_app OpenCloud;
        set \$upstream_port 9200;
        set \$upstream_proto http;
        proxy_pass \$upstream_proto://\$upstream_app:\$upstream_port;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
}"
    write_swag_conf "${OC_CONF_NAME}" "${OC_CONF_CONTENT}" "${OVERWRITE_SWAG_OPENCLOUD}"

    if [ -n "${WEBOFFICE_DOMAIN}" ]; then
        WO_SUB="${WEBOFFICE_DOMAIN%%.*}"
        WO_CONF_NAME="${WO_SUB}.subdomain.conf"
        WO_CONTAINER="Collabora"; WO_PORT="9980"
        [ "${ENABLE_EURO_OFFICE}" = "true" ] && { WO_CONTAINER="Euro-Office"; WO_PORT="80"; }
        WO_CONF_CONTENT="## ${WEBOFFICE_NAME} for OpenCloud 7.5+ - generated ${TS}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${WO_SUB}.*;

    include /config/nginx/ssl.conf;

    client_max_body_size 100M;

    location / {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;

        set \$upstream_app ${WO_CONTAINER};
        set \$upstream_port ${WO_PORT};
        set \$upstream_proto http;
        proxy_pass \$upstream_proto://\$upstream_app:\$upstream_port;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_read_timeout 3600s;
    }
}"
        write_swag_conf "${WO_CONF_NAME}" "${WO_CONF_CONTENT}" "${OVERWRITE_SWAG_WEBOFFICE}"
    fi
fi
say ""

###############################################################################
# Summary
###############################################################################
say "============================================================"
if [ "${DRY_RUN}" = "true" ]; then
    say " DRY RUN complete - nothing was written."
    say " Review the plan above, then set DRY_RUN=\"false\" and run again."
    say "============================================================"
    exit 0
fi
say " Setup complete"
say "============================================================"
say ""
say " Templates in ${TEMPLATE_DIR}:"
for t in my-OpenCloud.xml my-Collabora.xml my-Euro-Office.xml my-Radicale.xml my-Pocket-ID.xml; do
    [ -f "${TEMPLATE_DIR}/${t}" ] && say "   ${t}"
    [ -f "${TEMPLATE_DIR}/${t}.new" ] && say "   ${t}.new   (existing template kept - compare and rename manually)"
done
say ""
say " Secrets: ${SECRETS_FILE}"
[ "${ENABLE_POCKET_ID}" != "true" ] && say "   admin password: ${ADMIN_PW}"
say ""
say " DNS / certificates needed for:"
say "   ${OCIS_DOMAIN}"
[ -n "${WEBOFFICE_DOMAIN}" ] && say "   ${WEBOFFICE_DOMAIN}"
[ "${ENABLE_POCKET_ID}" = "true" ] && say "   ${POCKET_ID_DOMAIN}"
say "   (no wopiserver domain - WOPI lives on ${OCIS_DOMAIN})"
say ""
say " START THE CONTAINERS IN THIS ORDER:"
n=1
if [ "${ENABLE_POCKET_ID}" = "true" ]; then
    say "   ${n}. Pocket-ID -> create groups, claims and OIDC clients, then put the"
    say "      web client ID into POCKET_ID_WEB_CLIENT_ID and re-run this script"
    n=$((n+1))
fi
if [ -n "${WEBOFFICE_DOMAIN}" ]; then
    say "   ${n}. ${WEBOFFICE_NAME}"
    n=$((n+1))
    say "   ${n}. Verify:  curl -sk -o /dev/null -w '%{http_code}\\n' ${WEBOFFICE_URL}/hosting/discovery"
    say "      It MUST return 200 before you start OpenCloud."
    n=$((n+1))
fi
say "   ${n}. OpenCloud"
n=$((n+1))
[ "${ENABLE_RADICALE}" = "true" ] && say "   ${n}. Radicale"
say ""
say " In Unraid: Docker -> Add Container -> pick the template under"
say " \"User templates\" -> review -> Apply."
say ""
