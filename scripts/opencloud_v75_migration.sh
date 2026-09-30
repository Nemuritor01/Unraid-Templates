#!/bin/bash
###############################################################################
#  OpenCloud  ->  7.5+ / 8.x  Migration  (Unraid / Docker templates, NOT compose)
###############################################################################
#
#  WHY: OpenCloud 7.5 changed the web-office architecture:
#    * The separate "Collaboration" (WOPI) container is retired. The WOPI
#      service now runs INSIDE the OpenCloud container
#      (OC_ADD_RUN_SERVICES=collaboration) and is served on the MAIN
#      OpenCloud domain under /wopi and /collaboration.
#    * Collabora must NOT override its entrypoint anymore
#      (no "--entrypoint=/bin/bash" + "coolconfig generate-proof-key").
#      The WOPI proof key is generated on the host and mounted read-only.
#    * Collabora's aliasgroup1 must point at the OpenCloud domain.
#    * CSP needs worker-src + blob: in style-src; apps.yaml is new.
#
#  WHY (8.x): OpenCloud 8.x uses a NEW, VERSIONED search index
#  (bleve-v5 / opencloud-resources-v5). Files that already existed are NOT
#  found again until the index is rebuilt once. Upstream release notes call
#  this "the whole migration path from 7.x to 8.x":
#
#      opencloud search index --all-spaces --force-rescan --insecure
#
#  Optionally, 8.x adds real-time collaborative editing in the OpenCloud
#  Editor. That needs the separate Yjs service (opencloudeu/yjs), a
#  proxy.yaml route, WEB_OPTION_YJS_SERVER_URL and an /yjs WebSocket route on
#  your reverse proxy. Enable it with ./opencloud-enable-yjs.sh - this script
#  only reports that it is missing.
#
#  WHAT THIS SCRIPT DOES (in LIVE mode):
#    1. Backs up your OpenCloud config dir and the Unraid user templates
#    2. Applies the 7.0 sharing service-account fix if it is still missing
#    3. Generates the Collabora WOPI proof key
#    4. Patches csp.yaml (keeps your entries) and creates apps.yaml
#    5. Patches the Unraid user templates (my-OpenCloud.xml, my-Collabora.xml)
#    6. Stops the old Collaboration container and disables its autostart
#       (NOT deleted - kept for rollback)
#    7. Recreates OpenCloud and Collabora from the patched templates
#    8. [8.x] Checks opencloud.yaml against the new release (init --diff),
#       rebuilds the versioned search index and (optionally) removes the old
#       unversioned one.
#
#  It does NOT touch your file data (/var/lib/opencloud).
#
#  RUN IT FIRST WITH DRY_RUN="true" (default) and read the output.
#  Strongly recommended: make an appdata backup before the LIVE run.
###############################################################################
#name=OpenCloud 7.5 / 8.x Migration
#description=Migrates an existing OpenCloud/Collabora/Collaboration setup to the 7.5+/8.x architecture
#arrayStarted=true

###############################################################################
#  USER CONFIGURATION
###############################################################################

# Container names exactly as shown on the Unraid Docker tab
OPENCLOUD_CONTAINER="OpenCloud"
COLLABORA_CONTAINER="Collabora"
COLLABORATION_CONTAINER="Collaboration"   # the OLD WOPI container to retire

# Paths
OCL_CONFIG="/mnt/user/appdata/opencloud/config"
COL_PROOF_DIR="/mnt/user/appdata/collabora/proof"
BACKUP_BASE="/mnt/user/appdata/opencloud"

# Leave empty to auto-detect from your existing templates
OC_URL_OVERRIDE=""          # e.g. https://opencloud.example.com
COLLABORA_URL_OVERRIDE=""   # e.g. https://collabora.example.com

# true  = only report what would change (DEFAULT - run this first)
# false = apply the migration
DRY_RUN="true"

# Recreate the containers from the patched templates at the end?
# If false (or if Unraid's recreate helper is missing), open each container
# in the Docker tab and click "Apply".
RECREATE_CONTAINERS="true"

# ── OpenCloud 8.x ───────────────────────────────────────────────────────────
# Check the running config against the new release ("opencloud init --diff").
# Report only: if it reports changes, the patch file is written to the config
# dir and you apply it yourself after reading it.
RUN_INIT_DIFF="true"

# Rebuild the versioned search index. MANDATORY once for 7.x -> 8.x. It runs
# in the foreground and can take a while on large instances.
REINDEX_8X="true"

# Force the reindex even when no old index was detected.
FORCE_REINDEX="false"

# Remove the OLD, unversioned index after the reindex. Leave this "false" and
# verify in the Web Client that old files are found again, then set it to
# "true" and re-run (or use the printed command).
DELETE_OLD_BLEVE_INDEX="false"

###############################################################################
#  DO NOT EDIT BELOW THIS LINE
###############################################################################

TPL_DIR="/boot/config/plugins/dockerMan/templates-user"
TPL_OC="${TPL_DIR}/my-${OPENCLOUD_CONTAINER}.xml"
TPL_COL="${TPL_DIR}/my-${COLLABORA_CONTAINER}.xml"
TPL_WOPI="${TPL_DIR}/my-${COLLABORATION_CONTAINER}.xml"
YAML="${OCL_CONFIG}/opencloud.yaml"
CSP="${OCL_CONFIG}/csp.yaml"
APPS="${OCL_CONFIG}/apps.yaml"
PROOF_KEY="${COL_PROOF_DIR}/proof_key"
AUTOSTART="/var/lib/docker/unraid-autostart"
RECREATE_HELPER="/usr/local/emhttp/plugins/dynamix.docker.manager/scripts/update_container"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_BASE}/migration-backup-7.5-${TS}"

PLAN=()
plan() { PLAN+=("$1"); echo "    -> $1"; }
live() { [ "${DRY_RUN}" != "true" ]; }

echo "============================================================"
echo " OpenCloud 7.5+ / 8.x Migration"
[ "${DRY_RUN}" = "true" ] && echo " MODE: DRY RUN - nothing will be changed" || echo " MODE: LIVE"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Helpers for Unraid template XML (each <Config> is one line in dockerMan)
# ---------------------------------------------------------------------------

# get_cfg <file> <Target>   -> prints the configured value
get_cfg() {
    sed -n -E "s|.*<Config [^>]*Target=\"$2\"[^>]*>([^<]*)</Config>.*|\1|p" "$1" 2>/dev/null | head -1
}

# has_cfg <file> <Target>
has_cfg() { grep -qE "<Config [^>]*Target=\"$2\"" "$1" 2>/dev/null; }

# get_tag <file> <Tag>   -> prints the tag value (e.g. Repository, Network)
get_tag() {
    sed -n -E "s|.*<${2}>([^<]*)</${2}>.*|\1|p" "$1" 2>/dev/null | head -1
}

sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

# set_cfg <file> <Target> <value> <Type> <Display> <Description> [Mode]
set_cfg() {
    local f="$1" t="$2" v="$3" type="$4" disp="$5" desc="$6" mode="${7:-}"
    local ev; ev="$(sed_escape "$v")"
    if has_cfg "$f" "$t"; then
        # self-closing -> open/close with value
        sed -i -E "/<Config [^>]*Target=\"${t}\"[^>]*\/>/ s|/>|>${ev}</Config>|" "$f"
        # replace existing value
        sed -i -E "s|(<Config [^>]*Target=\"${t}\"[^>]*>)[^<]*(</Config>)|\1${ev}\2|" "$f"
    else
        local line="  <Config Name=\"${t}\" Target=\"${t}\" Default=\"${v}\" Mode=\"${mode}\" Description=\"${desc}\" Type=\"${type}\" Display=\"${disp}\" Required=\"false\" Mask=\"false\">${v}</Config>"
        local el; el="$(sed_escape "$line")"
        sed -i -E "s|^([[:space:]]*)</Container>|${el}\n</Container>|" "$f"
    fi
}

# set_tag <file> <Tag> <value>   (e.g. ExtraParams, PostArgs, Privileged)
set_tag() {
    local f="$1" tag="$2" v="$3" ev; ev="$(sed_escape "$v")"
    if grep -qE "<${tag}/>" "$f"; then
        if [ -n "$v" ]; then sed -i -E "s|<${tag}/>|<${tag}>${ev}</${tag}>|" "$f"; fi
    elif grep -qE "<${tag}>" "$f"; then
        if [ -n "$v" ]; then
            sed -i -E "s|<${tag}>.*</${tag}>|<${tag}>${ev}</${tag}>|" "$f"
        else
            sed -i -E "s|<${tag}>.*</${tag}>|<${tag}/>|" "$f"
        fi
    fi
}

# ---------------------------------------------------------------------------
# [0] Pre-flight
# ---------------------------------------------------------------------------
echo "[0] Pre-flight checks"
FAIL="false"
command -v docker >/dev/null 2>&1 || { echo "    ERROR: docker not found"; FAIL="true"; }
[ -f "${TPL_OC}" ]  || { echo "    ERROR: template not found: ${TPL_OC}"; FAIL="true"; }
[ -f "${YAML}" ]    || { echo "    ERROR: config not found: ${YAML}"; FAIL="true"; }
HAVE_COL="false";  [ -f "${TPL_COL}" ]  && HAVE_COL="true"
HAVE_WOPI="false"; [ -f "${TPL_WOPI}" ] && HAVE_WOPI="true"
echo "    OpenCloud template:      ${TPL_OC}"
echo "    Collabora template:      $([ "$HAVE_COL" = true ] && echo "${TPL_COL}" || echo 'not found (web office will be skipped)')"
echo "    Old Collaboration tpl:   $([ "$HAVE_WOPI" = true ] && echo "${TPL_WOPI}" || echo 'not found (already retired?)')"
[ "${FAIL}" = "true" ] && { echo ""; echo "Aborting - nothing changed."; exit 1; }

OC_URL="${OC_URL_OVERRIDE:-$(get_cfg "${TPL_OC}" OC_URL)}"
OC_URL="${OC_URL%/}"
COLLABORA_URL="${COLLABORA_URL_OVERRIDE}"
[ -z "${COLLABORA_URL}" ] && [ "$HAVE_WOPI" = true ] && COLLABORA_URL="$(get_cfg "${TPL_WOPI}" COLLABORATION_APP_ADDR)"
[ -z "${COLLABORA_URL}" ] && COLLABORA_URL="$(get_cfg "${TPL_OC}" COLLABORATION_APP_ADDR)"
[ -z "${COLLABORA_URL}" ] && [ -n "$(get_cfg "${TPL_OC}" COLLABORA_DOMAIN)" ] && COLLABORA_URL="https://$(get_cfg "${TPL_OC}" COLLABORA_DOMAIN)"
COLLABORA_URL="${COLLABORA_URL%/}"
OC_HOST="${OC_URL#https://}"; OC_HOST="${OC_HOST#http://}"
COL_HOST="${COLLABORA_URL#https://}"; COL_HOST="${COL_HOST#http://}"

# Host path of the container's /var/lib/opencloud (for the 8.x index checks)
OCL_DATA_HOST="$(get_cfg "${TPL_OC}" /var/lib/opencloud)"
[ -z "${OCL_DATA_HOST}" ] && OCL_DATA_HOST="${BACKUP_BASE}/data"
NETWORK_NAME="$(get_tag "${TPL_OC}" Network)"
OC_IMAGE="$(get_tag "${TPL_OC}" Repository)"

echo "    OpenCloud URL:           ${OC_URL:-<NOT FOUND>}"
echo "    Collabora URL:           ${COLLABORA_URL:-<NOT FOUND>}"
echo "    OpenCloud image:         ${OC_IMAGE:-<NOT FOUND>}"
echo "    OpenCloud data (host):   ${OCL_DATA_HOST}"
if [ -z "${OC_URL}" ] || { [ "$HAVE_COL" = true ] && [ -z "${COLLABORA_URL}" ]; }; then
    echo "    ERROR: could not detect URLs. Set OC_URL_OVERRIDE / COLLABORA_URL_OVERRIDE."
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# [1] Backup
# ---------------------------------------------------------------------------
echo "[1] Backup"
plan "backup config dir + templates to ${BACKUP_DIR}"
if live; then
    mkdir -p "${BACKUP_DIR}/templates"
    tar -czf "${BACKUP_DIR}/opencloud-config.tar.gz" -C "$(dirname "${OCL_CONFIG}")" "$(basename "${OCL_CONFIG}")"
    cp "${TPL_OC}" "${BACKUP_DIR}/templates/"
    [ "$HAVE_COL" = true ]  && cp "${TPL_COL}"  "${BACKUP_DIR}/templates/"
    [ "$HAVE_WOPI" = true ] && cp "${TPL_WOPI}" "${BACKUP_DIR}/templates/"
    [ -f "${AUTOSTART}" ]   && cp "${AUTOSTART}" "${BACKUP_DIR}/unraid-autostart"
    echo "    done"
fi
echo ""

# ---------------------------------------------------------------------------
# [2] 7.0 sharing service-account fix (for users skipping versions)
# ---------------------------------------------------------------------------
echo "[2] Sharing service account (7.0 requirement)"
HAS_SA="$(awk '/^[a-zA-Z_]/{s=($0~/^sharing:/)?1:0} s&&/^[[:space:]]+service_account:/{print "yes";exit}' "${YAML}")"
if [ "${HAS_SA}" = "yes" ]; then
    echo "    already present - ok"
else
    SA_ID="$(grep -E '^[[:space:]]+service_account_id:' "${YAML}" | head -1 | sed -E 's/^[[:space:]]+service_account_id:[[:space:]]*//')"
    SA_SECRET="$(grep -E '^[[:space:]]+service_account_secret:' "${YAML}" | head -1 | sed -E 's/^[[:space:]]+service_account_secret:[[:space:]]*//')"
    if [ -z "${SA_ID}" ] || [ -z "${SA_SECRET}" ]; then
        echo "    WARNING: no existing service account found - skipping (check manually)"
    else
        plan "add sharing.service_account (reusing id ${SA_ID})"
        if live; then
            if grep -qE '^sharing:' "${YAML}"; then
                awk -v id="${SA_ID}" -v s="${SA_SECRET}" '{print} /^sharing:/&&!d{print "  service_account:";print "    service_account_id: " id;print "    service_account_secret: " s;d=1}' "${YAML}" > "${YAML}.tmp" && mv "${YAML}.tmp" "${YAML}"
            else
                printf '\nsharing:\n  service_account:\n    service_account_id: %s\n    service_account_secret: %s\n' "${SA_ID}" "${SA_SECRET}" >> "${YAML}"
            fi
        fi
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# [3] Collabora proof key
# ---------------------------------------------------------------------------
if [ "$HAVE_COL" = true ]; then
    echo "[3] Collabora WOPI proof key"
    if [ -s "${PROOF_KEY}" ]; then
        echo "    exists - ok (${PROOF_KEY})"
    else
        plan "generate 4096-bit proof key at ${PROOF_KEY} (owner 1001, mode 400)"
        if live; then
            mkdir -p "${COL_PROOF_DIR}"
            if openssl genrsa -traditional -out "${PROOF_KEY}.tmp" 4096 2>/dev/null \
               || openssl genrsa -out "${PROOF_KEY}.tmp" 4096 2>/dev/null; then
                chown 1001:1001 "${PROOF_KEY}.tmp" 2>/dev/null
                chmod 400 "${PROOF_KEY}.tmp"
                mv "${PROOF_KEY}.tmp" "${PROOF_KEY}"
            else
                rm -f "${PROOF_KEY}.tmp"
                echo "    ERROR: openssl failed - aborting before touching templates"
                exit 1
            fi
        fi
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# [4] csp.yaml + apps.yaml (patch, never overwrite user entries)
# ---------------------------------------------------------------------------
echo "[4] CSP and apps.yaml"
if [ -f "${CSP}" ]; then
    if ! grep -qE '^[[:space:]]+worker-src:' "${CSP}"; then
        plan "csp.yaml: add worker-src ('self', blob:)"
        live && printf "  worker-src:\n    - '''self'''\n    - 'blob:'\n" >> "${CSP}"
    fi
    STYLE_BLOB="$(awk '/^  [a-z-]+:/{s=($0~/^  style-src:/)?1:0} s&&/blob:/{print "yes";exit}' "${CSP}")"
    if [ "${STYLE_BLOB}" != "yes" ] && grep -qE '^  style-src:' "${CSP}"; then
        plan "csp.yaml: add blob: to style-src"
        live && { awk '{print} /^  style-src:/&&!d{print "    - '"'"'blob:'"'"'";d=1}' "${CSP}" > "${CSP}.tmp" && mv "${CSP}.tmp" "${CSP}"; }
    fi
    if [ -n "${COL_HOST}" ] && ! grep -q "${COL_HOST}" "${CSP}"; then
        echo "    WARNING: ${COL_HOST} is not in csp.yaml frame-src/img-src - add it manually"
    fi
    # 8.x: the Yjs socket is same-origin (wss://<oc-domain>/yjs); connect-src
    # must therefore contain 'self' or the wss URL of the OpenCloud domain.
    if ! grep -qE "wss://${OC_HOST}|'self'" "${CSP}"; then
        echo "    WARNING: csp.yaml connect-src has neither 'self' nor wss://${OC_HOST}"
        echo "             -> collaborative editing (/yjs) would be blocked by the CSP"
    fi
else
    echo "    WARNING: ${CSP} missing - run the new pre-install script"
fi
if [ ! -f "${APPS}" ]; then
    plan "create apps.yaml"
    live && printf 'maps:\n  config:\n    folderViewEnabled: false\n' > "${APPS}"
fi
echo ""

# ---------------------------------------------------------------------------
# [5] Patch Unraid templates
# ---------------------------------------------------------------------------
echo "[5] Templates"

# OpenCloud: embed the collaboration service
CUR_SVC="$(get_cfg "${TPL_OC}" OC_ADD_RUN_SERVICES)"
NEW_SVC="${CUR_SVC}"
case ",${CUR_SVC}," in *,collaboration,*) ;; *) NEW_SVC="${CUR_SVC:+${CUR_SVC},}collaboration";; esac
if [ "$HAVE_COL" = true ]; then
    plan "OpenCloud: OC_ADD_RUN_SERVICES='${NEW_SVC}' (was '${CUR_SVC}')"
    plan "OpenCloud: COLLABORATION_WOPI_SRC=${OC_URL}, APP_ADDR=${COLLABORA_URL}, APP_NAME=CollaboraOnline"
    if live; then
        set_cfg "${TPL_OC}" OC_ADD_RUN_SERVICES "${NEW_SVC}" Variable always "Additional services (7.5 needs collaboration)"
        set_cfg "${TPL_OC}" COLLABORATION_WOPI_SRC "${OC_URL}" Variable always "WOPI URL = main OpenCloud URL (7.5+)"
        set_cfg "${TPL_OC}" COLLABORATION_APP_NAME "CollaboraOnline" Variable advanced "Web office app name"
        set_cfg "${TPL_OC}" COLLABORATION_APP_PRODUCT "Collabora" Variable advanced "Web office product"
        set_cfg "${TPL_OC}" COLLABORATION_APP_ADDR "${COLLABORA_URL}" Variable always "Public Collabora URL"
        set_cfg "${TPL_OC}" COLLABORATION_APP_ICON "${COLLABORA_URL}/favicon.ico" Variable advanced "App icon"
        set_cfg "${TPL_OC}" COLLABORATION_APP_INSECURE "true" Variable advanced "Skip TLS verify to Collabora"
        set_cfg "${TPL_OC}" COLLABORATION_CS3API_DATAGATEWAY_INSECURE "true" Variable advanced "Skip TLS verify CS3 gateway"
        set_cfg "${TPL_OC}" COLLABORA_DOMAIN "${COL_HOST}" Variable advanced "Collabora domain (CSP)"
        # NOTE: apps.yaml already lives in the config dir (mounted at
        # /etc/opencloud), so this extra file mount is redundant. It is kept
        # for backwards compatibility with earlier runs of this script.
        has_cfg "${TPL_OC}" "/etc/opencloud/apps.yaml" || \
            set_cfg "${TPL_OC}" "/etc/opencloud/apps.yaml" "${APPS}" Path advanced "apps.yaml" rw
    fi
fi

# Collabora: drop entrypoint override, new privileges, proof key, aliasgroup
if [ "$HAVE_COL" = true ]; then
    plan "Collabora: ExtraParams -> --cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined"
    plan "Collabora: PostArgs -> (empty), Privileged -> false"
    plan "Collabora: aliasgroup1 -> ${OC_URL}  (was '$(get_cfg "${TPL_COL}" aliasgroup1)')"
    plan "Collabora: mount ${PROOF_KEY} -> /etc/coolwsd/proof_key (ro)"
    if live; then
        set_tag "${TPL_COL}" ExtraParams "--cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined"
        set_tag "${TPL_COL}" PostArgs ""
        set_tag "${TPL_COL}" Privileged "false"
        set_cfg "${TPL_COL}" aliasgroup1 "${OC_URL}" Variable always "WOPI host = main OpenCloud URL (7.5+)"
        set_cfg "${TPL_COL}" "/etc/coolwsd/proof_key" "${PROOF_KEY}" Path always "WOPI proof key (read-only)" ro
    fi
fi

# 8.x hint: collaborative editing needs the separate Yjs container.
if ! has_cfg "${TPL_OC}" WEB_OPTION_YJS_SERVER_URL; then
    echo "    NOTE: real-time collaboration is not configured (no WEB_OPTION_YJS_SERVER_URL)."
    echo "          Run ./opencloud-enable-yjs.sh afterwards to add the Yjs service."
fi
echo ""

# ---------------------------------------------------------------------------
# [6] Retire the old Collaboration container (stop + no autostart, keep it)
# ---------------------------------------------------------------------------
echo "[6] Old Collaboration (WOPI) container"
if docker inspect "${COLLABORATION_CONTAINER}" >/dev/null 2>&1; then
    plan "stop '${COLLABORATION_CONTAINER}' and remove it from Unraid autostart (container kept for rollback)"
    if live; then
        docker stop "${COLLABORATION_CONTAINER}" >/dev/null 2>&1
        [ -f "${AUTOSTART}" ] && sed -i -E "/^${COLLABORATION_CONTAINER}([[:space:]].*)?$/d" "${AUTOSTART}"
    fi
else
    echo "    not present - ok"
fi
echo ""

# ---------------------------------------------------------------------------
# [7] Recreate
# ---------------------------------------------------------------------------
echo "[7] Recreate containers from patched templates"
if [ "${RECREATE_CONTAINERS}" = "true" ] && [ -x "${RECREATE_HELPER}" ]; then
    plan "recreate ${OPENCLOUD_CONTAINER}$([ "$HAVE_COL" = true ] && echo " and ${COLLABORA_CONTAINER}") via Unraid helper"
    if live; then
        "${RECREATE_HELPER}" "${OPENCLOUD_CONTAINER}"
        [ "$HAVE_COL" = true ] && "${RECREATE_HELPER}" "${COLLABORA_CONTAINER}"
    fi
else
    echo "    Manual step: Docker tab -> edit '${OPENCLOUD_CONTAINER}' -> Apply,"
    echo "                 then the same for '${COLLABORA_CONTAINER}'."
fi
echo ""

# ---------------------------------------------------------------------------
# [8] OpenCloud 8.x post-upgrade  (NEW)
#
#  Upstream: upgrading 7.x -> 8.x rebuilds the search index into a new,
#  versioned index (bleve-v5 / opencloud-resources-v5). Until that rebuild
#  happened, files that existed before are not found in search.
# ---------------------------------------------------------------------------
echo "[8] OpenCloud 8.x post-upgrade"
if ! docker inspect "${OPENCLOUD_CONTAINER}" >/dev/null 2>&1; then
    echo "    '${OPENCLOUD_CONTAINER}' does not exist yet - run the 8.x steps after it is created:"
    echo "      docker exec ${OPENCLOUD_CONTAINER} opencloud search index --all-spaces --force-rescan --insecure"
    echo ""
else
    OC_RUNNING="$(docker inspect -f '{{.State.Running}}' "${OPENCLOUD_CONTAINER}" 2>/dev/null)"
    if [ "${OC_RUNNING}" != "true" ] && live; then
        echo "    waiting for ${OPENCLOUD_CONTAINER} to start (up to 120s)..."
        for _ in $(seq 1 24); do
            [ "$(docker inspect -f '{{.State.Running}}' "${OPENCLOUD_CONTAINER}" 2>/dev/null)" = "true" ] && break
            sleep 5
        done
        OC_RUNNING="$(docker inspect -f '{{.State.Running}}' "${OPENCLOUD_CONTAINER}" 2>/dev/null)"
    fi
    # Read-only checks (exec is fine in DRY_RUN)
    OC_VER=""
    if [ "${OC_RUNNING}" = "true" ]; then
        OC_VER="$(docker exec "${OPENCLOUD_CONTAINER}" opencloud version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    fi
    echo "    container running: ${OC_RUNNING:-unknown}   version: ${OC_VER:-unknown}"

    IS_8X="false"
    case "${OC_VER}" in 8.*|9.*|1[0-9].*) IS_8X="true";; esac
    PROCEED_8X="false"
    [ "${IS_8X}" = "true" ] && PROCEED_8X="true"
    [ "${FORCE_REINDEX}" = "true" ] && PROCEED_8X="true"
    # In a DRY RUN the container is still the old one; if the recreate is
    # planned, report the 8.x steps that would run afterwards anyway.
    if [ "${DRY_RUN}" = "true" ] && [ "${RECREATE_CONTAINERS}" = "true" ] && [ -x "${RECREATE_HELPER}" ]; then
        PROCEED_8X="true"
        [ "${IS_8X}" != "true" ] && echo "    (DRY RUN: assuming ${OC_IMAGE:-the 8.x image} after the planned recreate)"
    fi
    if [ "${PROCEED_8X}" != "true" ]; then
        if [ -z "${OC_VER}" ]; then
            echo "    could not detect the version - skipping the 8.x steps."
            echo "    Recreate the container with the 8.x image, then re-run this script,"
            echo "    or set FORCE_REINDEX=\"true\" to run the reindex regardless."
        else
            echo "    container is ${OC_VER} (not 8.x) - skipping the 8.x steps."
            echo "    Recreate it with the opencloudeu/opencloud-rolling 8.x image and re-run."
        fi
        echo ""
    else
        # ---- 8.a config diff (report only) ---------------------------------
        if [ "${RUN_INIT_DIFF}" = "true" ] && [ "${OC_RUNNING}" = "true" ]; then
            plan "check opencloud.yaml against ${OC_VER:-8.x} ('opencloud init --diff', report only)"
            if live; then
                DIFF_OUT="$(docker exec "${OPENCLOUD_CONTAINER}" opencloud init --diff 2>&1)"
                echo "${DIFF_OUT}" | sed 's/^/      /'
                case "${DIFF_OUT}" in
                    *"no changes"*|*"up to date"*)
                        echo "    opencloud.yaml is up to date - ok" ;;
                    *)
                        echo "    ATTENTION: a configuration patch was written."
                        echo "      Patch file: ${OCL_CONFIG}/opencloud.config.patch"
                        echo "      Apply it with:"
                        echo "        cd ${OCL_CONFIG} && patch --dry-run opencloud.yaml < opencloud.config.patch"
                        echo "        cd ${OCL_CONFIG} && patch opencloud.yaml < opencloud.config.patch"
                        echo "      then restart ${OPENCLOUD_CONTAINER}." ;;
                esac
            fi
        fi

        # ---- 8.b search engine + index state -------------------------------
        SEARCH_ENGINE=""
        BLEVE_PATH=""
        if [ "${OC_RUNNING}" = "true" ]; then
            SEARCH_ENGINE="$(docker exec "${OPENCLOUD_CONTAINER}" printenv SEARCH_ENGINE_TYPE 2>/dev/null)"
            OS_ADDRS="$(docker exec "${OPENCLOUD_CONTAINER}" printenv SEARCH_ENGINE_OPEN_SEARCH_CLIENT_ADDRESSES 2>/dev/null)"
            BLEVE_PATH="$(docker exec "${OPENCLOUD_CONTAINER}" printenv SEARCH_ENGINE_BLEVE_DATA_PATH 2>/dev/null)"
        fi
        [ -z "${BLEVE_PATH}" ] && BLEVE_PATH="/var/lib/opencloud/search"
        case "${OS_ADDRS}" in ""|"[]") ;; *) SEARCH_ENGINE="opensearch" ;; esac
        [ -z "${SEARCH_ENGINE}" ] && SEARCH_ENGINE="bleve"
        echo "    search engine: ${SEARCH_ENGINE}   bleve data path: ${BLEVE_PATH}"

        REINDEX_CMD="opencloud search index --all-spaces --force-rescan --insecure"

        if [ "${SEARCH_ENGINE}" = "opensearch" ]; then
            echo "    OpenSearch backend: rebuild the versioned index (opencloud-resources-v5) once."
            echo "      docker exec ${OPENCLOUD_CONTAINER} ${REINDEX_CMD}"
            echo "    Verify old files in the Web Client, then drop the old index:"
            echo "      curl \"http://localhost:9200/_cat/indices/opencloud-resources*?v\""
            echo "      curl -X DELETE \"http://localhost:9200/opencloud-resources\""
            if [ "${FORCE_REINDEX}" = "true" ]; then
                plan "run the OpenSearch reindex (this can take a while)"
                if live; then docker exec "${OPENCLOUD_CONTAINER}" ${REINDEX_CMD}; fi
            else
                echo "    (not run automatically - set FORCE_REINDEX=\"true\" to run it from here)"
            fi
        else
            OLD_IDX="false"; NEW_IDX="false"
            if [ "${OC_RUNNING}" = "true" ]; then
                docker exec "${OPENCLOUD_CONTAINER}" sh -c "[ -d '${BLEVE_PATH}/bleve' ]" >/dev/null 2>&1 && OLD_IDX="true"
                docker exec "${OPENCLOUD_CONTAINER}" sh -c "ls -d '${BLEVE_PATH}'/bleve-v* >/dev/null 2>&1" >/dev/null 2>&1 && NEW_IDX="true"
            fi
            echo "    old 7.x index present: ${OLD_IDX}   versioned index present: ${NEW_IDX}"

            NEED_REINDEX="false"
            [ "${OLD_IDX}" = "true" ] && NEED_REINDEX="true"
            [ "${FORCE_REINDEX}" = "true" ] && NEED_REINDEX="true"

            if [ "${NEED_REINDEX}" = "true" ]; then
                if [ "${REINDEX_8X}" = "true" ] && [ "${OC_RUNNING}" = "true" ]; then
                    plan "rebuild versioned search index (MANDATORY for 8.x, can take a while)"
                    if live; then
                        # The server may still be booting right after the
                        # recreate; retry a few times before giving up.
                        REINDEX_OK="false"
                        for attempt in 1 2 3; do
                            if docker exec "${OPENCLOUD_CONTAINER}" ${REINDEX_CMD}; then
                                REINDEX_OK="true"; break
                            fi
                            if [ "${attempt}" -lt 3 ]; then
                                echo "    attempt ${attempt} failed - retrying in 20s..."
                                sleep 20
                            fi
                        done
                        if [ "${REINDEX_OK}" = "true" ]; then
                            echo "    reindex finished"
                        else
                            echo "    ERROR: reindex failed - run it manually once the container is up:"
                            echo "      docker exec ${OPENCLOUD_CONTAINER} ${REINDEX_CMD}"
                        fi
                    fi
                else
                    echo "    Run it manually (container must be running):"
                    echo "      docker exec ${OPENCLOUD_CONTAINER} ${REINDEX_CMD}"
                fi
            else
                echo "    no old unversioned index found - nothing to rebuild"
                echo "    (fresh 8.x install, or the migration was already done)"
            fi

            if [ "${OLD_IDX}" = "true" ]; then
                if [ "${DELETE_OLD_BLEVE_INDEX}" = "true" ]; then
                    plan "remove the old unversioned index ${BLEVE_PATH}/bleve"
                    live && docker exec "${OPENCLOUD_CONTAINER}" rm -r "${BLEVE_PATH}/bleve"
                else
                    echo "    After you verified in the Web Client that old files are found again:"
                    echo "      docker exec ${OPENCLOUD_CONTAINER} rm -r ${BLEVE_PATH}/bleve"
                    echo "      docker exec ${OPENCLOUD_CONTAINER} ls ${BLEVE_PATH}"
                    echo "      # keep only the index with the highest version suffix (e.g. bleve-v5)"
                fi
            fi
        fi
        echo ""
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================================"
if [ "${DRY_RUN}" = "true" ]; then
    echo " DRY RUN complete - ${#PLAN[@]} planned change(s), nothing modified."
    echo " Review the list above, make an appdata backup,"
    echo " then set DRY_RUN=\"false\" and run again."
else
    echo " Migration applied. Backup: ${BACKUP_DIR}"
    echo ""
    echo " Verify:"
    echo "   curl -s -o /dev/null -w '%{http_code}\\n' ${OC_URL}/wopi   (expect 418)"
    echo "   docker logs ${OPENCLOUD_CONTAINER} 2>&1 | grep -i collaboration"
    echo "   Open a .docx/.odt in OpenCloud."
    echo "   Search for an OLD file (created before the upgrade)."
    echo "      If it is missing, run:"
    echo "        docker exec ${OPENCLOUD_CONTAINER} opencloud search index --all-spaces --force-rescan --insecure"
    echo ""
    echo " Real-time collaborative editing (optional, 8.x): run ./opencloud-enable-yjs.sh"
    echo ""
    echo " Afterwards (optional cleanup):"
    echo "   - delete the wopiserver SWAG conf and reload SWAG"
    echo "   - delete the wopiserver DNS record"
    echo "   - remove the '${COLLABORATION_CONTAINER}' container once all works"
    echo ""
    echo " Rollback: restore templates + config from ${BACKUP_DIR},"
    echo "   re-add the old container to autostart, and Apply in the Docker tab."
fi
echo "============================================================"
