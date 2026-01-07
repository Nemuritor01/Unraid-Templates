#!/bin/bash
################################################################################
# OpenCloud + Collabora + WOPI Integration Diagnostic Script v2
# For Unraid User Scripts Plugin
# Tests connectivity, configuration, and integration between all components
################################################################################
#name=OpenCloud Collabora Diagnostic v2
#description=Comprehensive diagnostic tool for OpenCloud with Collabora integration
#arrayStarted=true

################################################################################
# USER CONFIGURATION - EDIT THESE VALUES
################################################################################

# Domain Configuration (without https://)
OCIS_DOMAIN="opencloud.yourdomain.com"
COLLABORA_DOMAIN="collabora.yourdomain.com"
WOPISERVER_DOMAIN="wopi.yourdomain.com"

# Container Names (as shown in Docker)
OPENCLOUD_CONTAINER="OpenCloud"
COLLABORA_CONTAINER="Collabora"
COLLABORATION_CONTAINER="Collaboration"

# Docker Network Name
NETWORK_NAME="opencloud-net"

# Installation Paths
OCL_CONFIG="/mnt/user/appdata/opencloud/config"
OCL_DATA="/mnt/user/appdata/opencloud/data"

# Reverse Proxy Type (swag, nginx, traefik, caddy, pangolin, other)
PROXY_TYPE="swag"  # Options: swag, nginx, traefik, caddy, pangolin, other

# Enable Extended Tests (slower but more thorough)
EXTENDED_TESTS="true"

# Hide Sensitive Data (true = safe to share publicly, false = full details)
HIDE_SENSITIVE_DATA="false"  # Set to "true" to sanitize output for sharing

# Diagnostic Report File Location
DIAGNOSTIC_FILE="${OCL_CONFIG}/opencloud-diagnostic-$(date +%Y%m%d-%H%M%S).log"

################################################################################
# SCRIPT CONFIGURATION - DO NOT EDIT BELOW THIS LINE
################################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Component tracking
declare -A COMPONENT_TESTS
declare -A COMPONENT_PASSED
declare -A COMPONENT_FAILED
declare -A COMPONENT_WARNINGS

# Result storage
declare -a FAILURES
declare -a WARNINGS
declare -a RECOMMENDATIONS
declare -a DETAILED_ERRORS

# Critical failure tracking
CRITICAL_FAILURES=false

# Cached IPs for sanitization
OPENCLOUD_IP=""
COLLABORA_IP=""
COLLABORATION_IP=""
HOST_IP=""

################################################################################
# HELPER FUNCTIONS
################################################################################

# Sanitize sensitive data if HIDE_SENSITIVE_DATA is true
sanitize() {
    local text="$1"
    
    if [ "$HIDE_SENSITIVE_DATA" = "true" ]; then
        # Replace specific IPs with generic placeholders
        if [ -n "$OPENCLOUD_IP" ]; then
            text=$(echo "$text" | sed "s/${OPENCLOUD_IP}/[OPENCLOUD-IP]/g")
        fi
        if [ -n "$COLLABORA_IP" ]; then
            text=$(echo "$text" | sed "s/${COLLABORA_IP}/[COLLABORA-IP]/g")
        fi
        if [ -n "$COLLABORATION_IP" ]; then
            text=$(echo "$text" | sed "s/${COLLABORATION_IP}/[WOPI-IP]/g")
        fi
        
        # Replace generic IP patterns
        text=$(echo "$text" | sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[IP-HIDDEN]/g')
        
        # Replace password/token patterns
        text=$(echo "$text" | sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=[^[:space:]]+/\1=[REDACTED]/gi')
        text=$(echo "$text" | sed -E 's/(password|token|secret|key)[:=][^[:space:]]+/\1=[REDACTED]/gi')
        
        # Replace domain names with generic versions (optional - uncomment if needed)
        # text=$(echo "$text" | sed "s/${OCIS_DOMAIN}/opencloud.example.com/g")
        # text=$(echo "$text" | sed "s/${COLLABORA_DOMAIN}/collabora.example.com/g")
        # text=$(echo "$text" | sed "s/${WOPISERVER_DOMAIN}/wopiserver.example.com/g")
        
        # Mark certificate data as hidden
        if echo "$text" | grep -q "BEGIN CERTIFICATE"; then
            text="[SSL-CERTIFICATE-DETAILS-HIDDEN-FOR-PRIVACY]"
        fi
    fi
    
    echo "$text"
}

# Initialize diagnostic file
init_diagnostic_file() {
    mkdir -p "$(dirname "$DIAGNOSTIC_FILE")"
    
    local header="================================================================================
OpenCloud + Collabora + WOPI Integration Diagnostic Report
================================================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
Unraid Version: $(cat /etc/unraid-version 2>/dev/null || echo "Unknown")

Configuration:
  OpenCloud:     https://${OCIS_DOMAIN}
  Collabora:     https://${COLLABORA_DOMAIN}
  WOPI Server:   https://${WOPISERVER_DOMAIN}
  Proxy Type:    ${PROXY_TYPE}
  Network:       ${NETWORK_NAME}
  Sensitive Data Hiding: ${HIDE_SENSITIVE_DATA}

================================================================================"
    
    if [ "$HIDE_SENSITIVE_DATA" = "true" ]; then
        header="$header

⚠️ PRIVACY MODE ENABLED ⚠️
This report has been sanitized for public sharing:
  - IP addresses replaced with placeholders
  - Passwords/tokens redacted
  - SSL certificates hidden
  - Some technical details may be obscured for privacy

================================================================================"
    fi
    
    echo "$header" > "$DIAGNOSTIC_FILE"
    echo "" >> "$DIAGNOSTIC_FILE"
}

# Log to both console and file with sanitization
log_both() {
    local sanitized=$(sanitize "$1")
    echo -e "$sanitized" | tee -a "$DIAGNOSTIC_FILE"
}

# Log only to file with sanitization
log_file() {
    local sanitized=$(sanitize "$1")
    echo -e "$sanitized" >> "$DIAGNOSTIC_FILE"
}

print_header() {
    log_both "${CYAN}================================================${NC}"
    log_both "${CYAN}$1${NC}"
    log_both "${CYAN}================================================${NC}"
}

print_section() {
    log_both ""
    log_both "${BLUE}[TEST] $1${NC}"
    log_both "----------------------------------------"
}

# Track component for categorization
track_component() {
    local component="$1"
    COMPONENT_TESTS[$component]=$((${COMPONENT_TESTS[$component]:-0} + 1))
}

test_passed() {
    local message="$1"
    local details="$2"
    local component="${3:-General}"
    
    log_both "${GREEN}✓ PASS${NC}: $message"
    if [ -n "$details" ]; then
        log_file "  Details: $details"
    fi
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
    
    track_component "$component"
    COMPONENT_PASSED[$component]=$((${COMPONENT_PASSED[$component]:-0} + 1))
}

test_failed() {
    local message="$1"
    local error_details="$2"
    local component="${3:-General}"
    local is_critical="${4:-false}"
    
    log_both "${RED}✗ FAIL${NC}: $message"
    
    if [ -n "$error_details" ]; then
        log_both "  ${RED}Error:${NC} ${error_details:0:200}"
        log_file "  Full Error Details:"
        log_file "$error_details"
        DETAILED_ERRORS+=("FAIL|$component|$message|$error_details")
    fi
    
    FAILURES+=("$component: $message")
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
    
    track_component "$component"
    COMPONENT_FAILED[$component]=$((${COMPONENT_FAILED[$component]:-0} + 1))
    
    if [ "$is_critical" = "true" ]; then
        CRITICAL_FAILURES=true
    fi
}

test_warning() {
    local message="$1"
    local warning_details="$2"
    local component="${3:-General}"
    
    log_both "${YELLOW}⚠ WARN${NC}: $message"
    
    if [ -n "$warning_details" ]; then
        log_both "  ${YELLOW}Details:${NC} ${warning_details:0:200}"
        log_file "$warning_details"
        DETAILED_ERRORS+=("WARN|$component|$message|$warning_details")
    fi
    
    WARNINGS+=("$component: $message")
    ((WARNING_TESTS++))
    ((TOTAL_TESTS++))
    
    track_component "$component"
    COMPONENT_WARNINGS[$component]=$((${COMPONENT_WARNINGS[$component]:-0} + 1))
}

add_recommendation() {
    RECOMMENDATIONS+=("$1")
    log_file "  Recommendation: $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

################################################################################
# MAIN DIAGNOSTIC SCRIPT
################################################################################

clear
init_diagnostic_file

print_header "OpenCloud + Collabora Diagnostic Tool v2"
log_both ""
log_both "Configuration:"
log_both "  OpenCloud:     https://${OCIS_DOMAIN}"
log_both "  Collabora:     https://${COLLABORA_DOMAIN}"
log_both "  WOPI Server:   https://${WOPISERVER_DOMAIN}"
log_both "  Proxy Type:    ${PROXY_TYPE}"
log_both "  Network:       ${NETWORK_NAME}"

if [ "$HIDE_SENSITIVE_DATA" = "true" ]; then
    log_both ""
    log_both "${YELLOW}⚠️  Privacy Mode: ENABLED${NC}"
    log_both "  Output sanitized for public sharing"
fi

log_both ""
log_both "Diagnostic report will be saved to:"
log_both "  ${DIAGNOSTIC_FILE}"
log_both ""
log_both "Starting diagnostics..."
sleep 2

################################################################################
# TEST 1: SYSTEM PREREQUISITES
################################################################################

print_section "System Prerequisites"

# Check Docker
if check_command docker; then
    DOCKER_VERSION=$(docker --version 2>&1)
    test_passed "Docker installed" "$DOCKER_VERSION" "System"
    log_file "Docker version: $DOCKER_VERSION"
else
    test_failed "Docker not found" "Docker command not available in PATH" "System" "true"
    log_both "${RED}CRITICAL: Cannot continue without Docker${NC}"
    exit 1
fi

# Check curl
if check_command curl; then
    CURL_VERSION=$(curl --version 2>&1 | head -1)
    test_passed "curl command available" "$CURL_VERSION" "System"
else
    test_failed "curl not found (required for testing)" "curl command not in PATH" "System"
    add_recommendation "Install curl: opkg install curl"
fi

# Check jq
if check_command jq; then
    JQ_VERSION=$(jq --version 2>&1)
    test_passed "jq available (JSON parsing enabled)" "$JQ_VERSION" "System"
else
    test_warning "jq not found (some tests will be limited)" "JSON parsing will be unavailable" "System"
    add_recommendation "Install jq for better JSON parsing: opkg install jq"
fi

################################################################################
# TEST 2: DOCKER NETWORK
################################################################################

print_section "Docker Network Configuration"

NETWORK_INSPECT=$(docker network inspect "${NETWORK_NAME}" 2>&1)
if [ $? -eq 0 ]; then
    test_passed "Network '${NETWORK_NAME}' exists" "" "Network"
    
    log_file "Full network details:"
    log_file "$NETWORK_INSPECT"
    
    NETWORK_SUBNET=$(echo "$NETWORK_INSPECT" | grep -o '"Subnet": "[^"]*"' | head -1 | cut -d'"' -f4)
    NETWORK_GATEWAY=$(echo "$NETWORK_INSPECT" | grep -o '"Gateway": "[^"]*"' | head -1 | cut -d'"' -f4)
    
    log_both "  Network Details:"
    log_both "    Subnet:  ${NETWORK_SUBNET}"
    log_both "    Gateway: ${NETWORK_GATEWAY}"
    
    log_both "  Containers on network:"
    NETWORK_CONTAINERS=$(docker network inspect "${NETWORK_NAME}" --format='{{range .Containers}}{{.Name}} ({{.IPv4Address}}){{println}}{{end}}' 2>/dev/null)
    if [ -n "$NETWORK_CONTAINERS" ]; then
        echo "$NETWORK_CONTAINERS" | while read line; do
            log_both "    - $line"
        done
    else
        test_warning "No containers found on network '${NETWORK_NAME}'" "Network exists but has no connected containers" "Network"
    fi
else
    ERROR_MSG=$(echo "$NETWORK_INSPECT" | tail -5)
    test_failed "Network '${NETWORK_NAME}' does not exist" "$ERROR_MSG" "Network" "true"
    add_recommendation "Create network: docker network create ${NETWORK_NAME}"
fi

################################################################################
# TEST 3: CONTAINER STATUS
################################################################################

print_section "Container Status"

check_container() {
    local container_name=$1
    local service_name=$2
    local component=$3
    
    CONTAINER_PS=$(docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}|{{.Status}}|{{.State}}" 2>&1)
    
    if echo "$CONTAINER_PS" | grep -q "^${container_name}"; then
        STATUS=$(echo "$CONTAINER_PS" | cut -d'|' -f2)
        STATE=$(echo "$CONTAINER_PS" | cut -d'|' -f3)
        
        CONTAINER_DETAILS=$(docker inspect "${container_name}" 2>&1)
        log_file "Container ${container_name} full details:"
        log_file "$CONTAINER_DETAILS"
        
        if [ "$STATE" = "running" ]; then
            UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "${container_name}" 2>/dev/null)
            test_passed "${service_name} container '${container_name}' is running" "Started: ${UPTIME}, Status: ${STATUS}" "$component"
            log_both "    Started: ${UPTIME}"
            
            CONTAINER_NETWORKS=$(docker inspect --format='{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "${container_name}" 2>/dev/null)
            if echo "$CONTAINER_NETWORKS" | grep -q "${NETWORK_NAME}"; then
                test_passed "${service_name} is on network '${NETWORK_NAME}'" "Networks: ${CONTAINER_NETWORKS}" "$component"
            else
                test_failed "${service_name} is NOT on network '${NETWORK_NAME}'" "Current networks: ${CONTAINER_NETWORKS}, Expected: ${NETWORK_NAME}" "$component" "true"
                add_recommendation "Connect ${container_name} to network: docker network connect ${NETWORK_NAME} ${container_name}"
            fi
            
            CONTAINER_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}" 2>/dev/null | head -1)
            log_both "    Container IP: ${CONTAINER_IP}"
            
            return 0
        else
            CONTAINER_LOGS=$(docker logs "${container_name}" --tail 20 2>&1)
            test_failed "${service_name} container '${container_name}' is ${STATE}" "Status: ${STATUS}\n\nLast 20 log lines:\n${CONTAINER_LOGS}" "$component" "true"
            add_recommendation "Start ${container_name} container"
            return 1
        fi
    else
        test_failed "${service_name} container '${container_name}' not found" "Docker ps output: ${CONTAINER_PS}" "$component" "true"
        add_recommendation "Install and start ${service_name} container"
        return 1
    fi
}

OPENCLOUD_RUNNING=false
COLLABORA_RUNNING=false
COLLABORATION_RUNNING=false

if check_container "${OPENCLOUD_CONTAINER}" "OpenCloud" "OpenCloud"; then
    OPENCLOUD_RUNNING=true
    OPENCLOUD_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${OPENCLOUD_CONTAINER}" 2>/dev/null | head -1)
fi

if check_container "${COLLABORA_CONTAINER}" "Collabora" "Collabora"; then
    COLLABORA_RUNNING=true
    COLLABORA_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${COLLABORA_CONTAINER}" 2>/dev/null | head -1)
fi

if check_container "${COLLABORATION_CONTAINER}" "Collaboration (WOPI)" "WOPI Server"; then
    COLLABORATION_RUNNING=true
    COLLABORATION_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${COLLABORATION_CONTAINER}" 2>/dev/null | head -1)
fi

################################################################################
# TEST 4: PORT BINDING
################################################################################

print_section "Port Bindings"

check_port_binding() {
    local container_name=$1
    local expected_port=$2
    local service_name=$3
    local component=$4
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        ALL_PORTS=$(docker port "${container_name}" 2>&1)
        log_file "All ports for ${container_name}:"
        log_file "$ALL_PORTS"
        
        BOUND_PORTS=$(echo "$ALL_PORTS" | grep "${expected_port}/tcp" | awk '{print $3}')
        if [ -n "$BOUND_PORTS" ]; then
            test_passed "${service_name} port ${expected_port} is bound to ${BOUND_PORTS}" "Full port list: ${ALL_PORTS}" "$component"
        else
            test_warning "${service_name} port ${expected_port} not found in port bindings" "Available ports: ${ALL_PORTS}" "$component"
        fi
    fi
}

if [ "$OPENCLOUD_RUNNING" = true ]; then
    check_port_binding "${OPENCLOUD_CONTAINER}" "9200" "OpenCloud" "OpenCloud"
    check_port_binding "${OPENCLOUD_CONTAINER}" "9233" "OpenCloud NATS" "OpenCloud"
fi

if [ "$COLLABORA_RUNNING" = true ]; then
    check_port_binding "${COLLABORA_CONTAINER}" "9980" "Collabora" "Collabora"
fi

if [ "$COLLABORATION_RUNNING" = true ]; then
    check_port_binding "${COLLABORATION_CONTAINER}" "9300" "Collaboration WOPI" "WOPI Server"
    check_port_binding "${COLLABORATION_CONTAINER}" "9301" "Collaboration gRPC" "WOPI Server"
fi

################################################################################
# TEST 5: CONFIGURATION FILES
################################################################################

print_section "Configuration Files"

if [ -f "${OCL_CONFIG}/csp.yaml" ]; then
    test_passed "CSP configuration file exists" "Path: ${OCL_CONFIG}/csp.yaml" "OpenCloud"
    
    CSP_CONTENT=$(cat "${OCL_CONFIG}/csp.yaml" 2>&1)
    log_file "CSP file contents:"
    log_file "$CSP_CONTENT"
    
    if grep -q "${COLLABORA_DOMAIN}" "${OCL_CONFIG}/csp.yaml"; then
        test_passed "CSP includes Collabora domain" "Found ${COLLABORA_DOMAIN} in CSP config" "OpenCloud"
    else
        test_failed "CSP does NOT include Collabora domain" "Expected to find ${COLLABORA_DOMAIN} in frame-src and img-src\n\nCurrent CSP content:\n${CSP_CONTENT}" "OpenCloud" "true"
        add_recommendation "Add Collabora domain to ${OCL_CONFIG}/csp.yaml frame-src and img-src sections"
    fi
else
    test_failed "CSP configuration file missing: ${OCL_CONFIG}/csp.yaml" "File does not exist at expected location" "OpenCloud" "true"
    add_recommendation "Create CSP configuration file - this is CRITICAL for Collabora integration"
fi

if [ -f "${OCL_CONFIG}/banned-password-list.txt" ]; then
    test_passed "Banned password list exists" "Path: ${OCL_CONFIG}/banned-password-list.txt" "OpenCloud"
else
    test_warning "Banned password list not found" "Expected at ${OCL_CONFIG}/banned-password-list.txt" "OpenCloud"
fi

if [ -d "${OCL_DATA}" ]; then
    DATA_SIZE=$(du -sh "${OCL_DATA}" 2>/dev/null | cut -f1)
    test_passed "Data directory exists: ${OCL_DATA}" "Size: ${DATA_SIZE}" "OpenCloud"
else
    test_failed "Data directory missing: ${OCL_DATA}" "Directory does not exist" "OpenCloud" "true"
fi

################################################################################
# TEST 6: INTERNAL CONTAINER CONNECTIVITY
################################################################################

print_section "Internal Container-to-Container Connectivity"

if [ "$OPENCLOUD_RUNNING" = true ] && [ "$COLLABORA_RUNNING" = true ] && [ "$COLLABORATION_RUNNING" = true ]; then
    
    log_both "Testing: OpenCloud -> Collabora..."
    TEST_RESULT=$(docker exec "${OPENCLOUD_CONTAINER}" wget -q -O- --timeout=5 "http://${COLLABORA_IP}:9980/" 2>&1)
    if [ $? -eq 0 ]; then
        test_passed "OpenCloud can reach Collabora internally (${COLLABORA_IP}:9980)" "Response received successfully" "Connectivity"
    else
        test_failed "OpenCloud CANNOT reach Collabora internally" "Target: http://${COLLABORA_IP}:9980/\nError: ${TEST_RESULT}" "Connectivity" "true"
        add_recommendation "Check network connectivity and firewall rules between containers"
    fi
    
    log_both "Testing: OpenCloud -> Collaboration (WOPI)..."
    TEST_RESULT=$(docker exec "${OPENCLOUD_CONTAINER}" wget -q -O- --timeout=5 "http://${COLLABORATION_IP}:9300/wopi" 2>&1)
    # HTTP 418 "I
