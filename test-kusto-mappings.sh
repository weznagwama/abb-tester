#!/bin/bash

# Test script to check Kusto mappings and connectivity
CONFIG_FILE="$(dirname "$0")/kusto-config.conf"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "Testing Kusto connection and mappings..."
echo "Cluster: $KUSTO_CLUSTER_URL"
echo "Database: $KUSTO_DATABASE" 
echo "Table: $KUSTO_TABLE"
echo ""

# Get access token
get_azure_token() {
    local token_response
    token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/${KUSTO_TENANT_ID}/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${KUSTO_CLIENT_ID}" \
        -d "client_secret=${KUSTO_CLIENT_SECRET}" \
        -d "scope=https://kusto.kusto.windows.net/.default" \
        -d "grant_type=client_credentials")
    
    echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

echo "Getting Azure AD token..."
TOKEN=$(get_azure_token)

if [[ -z "$TOKEN" ]]; then
    echo "Failed to get Azure AD token"
    exit 1
fi

echo "Token obtained successfully"
echo ""

# Query to show all mappings for the table
QUERY=".show table $KUSTO_TABLE ingestion json mappings"

echo "Querying existing mappings with: $QUERY"
echo ""

# Execute query
RESPONSE=$(curl -s -X POST "${KUSTO_CLUSTER_URL}/v1/rest/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"db\":\"$KUSTO_DATABASE\",\"csl\":\"$QUERY\"}")

echo "Response from Kusto:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
echo ""

# Also test if table exists
QUERY2=".show tables | where TableName == \"$KUSTO_TABLE\""
echo "Checking if table exists with: $QUERY2"

RESPONSE2=$(curl -s -X POST "${KUSTO_CLUSTER_URL}/v1/rest/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"db\":\"$KUSTO_DATABASE\",\"csl\":\"$QUERY2\"}")

echo "Table check response:"
echo "$RESPONSE2" | jq '.' 2>/dev/null || echo "$RESPONSE2"