#!/bin/bash

# Continuous Ping Data Collector for Kusto
# Usage: ./network-monitor-kusto.sh <ip1> <ip2> [ip3] [ip4] ...
#
# This script continuously pings a list of IP addresses and uploads
# every individual ping result directly to Azure Data Explorer (Kusto).
# No file output, no threshold monitoring - pure data collection.

# Configuration
PING_INTERVAL=5        # seconds between ping rounds
PING_COUNT=1          # single ping per IP per round
PING_TIMEOUT=3        # timeout for each ping
RETRY_INTERVAL=30     # seconds between retry attempts for failed uploads
MAX_BUFFER_SIZE=1000  # maximum number of records to buffer locally

# Configuration file path
CONFIG_FILE="$(dirname "$0")/kusto-config.conf"
BUFFER_FILE="$(dirname "$0")/kusto-buffer.jsonl"

# Global variables for failure tracking
CURRENT_FAILURE_ID=""

# Function to load configuration from file
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        log "ERROR" "Please copy kusto-config.conf.template to kusto-config.conf and configure it"
        return 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required configuration
    if [[ -z "$KUSTO_CLUSTER_URL" || -z "$KUSTO_DATABASE" || -z "$KUSTO_TABLE" || 
          -z "$KUSTO_CLIENT_ID" || -z "$KUSTO_CLIENT_SECRET" || -z "$KUSTO_TENANT_ID" || -z "$SOURCE" ]]; then
        log "ERROR" "Missing required configuration in $CONFIG_FILE"
        log "ERROR" "Please ensure all required fields are set (including SOURCE)"
        return 1
    fi
    
    log "INFO" "Configuration loaded from $CONFIG_FILE"
    return 0
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
show_usage() {
    cat << 'EOF'
===============================================================================
                    CONTINUOUS PING DATA COLLECTOR - KUSTO UPLOAD
===============================================================================

NAME
    network-monitor-kusto.sh - Continuous ping data collector with Kusto upload

SYNOPSIS
    network-monitor-kusto.sh <ip1> <ip2> [ip3] [ip4] ...

DESCRIPTION
    Continuously pings a list of IP addresses and uploads every individual
    ping result directly to Azure Data Explorer (Kusto). This is a pure
    data collection tool designed to run alongside your main monitoring
    script.

    Features:
    • Continuous ping data collection from multiple IPs
    • Every ping result uploaded to Kusto immediately
    • Local buffering with retry for connectivity issues
    • No threshold monitoring or diagnostic triggers
    • Configurable ping intervals
    • Designed for parallel operation with file-based monitoring

REQUIRED ARGUMENTS
    ip1, ip2, ...   One or more IP addresses to continuously ping

CONFIGURATION
    Create and configure kusto-config.conf file:
    
    1. Copy the template:
       cp kusto-config.conf.template kusto-config.conf
    
    2. Edit kusto-config.conf with your Azure settings:
       - KUSTO_CLUSTER_URL: Your Azure Data Explorer cluster URL
       - KUSTO_DATABASE: Database name (default: NetworkMonitoring)
       - KUSTO_TABLE: Table name (default: NetworkTests)
       - KUSTO_CLIENT_ID: Azure AD application client ID
       - KUSTO_CLIENT_SECRET: Azure AD application client secret
       - KUSTO_TENANT_ID: Azure AD tenant ID

CURRENT CONFIGURATION
EOF
    printf "    Ping interval:        %ds (between ping rounds)\n" "$PING_INTERVAL"
    printf "    Ping count:           %d (per IP per round)\n" "$PING_COUNT"
    printf "    Ping timeout:         %ds\n" "$PING_TIMEOUT"
    printf "    Configuration file:   %s\n" "$CONFIG_FILE"
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE" 2>/dev/null || true
        printf "    Kusto cluster:        %s\n" "${KUSTO_CLUSTER_URL:-Not configured}"
        printf "    Kusto database:       %s\n" "${KUSTO_DATABASE:-Not configured}"
        printf "    Kusto table:          %s\n" "${KUSTO_TABLE:-Not configured}"
    else
        printf "    Kusto cluster:        [Configuration file missing]\n"
    fi
    printf "    Cooldown period:      15s (between diagnostic runs)\n"
    cat << 'EOF'

KUSTO TABLE SCHEMA
    The data is uploaded to a table with the following schema:
    
    | Column          | Type     | Description                               |
    |-----------------|----------|-------------------------------------------|
    | timestamp       | datetime | When the ping was sent                    |
    | dstIp          | string   | Destination IP address pinged             |
    | sequenceNumber | int      | Ping sequence number                      |
    | responseTime   | real     | Response time in milliseconds (null if timeout) |
    | ttl            | int      | Time to live value (null if timeout)     |
    | sourceHost     | string   | Hostname where ping was executed          |
    | success        | bool     | Whether ping was successful               |

AZURE AUTHENTICATION SETUP
    1. Create an Azure AD application:
       az ad app create --display-name "NetworkMonitorKusto"
       
    2. Create a service principal:
       az ad sp create --id <app-id>
       
    3. Get the client secret:
       az ad app credential reset --id <app-id>
       
    4. Grant permissions to your Kusto database:
       - Open Azure Data Explorer web UI
       - Grant 'Database Ingestor' role to the service principal

USAGE EXAMPLES
    Setup configuration file:
    cp kusto-config.conf.template kusto-config.conf
    # Edit kusto-config.conf with your Azure settings
    
    Run continuous data collection:
    ./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 208.67.222.222
    
    Run alongside your existing file-based monitor:
    ./network-monitor.sh 192.168.1.1 8.8.8.8 1.1.1.1 &
    ./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9

CONTROL
    Start:      ./network-monitor-kusto.sh <args>
    Stop:       Press Ctrl+C for graceful shutdown

===============================================================================
EOF
}

# Function to log with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[${timestamp}] INFO:${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[${timestamp}] WARN:${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] ERROR:${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] SUCCESS:${NC} $message"
            ;;
    esac
}

# Function to get Azure AD access token
get_azure_token() {
    local token_response
    local access_token
    
    if [[ -z "$KUSTO_CLIENT_ID" || -z "$KUSTO_CLIENT_SECRET" || -z "$KUSTO_TENANT_ID" ]]; then
        log "ERROR" "Azure AD authentication not configured in $CONFIG_FILE"
        log "ERROR" "Please set KUSTO_CLIENT_ID, KUSTO_CLIENT_SECRET, and KUSTO_TENANT_ID"
        return 1
    fi
    
    token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/${KUSTO_TENANT_ID}/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${KUSTO_CLIENT_ID}" \
        -d "client_secret=${KUSTO_CLIENT_SECRET}" \
        -d "scope=https://kusto.kusto.windows.net/.default" \
        -d "grant_type=client_credentials")
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to get Azure AD token: curl request failed"
        return 1
    fi
    
    access_token=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$access_token" ]]; then
        log "ERROR" "Failed to extract access token from response: $token_response"
        return 1
    fi
    
    echo "$access_token"
}

# Function to generate a unique failure ID (UUID-like)
generate_failure_id() {
    # Generate a UUID-like identifier using available tools
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # Fallback: create UUID-like string using date, random, and process ID
        printf "%08x-%04x-%04x-%04x-%012x" \
            $(($(date +%s))) \
            $((RANDOM)) \
            $((RANDOM)) \
            $((RANDOM)) \
            $$$(date +%N | cut -c1-8)
    fi
}

# Function to add failed upload to local buffer
add_to_buffer() {
    local record="$1"
    
    # Generate new failure ID if this is the start of a new failure session
    if [[ -z "$CURRENT_FAILURE_ID" ]]; then
        CURRENT_FAILURE_ID=$(generate_failure_id)
        log "INFO" "New failure session started: $CURRENT_FAILURE_ID"
    fi
    
    # Add failureId to the record
    local record_with_failure_id=$(echo "$record" | sed 's/}$/, "failureId": "'$CURRENT_FAILURE_ID'"}&/')
    
    # Check buffer size and rotate if needed
    if [[ -f "$BUFFER_FILE" ]]; then
        local buffer_lines=$(wc -l < "$BUFFER_FILE" 2>/dev/null || echo 0)
        if [[ $buffer_lines -ge $MAX_BUFFER_SIZE ]]; then
            # Keep only the last 80% of records to prevent infinite growth
            local keep_lines=$((MAX_BUFFER_SIZE * 80 / 100))
            tail -n "$keep_lines" "$BUFFER_FILE" > "${BUFFER_FILE}.tmp" && mv "${BUFFER_FILE}.tmp" "$BUFFER_FILE"
            log "WARN" "Buffer rotated: keeping last $keep_lines records"
        fi
    fi
    
    # Add record with failure ID to buffer
    echo "$record_with_failure_id" >> "$BUFFER_FILE"
    
    if [[ "${KUSTO_DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "Added record to local buffer"
    fi
}

# Function to process buffered records
process_buffer() {
    if [[ ! -f "$BUFFER_FILE" ]] || [[ ! -s "$BUFFER_FILE" ]]; then
        return 0
    fi
    
    local processed=0
    local failed=0
    local temp_buffer="${BUFFER_FILE}.processing"
    
    # Read buffer line by line
    while IFS= read -r record; do
        if [[ -n "$record" ]]; then
            # Try to upload the buffered record
            if upload_record_direct "$record"; then
                ((processed++))
            else
                # Keep failed records for next retry
                echo "$record" >> "$temp_buffer"
                ((failed++))
            fi
        fi
    done < "$BUFFER_FILE"
    
    # Replace buffer with failed records only
    if [[ -f "$temp_buffer" ]]; then
        mv "$temp_buffer" "$BUFFER_FILE"
    else
        # All records processed successfully
        rm -f "$BUFFER_FILE"
    fi
    
    if [[ $processed -gt 0 ]]; then
        log "SUCCESS" "Uploaded $processed buffered records to Kusto"
        # Clear the current failure ID since we successfully processed records
        if [[ $failed -eq 0 ]]; then
            CURRENT_FAILURE_ID=""
        fi
    fi
    
    if [[ $failed -gt 0 ]] && [[ "${KUSTO_DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$failed records remain in buffer for retry"
    fi
    
    return 0
}

# Function to upload a record directly (used for both immediate and buffered uploads)
upload_record_direct() {
    local record="$1"
    
    # Get access token
    local access_token=$(get_azure_token)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Upload to Kusto using REST API
    local kusto_url="${KUSTO_CLUSTER_URL}/v1/rest/ingest/${KUSTO_DATABASE}/${KUSTO_TABLE}?streamFormat=json&mappingName=JsonMapping"
    
    local response=$(curl -s -X POST "$kusto_url" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-raw "$record")
    
    if [[ $? -eq 0 ]] && echo "$response" | grep -q '"Rows":\[\[1,'; then
        return 0
    else
        return 1
    fi
}

# Function to upload individual ping result to Kusto
upload_ping_to_kusto() {
    local dst_ip="$1"
    local sequence_number="$2"
    local response_time="$3"  # in ms, or "timeout"
    local ttl="$4"            # or "timeout"
    local success="$5"        # true/false
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    # Get access token
    local access_token=$(get_azure_token)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to get Azure access token"
        return 1
    fi
    
    # Create single record per ping with response time as the observable
    local observable_type="responseTime"
    local observable_value
    
    # Handle timeout vs successful ping
    if [[ "$response_time" == "timeout" ]] || [[ "$success" == "false" ]]; then
        observable_type="timeout"
        observable_value="1"  # 1 indicates timeout occurred
    else
        observable_type="responseTime"
        observable_value="$response_time"
    fi
    
    local record=$(cat <<EOF
{"timestamp": "$timestamp", "type": "ping", "dstIp": "$dst_ip", "observableType": "$observable_type", "observableValue": $observable_value, "source": "$SOURCE", "failureId": null}
EOF
)
    
    # Upload to Kusto using REST API
    local kusto_url="${KUSTO_CLUSTER_URL}/v1/rest/ingest/${KUSTO_DATABASE}/${KUSTO_TABLE}?streamFormat=json&mappingName=JsonMapping"
    
    # Log the upload attempt if debug is enabled
    if [[ "${KUSTO_DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "Uploading to URL: $kusto_url"
        log "DEBUG" "Record data: $record"
    fi
    
    # Try immediate upload first
    if upload_record_direct "$record"; then
        if [[ "${KUSTO_DEBUG:-false}" == "true" ]]; then
            log "DEBUG" "Successfully uploaded ping result for $dst_ip (1 record consumed)"
        fi
        return 0
    else
        # Upload failed, add to local buffer for retry
        add_to_buffer "$record"
        if [[ "${KUSTO_DEBUG:-false}" == "true" ]]; then
            log "DEBUG" "Upload failed for $dst_ip, added to buffer for retry"
        fi
        return 1
    fi
}

# Function to parse ping result and extract details
parse_ping_result() {
    local ping_output="$1"
    local target_ip="$2"
    
    # Check if ping was successful
    if echo "$ping_output" | grep -q "time="; then
        # Extract details from successful ping
        local response_time=$(echo "$ping_output" | grep "time=" | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p')
        local sequence=$(echo "$ping_output" | grep "icmp_seq=" | sed -n 's/.*icmp_seq=\([0-9]*\).*/\1/p')
        local ttl=$(echo "$ping_output" | grep "ttl=" | sed -n 's/.*ttl=\([0-9]*\).*/\1/p')
        
        # Upload successful ping
        upload_ping_to_kusto "$target_ip" "${sequence:-1}" "$response_time" "$ttl" "true"
        
        if [[ $? -eq 0 ]]; then
            echo -ne "\r${GREEN}[$(date '+%H:%M:%S')] $target_ip: ${response_time}ms${NC}    "
        else
            log "WARN" "Failed to upload ping result for $target_ip"
        fi
    else
        # Handle timeout/failure
        upload_ping_to_kusto "$target_ip" "1" "timeout" "timeout" "false"
        
        if [[ $? -eq 0 ]]; then
            echo -ne "\r${RED}[$(date '+%H:%M:%S')] $target_ip: TIMEOUT${NC}    "
        else
            log "WARN" "Failed to upload timeout result for $target_ip"
        fi
    fi
}

# Function to continuously ping a single IP
ping_target() {
    local target_ip="$1"
    
    while true; do
        # Execute single ping with timeout
        local ping_output
        ping_output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$target_ip" 2>&1)
        
        # Parse and upload result
        parse_ping_result "$ping_output" "$target_ip"
        
        # Wait for next ping round
        sleep "$PING_INTERVAL"
    done
}

# Function to periodically process buffered uploads
buffer_processor() {
    while true; do
        sleep "$RETRY_INTERVAL"
        process_buffer
    done
}

# Function to validate IP address format
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to test connectivity to all IPs
test_connectivity() {
    local test_ip="$1"
    shift
    local diagnostic_ips=("$@")
    
    log "INFO" "Testing connectivity to all specified IPs..."
    
    # Test primary IP
    if ! ping -c 1 -W 3 "$test_ip" > /dev/null 2>&1; then
        log "ERROR" "Cannot reach test IP: $test_ip"
        return 1
    fi
    
    # Test diagnostic IPs
    for ip in "${diagnostic_ips[@]}"; do
        if ! ping -c 1 -W 3 "$ip" > /dev/null 2>&1; then
            log "WARN" "Cannot reach diagnostic IP: $ip (will continue anyway)"
        fi
    done
    
    log "SUCCESS" "Connectivity test completed"
    return 0
}

# Function to validate Kusto configuration
validate_kusto_config() {
    log "INFO" "Validating Kusto configuration..."
    
    # Load configuration from file
    if ! load_config; then
        return 1
    fi
    
    # Test authentication
    local token=$(get_azure_token)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to authenticate with Azure AD"
        return 1
    fi
    
    log "SUCCESS" "Kusto configuration validated"
    return 0
}

# Signal handler for graceful shutdown
cleanup() {
    log "INFO" "Received interrupt signal. Stopping network monitor..."
    
    # Try to process any remaining buffered records
    if [[ -f "$BUFFER_FILE" ]] && [[ -s "$BUFFER_FILE" ]]; then
        log "INFO" "Processing remaining buffered records..."
        process_buffer
        local remaining=$(wc -l < "$BUFFER_FILE" 2>/dev/null || echo 0)
        if [[ $remaining -gt 0 ]]; then
            log "WARN" "$remaining records remain in buffer: $BUFFER_FILE"
        fi
    fi
    
    # Allow any running diagnostics to complete before exiting
    log "INFO" "Waiting for any running diagnostics to complete..."
    wait 2>/dev/null
    exit 0
}

# Main function
main() {
    # Check for help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    # Check arguments
    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi
    
    local target_ips=("$@")
    
    # Validate IP addresses
    for ip in "${target_ips[@]}"; do
        if ! validate_ip "$ip"; then
            log "ERROR" "Invalid IP address: $ip"
            exit 1
        fi
    done
    
    # Load configuration from file
    if ! load_config; then
        log "ERROR" "Failed to load configuration"
        exit 1
    fi
    
    # Validate Kusto configuration
    if ! validate_kusto_config; then
        log "ERROR" "Kusto configuration validation failed"
        exit 1
    fi
    
    # Test initial connectivity
    log "INFO" "Testing connectivity to target IPs..."
    for ip in "${target_ips[@]}"; do
        if ! ping -c 1 -W 3 "$ip" > /dev/null 2>&1; then
            log "WARN" "Cannot reach IP: $ip (will continue anyway)"
        fi
    done
    
    # Set up signal handler
    trap cleanup SIGINT SIGTERM
    
    # Display configuration
    log "INFO" "Starting continuous ping data collection for Kusto"
    log "INFO" "Target IPs: ${target_ips[*]}"
    log "INFO" "Ping interval: ${PING_INTERVAL}s"
    log "INFO" "Ping timeout: ${PING_TIMEOUT}s"
    log "INFO" "Configuration file: $CONFIG_FILE"
    log "INFO" "Kusto cluster: $KUSTO_CLUSTER_URL"
    log "INFO" "Kusto database: $KUSTO_DATABASE"
    log "INFO" "Kusto table: $KUSTO_TABLE"
    echo ""
    log "INFO" "Starting parallel ping processes..."
    
    # Start buffer processor in background
    log "INFO" "Starting buffer processor for retry uploads"
    buffer_processor &
    local buffer_pid=$!
    
    # Start ping processes for each IP in parallel
    local pids=()
    for ip in "${target_ips[@]}"; do
        log "INFO" "Starting ping process for $ip"
        ping_target "$ip" &
        pids+=($!)
    done
    
    # Add buffer processor to pids list
    pids+=($buffer_pid)
    
    # Wait for all processes (they run forever until interrupted)
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Check if required tools are installed
check_dependencies() {
    local missing=()
    
    if ! command -v ping >/dev/null 2>&1; then
        missing+=("ping")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing required tools: ${missing[*]}"
        log "ERROR" "Please install missing tools and try again"
        log "INFO" "On Ubuntu/Debian: sudo apt-get install ${missing[*]}"
        log "INFO" "On RHEL/CentOS: sudo yum install ${missing[*]}"
        exit 1
    fi
}

# Check dependencies before starting
check_dependencies

# Run main function with all arguments
main "$@"