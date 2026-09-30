#!/bin/bash
###############################################################################
#  OpenCloud 8.x - enable real-time collaborative editing (Yjs)
#
#  WHAT THIS DOES:
#    * writes a ready-to-use Unraid template  my-YJS.xml   (opencloudeu/yjs)
#    * adds WEB_OPTION_YJS_SERVER_URL=wss://<oc-domain>/yjs to my-OpenCloud.xml
#    * adds the /yjs route to the OpenCloud proxy.yaml (radicale routes kept)
#    * adds an /yjs WebSocket location to the SWAG proxy conf (if present)
#
#  WHY: OpenCloud 8.x can do real-time collaborative editing in the built-in
#  Editor (Markdown / .ocnote). It is OFF until a Yjs server URL is set. The
#  Yjs service is a separate container that acts as a pure WebSocket relay and
#  stores nothing.
#
#  AFTER RUNNING (LIVE mode):
#    1. Docker -> Add Container -> "YJS" (user template) -> Apply
#    2. Docker -> edit "OpenCloud" -> Apply   (picks up the new env var)
#    3. If you use SWAG: reload SWAG (or restart the container)
#    4. Optional: ./opencloud-enable-yjs.sh already patched the SWAG conf
#
#  It does NOT touch your file data.
#
#  RUN IT FIRST WITH DRY_RUN="true" (default) and read the output.
###############################################################################
#name=OpenCloud 8.x - Enable Yjs (collaborative editing)
#description=Adds the Yjs container template, OpenCloud env var, proxy route and SWAG config
#arrayStarted=true

###############################################################################
#  USER CONFIGURATION
###############################################################################

# Container name exactly as shown on the Unraid Docker tab
OPENCLOUD_CONTAINER="OpenCloud"
YJS_CONTAINER="YJS"
YJS_IMAGE="opencloudeu/yjs:1.0.0"

# Leave empty to auto-detect from my-OpenCloud.xml
OC_URL_OVERRIDE=""              # e.g. https://opencloud.example.com
NETWORK_NAME_OVERRIDE=""        # e.g. opencloud-net

TEMPLATE_DIR="/boot/config/plugins/dockerMan/templates-user"
OCL_CONFIG="/mnt/user/appdata/opencloud/config"

# SWAG (optional). Set PATCH_SWAG_CONF="false" if you use another proxy.
SWAG_PROXY_CONFS="/mnt/user/appdata/swag/nginx/proxy-confs"
PATCH_SWAG_CONF="true"

# false = keep an existing my-YJS.xml and write my-YJS.xml.new instead
OVERWRITE_YJS_TEMPLATE="false"

# true  = only report what would change (DEFAULT - run this first)
# false = apply
DRY_RUN="true"

###############################################################################
#  DO NOT EDIT BELOW THIS LINE
###############################################################################

TPL_OC="${TEMPLATE_DIR}/my-${OPENCLOUD_CONTAINER}.xml"
TPL_YJS="${TEMPLATE_DIR}/my-${YJS_CONTAINER}.xml"
PROXY_YAML="${OCL_CONFIG}/proxy.yaml"
TS="$(date +%Y%m%d-%H%M%S)"
PLAN=()
plan() { PLAN+=("$1"); echo "    -> $1"; }
live() { [ "${DRY_RUN}" != "true" ]; }

get_cfg() {
    sed -n -E "s|.*<Config [^>]*Target=\"$2\"[^>]*>([^<]*)</Config>.*|\1|p" "$1" 2>/dev/null | head -1
}
has_cfg() { grep -qE "<Config [^>]*Target=\"$2\"" "$1" 2>/dev/null; }
get_tag() { sed -n -E "s|.*<${2}>([^<]*)</${2}>.*|\1|p" "$1" 2>/dev/null | head -1; }
sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

set_cfg() {
    local f="$1" t="$2" v="$3" type="$4" disp="$5" desc="$6" mode="${7:-}"
    local ev; ev="$(sed_escape "$v")"
    if has_cfg "$f" "$t"; then
        sed -i -E "/<Config [^>]*Target=\"${t}\"[^>]*\/>/ s|/>|>${ev}</Config>|" "$f"
        sed -i -E "s|(<Config [^>]*Target=\"${t}\"[^>]*>)[^<]*(</Config>)|\1${ev}\2|" "$f"
    else
        local line="  <Config Name=\"${t}\" Target=\"${t}\" Default=\"${v}\" Mode=\"${mode}\" Description=\"${desc}\" Type=\"${type}\" Display=\"${disp}\" Required=\"false\" Mask=\"false\">${v}</Config>"
        local el; el="$(sed_escape "$line")"
        sed -i -E "s|^([[:space:]]*)</Container>|${el}\n</Container>|" "$f"
    fi
}

echo "============================================================"
echo " OpenCloud 8.x - Enable Yjs (collaborative editing)"
[ "${DRY_RUN}" = "true" ] && echo " MODE: DRY RUN - nothing will be changed" || echo " MODE: LIVE"
echo "============================================================"
echo ""

###############################################################################
# [0] Pre-flight
###############################################################################
echo "[0] Pre-flight checks"
FAIL="false"
command -v docker >/dev/null 2>&1 || { echo "    ERROR: docker not found"; FAIL="true"; }
[ -f "${TPL_OC}" ] || { echo "    ERROR: template not found: ${TPL_OC}"; FAIL="true"; }
[ "${FAIL}" = "true" ] && { echo ""; echo "Aborting - nothing changed."; exit 1; }

OC_URL="${OC_URL_OVERRIDE:-$(get_cfg "${TPL_OC}" OC_URL)}"
OC_URL="${OC_URL%/}"
OCIS_DOMAIN="${OC_URL#https://}"; OCIS_DOMAIN="${OCIS_DOMAIN#http://}"; OCIS_DOMAIN="${OCIS_DOMAIN%%/*}"
NETWORK_NAME="${NETWORK_NAME_OVERRIDE:-$(get_tag "${TPL_OC}" Network)}"
[ -z "${NETWORK_NAME}" ] && NETWORK_NAME="opencloud-net"
OC_CONF_NAME="$(printf '%s' "${OCIS_DOMAIN}" | cut -d. -f1).subdomain.conf"
OC_CONF="${SWAG_PROXY_CONFS}/${OC_CONF_NAME}"

if [ -z "${OCIS_DOMAIN}" ]; then
    echo "    ERROR: could not detect the OpenCloud domain. Set OC_URL_OVERRIDE."
    exit 1
fi
echo "    OpenCloud template:  ${TPL_OC}"
echo "    OpenCloud URL:       ${OC_URL}"
echo "    Domain:              ${OCIS_DOMAIN}"
echo "    Docker network:      ${NETWORK_NAME}"
echo "    Yjs image:           ${YJS_IMAGE}"
echo "    proxy.yaml:          ${PROXY_YAML}"
echo "    SWAG conf:           ${OC_CONF} $([ -f "${OC_CONF}" ] && echo '(found)' || echo '(not found)')"
echo ""

###############################################################################
# [1] Backup
###############################################################################
echo "[1] Backup"
plan "backup ${TPL_OC} and ${PROXY_YAML} (*.bak-${TS})"
if live; then
    cp "${TPL_OC}" "${TPL_OC}.bak-${TS}"
    [ -f "${PROXY_YAML}" ] && cp "${PROXY_YAML}" "${PROXY_YAML}.bak-${TS}"
    [ -f "${OC_CONF}" ] && cp "${OC_CONF}" "${OC_CONF}.bak-${TS}"
    echo "    done"
fi
echo ""

###############################################################################
# [2] my-YJS.xml
###############################################################################
echo "[2] Yjs container template"
plan "write ${TPL_YJS}"

YJS_XML="<?xml version=\"1.0\"?>
<Container version=\"2\">
  <Name>${YJS_CONTAINER}</Name>
  <Repository>${YJS_IMAGE}</Repository>
  <Registry>https://hub.docker.com/r/opencloudeu/yjs</Registry>
  <Network>${NETWORK_NAME}</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/opencloud-eu/web/issues</Support>
  <Project>https://github.com/opencloud-eu/web</Project>
  <Overview>Yjs (Hocuspocus) relay for real-time collaborative editing in the OpenCloud Editor.&#13;&#10;&#13;&#10;It is a pure WebSocket relay: it stores no content and persists nothing, so it needs no volume.&#13;&#10;&#13;&#10;OpenCloud reaches it through the proxy.yaml route /yjs -> http://${YJS_CONTAINER}:1234. Browsers reach it through the reverse proxy at ${OC_URL}/yjs.&#13;&#10;&#13;&#10;Requires WEB_OPTION_YJS_SERVER_URL=wss://${OCIS_DOMAIN}/yjs on the OpenCloud container.&#13;&#10;&#13;&#10;Only Markdown and .ocnote files support collaboration; end-to-end encrypted vaults and public links do not.</Overview>
  <Category>Cloud: Productivity:</Category>
  <WebUI/>
  <TemplateURL/>
  <Icon>https://raw.githubusercontent.com/opencloud-eu/opencloud/main/docs/assets/logo.svg</Icon>
  <ExtraParams>--stop-timeout=20 --user=1000:1000</ExtraParams>
  <PostArgs/>
  <CPUset/>
  <DonateText/>
  <DonateLink/>
  <Requires>Needs the ${OPENCLOUD_CONTAINER} container on the same Docker network and the /yjs route in its proxy.yaml.</Requires>
  <Config Name=\"OpenCloud URL\" Target=\"OPENCLOUD_URL\" Default=\"http://${OPENCLOUD_CONTAINER}:9200\" Mode=\"\" Description=\"Internal URL the relay uses to reach OpenCloud\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">http://${OPENCLOUD_CONTAINER}:9200</Config>
  <Config Name=\"PORT\" Target=\"PORT\" Default=\"1234\" Mode=\"\" Description=\"Internal listen port (not published)\" Type=\"Variable\" Display=\"always\" Required=\"true\" Mask=\"false\">1234</Config>
  <Config Name=\"SHUTDOWN_GRACE_PERIOD_MS\" Target=\"SHUTDOWN_GRACE_PERIOD_MS\" Default=\"15000\" Mode=\"\" Description=\"Graceful shutdown grace period in milliseconds\" Type=\"Variable\" Display=\"advanced\" Required=\"false\" Mask=\"false\">15000</Config>
  <TailscaleStateDir/>
</Container>"

if [ -f "${TPL_YJS}" ] && [ "${OVERWRITE_YJS_TEMPLATE}" != "true" ]; then
    plan "${TPL_YJS} exists -> writing ${TPL_YJS}.new instead"
    live && printf '%s\n' "${YJS_XML}" > "${TPL_YJS}.new"
else
    [ -f "${TPL_YJS}" ] && plan "${TPL_YJS} exists -> backup and overwrite"
    live && printf '%s\n' "${YJS_XML}" > "${TPL_YJS}"
fi
echo ""

###############################################################################
# [3] OpenCloud template: WEB_OPTION_YJS_SERVER_URL
###############################################################################
echo "[3] OpenCloud: WEB_OPTION_YJS_SERVER_URL"
YJS_URL="wss://${OCIS_DOMAIN}/yjs"
CUR_YJS_URL="$(get_cfg "${TPL_OC}" WEB_OPTION_YJS_SERVER_URL)"
if [ "${CUR_YJS_URL}" = "${YJS_URL}" ]; then
    echo "    already set - ok (${YJS_URL})"
else
    plan "set WEB_OPTION_YJS_SERVER_URL=${YJS_URL} (was '${CUR_YJS_URL}')"
    live && set_cfg "${TPL_OC}" WEB_OPTION_YJS_SERVER_URL "${YJS_URL}" Variable always "Yjs server URL for collaborative editing (8.x)"
fi
echo ""

###############################################################################
# [4] proxy.yaml: /yjs route (merged into the existing policy)
###############################################################################
echo "[4] proxy.yaml route"
if [ -f "${PROXY_YAML}" ] && grep -qE '(^|[[:space:]])endpoint:[[:space:]]*/yjs([[:space:]]|$)' "${PROXY_YAML}"; then
    echo "    /yjs route already present - ok"
else
    plan "add route /yjs -> http://${YJS_CONTAINER}:1234 (unprotected) to ${PROXY_YAML}"
    if live; then
        if [ ! -f "${PROXY_YAML}" ]; then
            mkdir -p "$(dirname "${PROXY_YAML}")"
            printf 'additional_policies:\n  - name: default\n    routes:\n      - endpoint: /yjs\n        backend: http://%s:1234\n        unprotected: true\n' "${YJS_CONTAINER}" > "${PROXY_YAML}"
        elif grep -qE '^[[:space:]]*additional_policies:' "${PROXY_YAML}"; then
            awk -v be="http://${YJS_CONTAINER}:1234" '
                { print }
                !done && /^[[:space:]]*routes:[[:space:]]*$/ {
                    printf "      - endpoint: /yjs\n        backend: %s\n        unprotected: true\n", be
                    done=1
                }
            ' "${PROXY_YAML}" > "${PROXY_YAML}.tmp" && mv "${PROXY_YAML}.tmp" "${PROXY_YAML}"
        fi
        if ! grep -qE '(^|[[:space:]])endpoint:[[:space:]]*/yjs([[:space:]]|$)' "${PROXY_YAML}"; then
            echo "    WARNING: could not insert the route automatically."
            echo "    Add this to the FIRST 'routes:' list under 'additional_policies:' in ${PROXY_YAML}:"
            echo "      - endpoint: /yjs"
            echo "        backend: http://${YJS_CONTAINER}:1234"
            echo "        unprotected: true"
            echo "    (do NOT add a second 'additional_policies:' block - YAML would drop one of them)"
        else
            echo "    route added (radicale/other routes kept)"
        fi
    fi
fi
echo ""

###############################################################################
# [5] SWAG: /yjs WebSocket location
###############################################################################
echo "[5] SWAG proxy conf"
if [ "${PATCH_SWAG_CONF}" != "true" ]; then
    echo "    skipped (PATCH_SWAG_CONF=false)"
    echo "    Make sure your own reverse proxy forwards ${OC_URL}/yjs as a WebSocket."
elif [ ! -f "${OC_CONF}" ]; then
    echo "    ${OC_CONF} not found - skipped"
    echo "    Make sure your own reverse proxy forwards ${OC_URL}/yjs as a WebSocket."
elif grep -qE '(^|[[:space:]])(location[[:space:]]+)?\^?~?[[:space:]]*/yjs' "${OC_CONF}"; then
    echo "    /yjs location already present - ok"
else
    plan "add 'location ^~ /yjs' WebSocket block to ${OC_CONF_NAME}"
    if live; then
        BLOCK="$(mktemp)"
        cat > "${BLOCK}" <<'NGINXEOF'
    location ^~ /yjs {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;

        set $upstream_app __OC_CONTAINER__;
        set $upstream_port 9200;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }

NGINXEOF
        sed -i "s|__OC_CONTAINER__|${OPENCLOUD_CONTAINER}|" "${BLOCK}"
        awk -v bf="${BLOCK}" '
            !done && /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ {
                while ((getline line < bf) > 0) print line
                close(bf); done=1
            }
            { print }
        ' "${OC_CONF}" > "${OC_CONF}.tmp" && mv "${OC_CONF}.tmp" "${OC_CONF}"
        rm -f "${BLOCK}"
        if grep -q '/yjs' "${OC_CONF}"; then
            echo "    added. Reload SWAG afterwards (nginx -s reload or restart the container)."
        else
            echo "    WARNING: could not insert the /yjs block - add it manually before 'location / {'."
        fi
    fi
fi
echo ""

###############################################################################
# Summary
###############################################################################
echo "============================================================"
if [ "${DRY_RUN}" = "true" ]; then
    echo " DRY RUN complete - ${#PLAN[@]} planned change(s), nothing modified."
    echo " Review the list above, then set DRY_RUN=\"false\" and run again."
else
    echo " Yjs enabled in the configuration."
    echo ""
    echo " NOW DO THIS (in this order):"
    echo "   1. Docker -> Add Container -> '${YJS_CONTAINER}' (User templates) -> Apply"
    if [ -f "${TPL_YJS}.new" ]; then
        echo "      NOTE: $(basename "${TPL_YJS}").new was written - compare it with the"
        echo "            existing template and rename it to $(basename "${TPL_YJS}") when you are happy."
    fi
    echo "   2. Docker -> edit '${OPENCLOUD_CONTAINER}' -> Apply   (new env var)"
    echo "   3. Reload SWAG so the /yjs location is active"
    echo ""
    echo " Verify:"
    echo "   docker logs ${YJS_CONTAINER} 2>&1 | tail -20"
    echo "   Open a .md or .ocnote file in the OpenCloud Editor with two browsers:"
    echo "   the toolbar shows 'Collaboration ready' and both cursors move live."
    echo ""
    echo " Notes:"
    echo "   * Only Markdown and .ocnote files support collaboration."
    echo "   * Public links and end-to-end encrypted vaults have no collaboration."
    echo "   * Websockets need sticky sessions if you run more than one Yjs instance."
fi
echo "============================================================"
