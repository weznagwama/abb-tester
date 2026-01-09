#!/bin/bash

# Kusto Setup Helper Script
# This script helps set up Azure Data Explorer (Kusto) for network monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/kusto-config.conf"

# Function to load configuration from file
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    source "$CONFIG_FILE"
    return 0
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

show_usage() {
    cat << 'EOF'
===============================================================================
                         KUSTO SETUP HELPER SCRIPT
===============================================================================

NAME
    kusto-setup.sh - Setup Azure Data Explorer for network monitoring

SYNOPSIS
    kusto-setup.sh <command> [options]

DESCRIPTION
    Helper script to set up Azure Data Explorer (Kusto) cluster, database,
    and table for network monitoring data ingestion.

COMMANDS
    create-table         Create the NetworkTests table with proper schema
    create-app          Create Azure AD application for authentication
    show-kql            Display the KQL commands for manual setup
    test-connection     Test connection to Kusto cluster
    generate-config     Create kusto-config.conf from template
    list-apps          List existing Azure AD applications

OPTIONS
    --cluster-url <url>    Kusto cluster URL (optional if set in config)
    --database <name>      Database name (default: NetworkMonitoring)
    --table <name>         Table name (default: NetworkTests)
    --app-name <name>      Application name for Azure AD app creation

CONFIGURATION
    This script uses kusto-config.conf for connection settings.
    Create it with: ./kusto-setup.sh generate-config

EXAMPLES
    # Setup from scratch
    ./kusto-setup.sh generate-config
    # Edit kusto-config.conf with your settings
    ./kusto-setup.sh show-kql
    ./kusto-setup.sh create-app --app-name "NetworkMonitorApp"
    ./kusto-setup.sh test-connection

===============================================================================
EOF
}

# Function to show KQL commands for manual setup
show_kql() {
    local database="${1:-NetworkMonitoring}"
    local table="${2:-NetworkTests}"
    
    log "INFO" "KQL commands for manual setup in Azure Data Explorer:"
    echo ""
    
    cat << EOF
// 1. Create database (run in cluster scope)
.create database ${database}

// 2. Use the database
.database ${database}

// 3. Create the NetworkTests table (matching your existing schema)
.create table ${table} (
    timestamp: datetime,
    type: string,
    dstIp: string,
    observableType: string,
    observableValue: real,
    source: string
)

// 4. Create ingestion mapping for JSON (matching existing schema)
.alter table ${table} ingestion json mapping "JsonMapping"
[
    { "column" : "timestamp", "DataType" : "datetime", "Properties":{"Path":"$.timestamp"}},
    { "column" : "type", "DataType" : "string", "Properties":{"Path":"$.type"}},
    { "column" : "dstIp", "DataType" : "string", "Properties":{"Path":"$.dstIp"}},
    { "column" : "observableType", "DataType" : "string", "Properties":{"Path":"$.observableType"}},
    { "column" : "observableValue", "DataType" : "real", "Properties":{"Path":"$.observableValue"}},
    { "column" : "source", "DataType" : "string", "Properties":{"Path":"$.source"}}
]

// 5. Enable streaming ingestion (REQUIRED for real-time data upload via REST API)
.alter table ${table} policy streamingingestion enable

// IMPORTANT: Also enable streaming ingestion on the database level if not already done
.alter database ${database} policy streamingingestion enable

// 6. Verify streaming ingestion is enabled (run these to check)
.show table ${table} policy streamingingestion
.show database ${database} policy streamingingestion

// 7. Sample queries to verify data
${table}
| limit 10

// Average response time by destination and source
${table}
| where observableType == "responseTime"
| summarize avg(observableValue) by dstIp, source, bin(timestamp, 1h)

// Success rate by destination and source  
${table}
| where observableType == "success"
| summarize SuccessRate=avg(observableValue) by dstIp, source, bin(timestamp, 1h)

// TTL values by destination
${table}
| where observableType == "ttl"
| summarize avg(observableValue) by dstIp, source, bin(timestamp, 1h)

// Query by specific source location
${table}
| where source == "your-location-name"
| limit 10

// All ping metrics for a specific IP
${table}
| where dstIp == "8.8.8.8"
| order by timestamp desc
| limit 20
EOF
    
    echo ""
    log "SUCCESS" "Copy and paste these commands into Azure Data Explorer web UI"
}

# Function to create Azure AD application
create_app() {
    local app_name="$1"
    
    if [[ -z "$app_name" ]]; then
        log "ERROR" "Application name required. Use --app-name option"
        exit 1
    fi
    
    log "INFO" "Creating Azure AD application: $app_name"
    
    # Check if Azure CLI is available and logged in
    if ! command -v az >/dev/null 2>&1; then
        log "ERROR" "Azure CLI not found. Please install Azure CLI first"
        log "INFO" "Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    log "INFO" "Checking Azure CLI authentication..."
    local account_info
    account_info=$(az account show --output json 2>&1)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Not logged in to Azure CLI. Please run: az login"
        log "ERROR" "Azure CLI error: $account_info"
        exit 1
    fi
    
    local current_tenant=$(echo "$account_info" | jq -r '.tenantId')
    local current_subscription=$(echo "$account_info" | jq -r '.name')
    log "INFO" "Logged in to tenant: $current_tenant"
    log "INFO" "Using subscription: $current_subscription"
    
    # Check permissions by trying a simple query
    log "INFO" "Checking permissions to create Azure AD applications..."
    local permission_check
    permission_check=$(az ad app list --query \"[0].appId\" --output tsv 2>&1)
    if [[ $? -ne 0 ]]; then
        log "WARN" "May not have permissions to query Azure AD applications"
        log "WARN" "Azure CLI response: $permission_check"
        log "INFO" "Continuing with app creation attempt..."
    fi
    
    # Create the application
    log "INFO" "Creating Azure AD application..."
    local app_result
    local create_error
    
    # Capture only JSON output, warnings go to stderr
    app_result=$(az ad app create --display-name "$app_name" --output json 2>/dev/null)
    local create_exit_code=$?
    
    if [[ $create_exit_code -ne 0 ]]; then
        log "ERROR" "Failed to create Azure AD application"
        log "ERROR" "Azure CLI error: $app_result"
        log "ERROR" "Exit code: $create_exit_code"
        
        # Check for common error scenarios
        if echo "$app_result" | grep -q "insufficient privileges"; then
            log "ERROR" "Insufficient privileges to create Azure AD applications"
            log "INFO" "You need 'Application Administrator' or 'Cloud Application Administrator' role"
            log "INFO" "Or ask your Azure AD admin to grant you permission to create applications"
        elif echo "$app_result" | grep -q "already exists"; then
            log "ERROR" "An application with this name already exists"
            log "INFO" "Try a different name: ./kusto-setup.sh create-app --app-name \"$app_name-$(date +%s)\""
        elif echo "$app_result" | grep -q "authentication"; then
            log "ERROR" "Authentication issue - try logging in again: az login"
        fi
        exit 1
    fi
    
    local app_id=$(echo "$app_result" | jq -r '.appId')
    local object_id=$(echo "$app_result" | jq -r '.id')
    
    log "SUCCESS" "Created Azure AD application: $app_name"
    log "INFO" "Application ID: $app_id"
    
    # Create service principal
    log "INFO" "Creating service principal..."
    local sp_result
    sp_result=$(az ad sp create --id "$app_id" --output json 2>/dev/null)
    local sp_exit_code=$?
    
    if [[ $sp_exit_code -ne 0 ]]; then
        log "WARN" "Failed to create service principal"
        log "WARN" "Azure CLI error: $sp_result"
        log "WARN" "Application was created successfully, but service principal creation failed"
        log "INFO" "You may need to create the service principal manually later"
    else
        log "SUCCESS" "Created service principal"
    fi
    
    # Create client secret
    log "INFO" "Creating client secret..."
    local secret_result
    # Redirect warnings to stderr while capturing JSON output
    secret_result=$(az ad app credential reset --id "$app_id" --output json 2>/dev/null)
    local secret_exit_code=$?
    
    if [[ $secret_exit_code -ne 0 ]]; then
        log "ERROR" "Failed to create client secret"
        log "ERROR" "Azure CLI error (running with verbose output):"
        az ad app credential reset --id "$app_id" --output json 2>&1
        log "ERROR" "Application and service principal may have been created, but no secret was generated"
        log "INFO" "You can create a secret manually in the Azure portal"
        log "INFO" "Application ID for manual setup: $app_id"
        exit 1
    fi
    
    local client_secret=$(echo "$secret_result" | jq -r '.password')
    local tenant_id=$(az account show --query tenantId --output tsv)
    
    # Verify the application was actually created
    log "INFO" "Verifying application creation..."
    local verify_result
    verify_result=$(az ad app show --id "$app_id" --output json 2>&1)
    if [[ $? -eq 0 ]]; then
        local app_display_name=$(echo "$verify_result" | jq -r '.displayName')
        log "SUCCESS" "Verified: Application '$app_display_name' exists in Azure AD"
    else
        log "WARN" "Could not verify application creation: $verify_result"
    fi
    
    log "SUCCESS" "Created client secret"
    echo ""
    log "INFO" "=== AZURE AD APPLICATION CONFIGURATION ==="
    echo "Application Name: $app_name"
    echo "Client ID: $app_id"
    echo "Client Secret: $client_secret"
    echo "Tenant ID: $tenant_id"
    echo ""
    log "WARN" "Save these values securely! The client secret cannot be retrieved again."
    echo ""
    log "INFO" "=== ENVIRONMENT VARIABLES ==="
    echo "export KUSTO_CLIENT_ID=\"$app_id\""
    echo "export KUSTO_CLIENT_SECRET=\"$client_secret\""
    echo "export KUSTO_TENANT_ID=\"$tenant_id\""
    echo ""
    log "INFO" "=== NEXT STEPS ==="
    log "INFO" "1. Grant permissions in Azure Data Explorer:"
    log "INFO" "   - Open your Kusto cluster in Azure Data Explorer web UI"
    log "INFO" "   - Go to Permissions"
    log "INFO" "   - Add 'Database Ingestor' role for principal: $app_id"
    log "INFO" "2. Set environment variables (see above)"
    log "INFO" "3. Run network monitor: ./network-monitor-kusto.sh"
}

# Function to test connection
test_connection() {
    local cluster_url="$1"
    
    if [[ -z "$cluster_url" ]]; then
        # Try to load from config file
        if load_config && [[ -n "$KUSTO_CLUSTER_URL" ]]; then
            cluster_url="$KUSTO_CLUSTER_URL"
            log "INFO" "Using cluster URL from configuration file: $cluster_url"
        else
            log "ERROR" "Cluster URL required. Use --cluster-url option or configure kusto-config.conf"
            exit 1
        fi
    fi
    
    log "INFO" "Testing connection to Kusto cluster: $cluster_url"
    
    # Load config for credentials
    if ! load_config; then
        log "ERROR" "Configuration file not found or invalid: $CONFIG_FILE"
        log "ERROR" "Please copy kusto-config.conf.template to kusto-config.conf and configure it"
        exit 1
    fi
    
    # Check configuration variables
    if [[ -z "$KUSTO_CLIENT_ID" || -z "$KUSTO_CLIENT_SECRET" || -z "$KUSTO_TENANT_ID" ]]; then
        log "ERROR" "Missing credentials in configuration file: $CONFIG_FILE"
        log "ERROR" "Please ensure KUSTO_CLIENT_ID, KUSTO_CLIENT_SECRET, and KUSTO_TENANT_ID are set"
        exit 1
    fi
    
    # Test authentication
    log "INFO" "Testing Azure AD authentication..."
    local token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/${KUSTO_TENANT_ID}/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${KUSTO_CLIENT_ID}" \
        -d "client_secret=${KUSTO_CLIENT_SECRET}" \
        -d "scope=https://kusto.kusto.windows.net/.default" \
        -d "grant_type=client_credentials")
    
    local access_token=$(echo "$token_response" | jq -r '.access_token // empty')
    
    if [[ -z "$access_token" ]]; then
        log "ERROR" "Failed to get access token"
        log "ERROR" "Response: $token_response"
        exit 1
    fi
    
    log "SUCCESS" "Azure AD authentication successful"
    
    # Test basic Kusto query
    log "INFO" "Testing Kusto cluster access..."
    local database="${KUSTO_DATABASE:-NetworkMonitoring}"
    
    local query_response=$(curl -s -X POST "${cluster_url}/v1/rest/query" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"db\":\"$database\",\"csl\":\".show tables\"}")
    
    if echo "$query_response" | jq -e '.Tables[0]' >/dev/null 2>&1; then
        log "SUCCESS" "Kusto cluster access successful"
        log "INFO" "Available tables in database '$database':"
        echo "$query_response" | jq -r '.Tables[0].Rows[][]' | sort | head -10
    else
        log "ERROR" "Failed to query Kusto cluster"
        log "ERROR" "Response: $query_response"
        exit 1
    fi
    
    log "SUCCESS" "Connection test completed successfully"
}

# Function to generate configuration template
generate_config() {
    log "INFO" "Generating kusto-config.conf from template..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log "WARN" "Configuration file already exists: $CONFIG_FILE"
        read -p "Overwrite existing configuration? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Configuration generation cancelled"
            return 0
        fi
    fi
    
    if [[ ! -f "$SCRIPT_DIR/kusto-config.conf.template" ]]; then
        log "ERROR" "Template file not found: $SCRIPT_DIR/kusto-config.conf.template"
        exit 1
    fi
    
    cp "$SCRIPT_DIR/kusto-config.conf.template" "$CONFIG_FILE"
    
    log "SUCCESS" "Configuration file created: $CONFIG_FILE"
    log "INFO" "Please edit this file with your Azure settings:"
    echo ""
    echo "Required settings:"
    echo "  KUSTO_CLUSTER_URL - Your Azure Data Explorer cluster URL"
    echo "  KUSTO_CLIENT_ID - Azure AD application ID"
    echo "  KUSTO_CLIENT_SECRET - Azure AD application secret"
    echo "  KUSTO_TENANT_ID - Azure AD tenant ID"
    echo ""
    log "INFO" "After configuration, test with: ./kusto-setup.sh test-connection"
}

# Function to list existing Azure AD applications
list_apps() {
    log "INFO" "Listing Azure AD applications..."
    
    # Check if Azure CLI is available and logged in
    if ! command -v az >/dev/null 2>&1; then
        log "ERROR" "Azure CLI not found. Please install Azure CLI first"
        exit 1
    fi
    
    if ! az account show >/dev/null 2>&1; then
        log "ERROR" "Not logged in to Azure CLI. Please run: az login"
        exit 1
    fi
    
    local apps_result
    apps_result=$(az ad app list --output json 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to list Azure AD applications"
        log "ERROR" "Azure CLI error: $apps_result"
        exit 1
    fi
    
    local app_count=$(echo "$apps_result" | jq length)
    log "INFO" "Found $app_count Azure AD applications:"
    echo ""
    
    if [[ "$app_count" -gt 0 ]]; then
        echo "Display Name                    | Application ID                       | Created"
        echo "--------------------------------|--------------------------------------|----------"
        echo "$apps_result" | jq -r '.[] | "\\(.displayName | (.[0:30] + (if length > 30 then "..." else "" end))) | \\(.appId) | \\(.createdDateTime // "Unknown")"' | head -20
        
        if [[ "$app_count" -gt 20 ]]; then
            echo "... and $((app_count - 20)) more applications"
        fi
        
        echo ""
        log "INFO" "To see if your NetworkMonitor app exists:"
        echo "az ad app list --display-name \"NetworkMonitor\" --output table"
    else
        log "INFO" "No Azure AD applications found in this tenant"
    fi
}

# Parse command line arguments
CLUSTER_URL=""
DATABASE="NetworkMonitoring"
TABLE="NetworkTests"
APP_NAME=""
COMMAND=""

# First pass: collect all options
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-url)
            CLUSTER_URL="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --table)
            TABLE="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        show-kql|create-app|test-connection|generate-config|list-apps)
            COMMAND="$1"
            shift 1
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Now execute the command
case "$COMMAND" in
    show-kql)
        show_kql "$DATABASE" "$TABLE"
        exit 0
        ;;
    create-app)
        if [[ -z "$APP_NAME" ]]; then
            APP_NAME="NetworkMonitorApp"
        fi
        create_app "$APP_NAME"
        exit 0
        ;;
    test-connection)
        test_connection "$CLUSTER_URL"
        exit 0
        ;;
    generate-config)
        generate_config
        exit 0
        ;;
    list-apps)
        list_apps
        exit 0
        ;;
    "")
        # If no command provided, show usage
        show_usage
        exit 0
        ;;
    *)
        log "ERROR" "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac