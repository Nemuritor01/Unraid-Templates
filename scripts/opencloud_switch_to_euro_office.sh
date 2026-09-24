#!/bin/bash
###############################################################################
#  OpenCloud 7.5+  -  Switch web office: Collabora  ->  Euro-Office
#                     (and back, with MODE="rollback")
#  Unraid / Docker templates, NOT docker compose
###############################################################################
#
#  PREREQUISITE: your install is already on the 7.5 architecture, i.e. the
#  WOPI service runs INSIDE the OpenCloud container
#  (OC_ADD_RUN_SERVICES contains "collaboration"). If not, run
#  opencloud_v75_migration.sh first.
#
#  Collabora and Euro-Office are MUTUALLY EXCLUSIVE: both are served by the
#  same embedded collaboration service. This script swaps the backend.
#
#  MODE="switch" (LIVE) does:
#    1. Backs up csp.yaml, app-registry.yaml, templates, autostart list
#    2. Writes app-registry.yaml (all office formats -> Euro-Office)
#    3. Adds the Euro-Office domain to csp.yaml (keeps Collabora entries)
#    4. Points the OpenCloud template at Euro-Office
#    5. Creates the Unraid user template "my-Euro-Office.xml" (JWT generated)
#    6. Optionally installs the SWAG proxy conf and reloads SWAG
#    7. Stops Collabora + removes it from autostart (NOT deleted)
#    8. Recreates OpenCloud
#
#  MODE="rollback" restores the files from the newest switch backup,
#  re-enables Collabora and stops Euro-Office.
#
#  No file data is touched. Default is DRY_RUN="true".
###############################################################################
#name=OpenCloud Switch to Euro-Office
#description=Switches an OpenCloud 7.5 install from Collabora to Euro-Office (with rollback)
#arrayStarted=true

###############################################################################
#  USER CONFIGURATION
###############################################################################

# "switch" = Collabora -> Euro-Office      "rollback" = back to Collabora
MODE="switch"

# Your Euro-Office subdomain (no https://). Needs a DNS record + SWAG conf.
EURO_OFFICE_DOMAIN="euro-office.yourdomain.com"

# Container names as shown on the Unraid Docker tab
OPENCLOUD_CONTAINER="OpenCloud"
COLLABORA_CONTAINER="Collabora"
EURO_OFFICE_CONTAINER="Euro-Office"

# Docker network shared with OpenCloud and SWAG
NETWORK_NAME="opencloud-net"

# Host port for Euro-Office (container listens on 80). Only needed for
# direct LAN access; SWAG reaches it by container name on the network.
EURO_OFFICE_HOST_PORT="8085"

# Paths
OCL_CONFIG="/mnt/user/appdata/opencloud/config"
BACKUP_BASE="/mnt/user/appdata/opencloud"

# SWAG: install euro-office.subdomain.conf automatically?
INSTALL_SWAG_CONF="true"
SWAG_CONTAINER="swag"
SWAG_PROXY_CONFS="/mnt/user/appdata/swag/nginx/proxy-confs"

# true = only show what would happen (DEFAULT)   false = apply
DRY_RUN="true"

# Recreate OpenCloud from the patched template at the end?
RECREATE_CONTAINERS="true"

###############################################################################
#  DO NOT EDIT BELOW THIS LINE
###############################################################################

TPL_DIR="/boot/config/plugins/dockerMan/templates-user"
TPL_OC="${TPL_DIR}/my-${OPENCLOUD_CONTAINER}.xml"
TPL_COL="${TPL_DIR}/my-${COLLABORA_CONTAINER}.xml"
TPL_EO="${TPL_DIR}/my-${EURO_OFFICE_CONTAINER}.xml"
CSP="${OCL_CONFIG}/csp.yaml"
APPREG="${OCL_CONFIG}/app-registry.yaml"
JWT_FILE="${OCL_CONFIG}/euro-office-jwt-secret.txt"
AUTOSTART="/var/lib/docker/unraid-autostart"
RECREATE_HELPER="/usr/local/emhttp/plugins/dynamix.docker.manager/scripts/update_container"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_BASE}/euro-office-switch-backup-${TS}"
EO_HOST="${EURO_OFFICE_DOMAIN#https://}"; EO_HOST="${EO_HOST%/}"
EO_URL="https://${EO_HOST}"
EO_SUB="${EO_HOST%%.*}"

PLAN=()
plan() { PLAN+=("$1"); echo "    -> $1"; }
live() { [ "${DRY_RUN}" != "true" ]; }

# ---- Unraid template helpers (each <Config> is a single line) --------------
get_cfg() { sed -n -E "s|.*<Config [^>]*Target=\"$2\"[^>]*>([^<]*)</Config>.*|\1|p" "$1" 2>/dev/null | head -1; }
has_cfg() { grep -qE "<Config [^>]*Target=\"$2\"" "$1" 2>/dev/null; }
sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }
set_cfg() {
    local f="$1" t="$2" v="$3" type="$4" disp="$5" desc="$6" mode="${7:-}" ev
    ev="$(sed_escape "$v")"
    if has_cfg "$f" "$t"; then
        sed -i -E "/<Config [^>]*Target=\"${t}\"[^>]*\/>/ s|/>|>${ev}</Config>|" "$f"
        sed -i -E "s|(<Config [^>]*Target=\"${t}\"[^>]*>)[^<]*(</Config>)|\1${ev}\2|" "$f"
    else
        local line="  <Config Name=\"${t}\" Target=\"${t}\" Default=\"${v}\" Mode=\"${mode}\" Description=\"${desc}\" Type=\"${type}\" Display=\"${disp}\" Required=\"false\" Mask=\"false\">${v}</Config>"
        sed -i -E "s|^([[:space:]]*)</Container>|$(sed_escape "$line")\n</Container>|" "$f"
    fi
}

# csp_add <directive> <entry>   - add entry to a directive if missing
csp_add() {
    local dir="$1" entry="$2"
    if ! grep -qE "^  ${dir}:" "${CSP}"; then
        printf "  %s:\n    - '%s'\n" "${dir}" "${entry}" >> "${CSP}"
        return
    fi
    local present
    present="$(awk -v d="  ${dir}:" -v e="${entry}" '/^  [a-z-]+:/{s=($0==d)?1:0} s&&index($0,e){print "yes";exit}' "${CSP}")"
    [ "${present}" = "yes" ] && return
    awk -v d="  ${dir}:" -v e="    - '${entry}'" '{print} $0==d&&!x{print e;x=1}' "${CSP}" > "${CSP}.tmp" && mv "${CSP}.tmp" "${CSP}"
}

echo "============================================================"
echo " OpenCloud web office switch - MODE: ${MODE}"
[ "${DRY_RUN}" = "true" ] && echo " DRY RUN - nothing will be changed" || echo " LIVE"
echo "============================================================"
echo ""

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
[ -f "${TPL_OC}" ] || { echo "ERROR: ${TPL_OC} not found"; exit 1; }

###############################################################################
#  ROLLBACK
###############################################################################
if [ "${MODE}" = "rollback" ]; then
    # newest backup whose saved template is NOT already on Euro-Office
    LAST=""
    for d in $(ls -1d "${BACKUP_BASE}"/euro-office-switch-backup-* 2>/dev/null | sort -r); do
        if [ -f "${d}/my-${OPENCLOUD_CONTAINER}.xml" ] && \
           [ "$(get_cfg "${d}/my-${OPENCLOUD_CONTAINER}.xml" COLLABORATION_APP_NAME)" != "Euro-Office" ]; then
            LAST="${d}"; break
        fi
    done
    [ -z "${LAST}" ] && { echo "ERROR: no pre-switch backup found in ${BACKUP_BASE}"; exit 1; }
    echo "[R] Restoring from ${LAST}"
    plan "restore my-${OPENCLOUD_CONTAINER}.xml"
    [ -f "${LAST}/csp.yaml" ] && plan "restore csp.yaml"
    if [ -f "${LAST}/app-registry.yaml" ]; then plan "restore previous app-registry.yaml"
    else plan "remove app-registry.yaml (did not exist before)"; fi
    [ -f "${LAST}/unraid-autostart" ] && plan "restore autostart list (re-enables ${COLLABORA_CONTAINER})"
    plan "stop ${EURO_OFFICE_CONTAINER}, start ${COLLABORA_CONTAINER}, recreate ${OPENCLOUD_CONTAINER}"
    if live; then
        cp "${LAST}/my-${OPENCLOUD_CONTAINER}.xml" "${TPL_OC}"
        [ -f "${LAST}/csp.yaml" ] && cp "${LAST}/csp.yaml" "${CSP}"
        if [ -f "${LAST}/app-registry.yaml" ]; then cp "${LAST}/app-registry.yaml" "${APPREG}"; else rm -f "${APPREG}"; fi
        [ -f "${LAST}/unraid-autostart" ] && cp "${LAST}/unraid-autostart" "${AUTOSTART}"
        docker stop "${EURO_OFFICE_CONTAINER}" >/dev/null 2>&1
        docker start "${COLLABORA_CONTAINER}" >/dev/null 2>&1
        if [ "${RECREATE_CONTAINERS}" = "true" ] && [ -x "${RECREATE_HELPER}" ]; then
            "${RECREATE_HELPER}" "${OPENCLOUD_CONTAINER}"
        else
            echo "    Manual: Docker tab -> edit ${OPENCLOUD_CONTAINER} -> Apply"
        fi
        echo ""
        echo " Rolled back. The ${EURO_OFFICE_CONTAINER} container and its template"
        echo " were kept; remove them in the Docker tab if you no longer need them."
    else
        echo ""
        echo " DRY RUN - set DRY_RUN=\"false\" to roll back."
    fi
    exit 0
fi

[ "${MODE}" != "switch" ] && { echo "ERROR: MODE must be 'switch' or 'rollback'"; exit 1; }

###############################################################################
#  SWITCH - pre-flight
###############################################################################
echo "[0] Pre-flight"
FAIL="false"
if [ "${EO_HOST}" = "euro-office.yourdomain.com" ] || [ -z "${EO_HOST}" ]; then
    echo "    ERROR: set EURO_OFFICE_DOMAIN"; FAIL="true"
fi
SVC="$(get_cfg "${TPL_OC}" OC_ADD_RUN_SERVICES)"
case ",${SVC}," in
    *,collaboration,*) echo "    OC_ADD_RUN_SERVICES='${SVC}' - ok (7.5 architecture)";;
    *) echo "    ERROR: OC_ADD_RUN_SERVICES does not contain 'collaboration'."
       echo "           Run opencloud_v75_migration.sh first."; FAIL="true";;
esac
OC_URL="$(get_cfg "${TPL_OC}" OC_URL)"; OC_URL="${OC_URL%/}"
[ -z "${OC_URL}" ] && { echo "    ERROR: OC_URL not found in template"; FAIL="true"; }
[ -f "${CSP}" ] || { echo "    ERROR: ${CSP} not found"; FAIL="true"; }
CUR_APP="$(get_cfg "${TPL_OC}" COLLABORATION_APP_NAME)"
[ "${CUR_APP}" = "Euro-Office" ] && echo "    NOTE: OpenCloud already points at Euro-Office - re-applying is safe"
[ -f "${TPL_EO}" ] && echo "    NOTE: ${TPL_EO} exists - it will be kept (JWT unchanged)"
[ "${FAIL}" = "true" ] && { echo ""; echo "Aborting - nothing changed."; exit 1; }
echo "    OpenCloud URL:   ${OC_URL}"
echo "    Euro-Office URL: ${EO_URL}"
echo ""

###############################################################################
#  [1] Backup
###############################################################################
echo "[1] Backup"
if [ "${CUR_APP}" = "Euro-Office" ]; then
    echo "    already switched - keeping the original pre-switch backup (no new one)"
else
plan "backup csp.yaml, app-registry.yaml, templates, autostart -> ${BACKUP_DIR}"
fi
if live && [ "${CUR_APP}" != "Euro-Office" ]; then
    mkdir -p "${BACKUP_DIR}"
    cp "${CSP}" "${BACKUP_DIR}/"
    [ -f "${APPREG}" ] && cp "${APPREG}" "${BACKUP_DIR}/"
    cp "${TPL_OC}" "${BACKUP_DIR}/"
    [ -f "${TPL_COL}" ] && cp "${TPL_COL}" "${BACKUP_DIR}/"
    [ -f "${AUTOSTART}" ] && cp "${AUTOSTART}" "${BACKUP_DIR}/unraid-autostart"
fi
echo ""

###############################################################################
#  [2] app-registry.yaml
#  The config dir is mounted at /etc/opencloud, so OpenCloud picks this file
#  up without an extra mount. default_app must equal COLLABORATION_APP_NAME.
###############################################################################
echo "[2] app-registry.yaml"
plan "write ${APPREG} (odt/ods/odp/docx/xlsx/pptx -> Euro-Office)"
if live; then
cat > "${APPREG}" <<'EOF'
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
fi
echo ""

###############################################################################
#  [3] CSP  (Collabora entries are kept so rollback needs no CSP edit)
###############################################################################
echo "[3] CSP"
plan "csp.yaml: add ${EO_URL}/ to frame-src, img-src, connect-src (+ wss)"
grep -qE '^  form-action:' "${CSP}" && plan "csp.yaml: add ${EO_URL}/ to form-action"
if live; then
    csp_add frame-src   "${EO_URL}/"
    csp_add img-src     "${EO_URL}/"
    csp_add connect-src "${EO_URL}/"
    csp_add connect-src "wss://${EO_HOST}/"
    grep -qE '^  form-action:' "${CSP}" && csp_add form-action "${EO_URL}/"
fi
echo ""

###############################################################################
#  [4] OpenCloud template -> Euro-Office
###############################################################################
echo "[4] OpenCloud template"
plan "COLLABORATION_APP_NAME=Euro-Office, APP_PRODUCT=OnlyOffice, APP_ADDR=${EO_URL}"
plan "COLLABORATION_APP_PROOF_DISABLE=true, EURO_OFFICE_DOMAIN=${EO_HOST}"
if live; then
    set_cfg "${TPL_OC}" COLLABORATION_APP_NAME "Euro-Office" Variable always "Web office app name"
    set_cfg "${TPL_OC}" COLLABORATION_APP_PRODUCT "OnlyOffice" Variable always "Web office product"
    set_cfg "${TPL_OC}" COLLABORATION_APP_ADDR "${EO_URL}" Variable always "Public Euro-Office URL"
    set_cfg "${TPL_OC}" COLLABORATION_APP_ICON "${EO_URL}/web-apps/apps/documenteditor/main/resources/img/favicon.ico" Variable advanced "App icon"
    set_cfg "${TPL_OC}" COLLABORATION_APP_PROOF_DISABLE "true" Variable advanced "Euro-Office does not use WOPI proof keys"
    set_cfg "${TPL_OC}" COLLABORATION_APP_INSECURE "true" Variable advanced "Skip TLS verify to web office"
    set_cfg "${TPL_OC}" EURO_OFFICE_DOMAIN "${EO_HOST}" Variable advanced "Euro-Office domain (CSP)"
fi
echo ""

###############################################################################
#  [5] Euro-Office user template
###############################################################################
echo "[5] Euro-Office template"
if [ -f "${TPL_EO}" ]; then
    echo "    ${TPL_EO} already exists - keeping it"
else
    if [ -s "${JWT_FILE}" ]; then
        JWT="$(sed -n 's/^EURO_OFFICE_JWT_SECRET=//p' "${JWT_FILE}")"
        echo "    reusing JWT secret from ${JWT_FILE}"
    else
        JWT="$(head -c 48 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)"
        plan "generate JWT secret -> ${JWT_FILE}"
    fi
    plan "create ${TPL_EO}"
    if live; then
        [ -s "${JWT_FILE}" ] || { printf 'EURO_OFFICE_JWT_SECRET=%s\n' "${JWT}" > "${JWT_FILE}"; chmod 600 "${JWT_FILE}"; }
        cat > "${TPL_EO}" <<EOF
<?xml version="1.0"?>
<Container version="2">
  <Name>${EURO_OFFICE_CONTAINER}</Name>
  <Repository>ghcr.io/euro-office/documentserver:latest</Repository>
  <Registry>https://github.com/EURO-office/DocumentServer</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/EURO-office/DocumentServer/issues</Support>
  <Project>https://github.com/EURO-office/DocumentServer</Project>
  <Overview>Euro-Office Document Server for OpenCloud 7.5+ (WOPI). Mutually exclusive with Collabora.</Overview>
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
  <Config Name="HTTP Port" Target="80" Default="8085" Mode="tcp" Description="Euro-Office HTTP port" Type="Port" Display="always" Required="true" Mask="false">${EURO_OFFICE_HOST_PORT}</Config>
  <Config Name="WOPI_ENABLED" Target="WOPI_ENABLED" Default="true" Mode="" Description="Must be true for OpenCloud" Type="Variable" Display="always" Required="true" Mask="false">true</Config>
  <Config Name="JWT_SECRET" Target="JWT_SECRET" Default="" Mode="" Description="JWT secret (saved in ${JWT_FILE})" Type="Variable" Display="always" Required="true" Mask="true">${JWT}</Config>
  <Config Name="USE_UNAUTHORIZED_STORAGE" Target="USE_UNAUTHORIZED_STORAGE" Default="false" Mode="" Description="true only for self-signed certificates" Type="Variable" Display="advanced" Required="false" Mask="false">false</Config>
  <Config Name="TrueType Fonts" Target="/usr/share/fonts/truetype/more" Default="/usr/share/fonts/truetype" Mode="ro" Description="Host fonts" Type="Path" Display="advanced" Required="false" Mask="false">/usr/share/fonts/truetype</Config>
  <TailscaleStateDir/>
</Container>
EOF
    fi
fi
echo ""

###############################################################################
#  [6] SWAG proxy conf
###############################################################################
echo "[6] SWAG"
SWAG_FILE="${SWAG_PROXY_CONFS}/${EO_SUB}.subdomain.conf"
if [ "${INSTALL_SWAG_CONF}" != "true" ]; then
    echo "    skipped (INSTALL_SWAG_CONF=false) - add a proxy for ${EO_HOST} -> ${EURO_OFFICE_CONTAINER}:80"
elif [ ! -d "${SWAG_PROXY_CONFS}" ]; then
    echo "    ${SWAG_PROXY_CONFS} not found - add a proxy for ${EO_HOST} -> ${EURO_OFFICE_CONTAINER}:80 yourself"
elif [ -f "${SWAG_FILE}" ]; then
    echo "    ${SWAG_FILE} exists - keeping it"
else
    plan "create ${SWAG_FILE} and reload ${SWAG_CONTAINER}"
    if live; then
        cat > "${SWAG_FILE}" <<EOF
## Euro-Office for OpenCloud 7.5+ (generated ${TS})
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${EO_SUB}.*;

    include /config/nginx/ssl.conf;

    client_max_body_size 100M;

    location / {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;

        set \$upstream_app ${EURO_OFFICE_CONTAINER};
        set \$upstream_port 80;
        set \$upstream_proto http;
        proxy_pass \$upstream_proto://\$upstream_app:\$upstream_port;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto https;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }
}
EOF
        if docker inspect "${SWAG_CONTAINER}" >/dev/null 2>&1; then
            if docker exec "${SWAG_CONTAINER}" nginx -t >/dev/null 2>&1; then
                docker exec "${SWAG_CONTAINER}" nginx -s reload >/dev/null 2>&1 && echo "    SWAG reloaded"
            else
                echo "    WARNING: nginx -t failed - removing generated conf, SWAG left untouched"
                rm -f "${SWAG_FILE}"
            fi
        fi
    fi
fi
echo ""

###############################################################################
#  [7] Retire Collabora (stop + no autostart, kept for rollback)
###############################################################################
echo "[7] Collabora"
if docker inspect "${COLLABORA_CONTAINER}" >/dev/null 2>&1; then
    plan "stop ${COLLABORA_CONTAINER} and remove it from autostart (kept for rollback)"
    if live; then
        docker stop "${COLLABORA_CONTAINER}" >/dev/null 2>&1
        [ -f "${AUTOSTART}" ] && sed -i -E "/^${COLLABORA_CONTAINER}([[:space:]].*)?$/d" "${AUTOSTART}"
    fi
else
    echo "    not present - ok"
fi
echo ""

###############################################################################
#  [8] Recreate OpenCloud
###############################################################################
echo "[8] Recreate OpenCloud"
if [ "${RECREATE_CONTAINERS}" = "true" ] && [ -x "${RECREATE_HELPER}" ]; then
    plan "recreate ${OPENCLOUD_CONTAINER} via Unraid helper"
    live && "${RECREATE_HELPER}" "${OPENCLOUD_CONTAINER}"
else
    echo "    Manual: Docker tab -> edit ${OPENCLOUD_CONTAINER} -> Apply"
fi
echo ""

###############################################################################
#  Summary
###############################################################################
echo "============================================================"
if [ "${DRY_RUN}" = "true" ]; then
    echo " DRY RUN complete - ${#PLAN[@]} planned change(s), nothing modified."
    echo " Set DRY_RUN=\"false\" to apply."
else
    echo " Switch applied. Backup: ${BACKUP_DIR}"
    echo ""
    echo " REMAINING MANUAL STEPS"
    echo "  1. DNS: create a record for ${EO_HOST} (skip if you use a wildcard)."
    echo "  2. Create the Euro-Office container:"
    echo "       Docker tab -> Add Container -> Template: ${EURO_OFFICE_CONTAINER}"
    echo "       (under 'User templates') -> Apply"
    echo "     First start takes ~2 minutes; give it 2-4 GB RAM."
    echo "  3. Verify:"
    echo "       curl -s -o /dev/null -w '%{http_code}\\n' ${EO_URL}/hosting/discovery   (expect 200)"
    echo "       curl -s -o /dev/null -w '%{http_code}\\n' ${OC_URL}/wopi               (expect 418)"
    echo "       Open a .docx in OpenCloud."
    echo ""
    echo " Undo: set MODE=\"rollback\" and DRY_RUN=\"false\", run again."
fi
echo "============================================================"
