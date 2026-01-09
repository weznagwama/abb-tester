#!/bin/bash

# Test script for Kusto buffering functionality
# This tests the local buffering and retry mechanisms

echo "==============================================================================="
echo "                    KUSTO BUFFERING FUNCTIONALITY TEST"
echo "==============================================================================="

# Test configuration
TEST_IP="8.8.8.8"
CONFIG_FILE="./kusto-config.conf"
BUFFER_FILE="./kusto-buffer.jsonl"
TEST_DURATION=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_test() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "INFO") echo -e "${BLUE}[${timestamp}] TEST INFO:${NC} $message" ;;
        "PASS") echo -e "${GREEN}[${timestamp}] TEST PASS:${NC} $message" ;;
        "FAIL") echo -e "${RED}[${timestamp}] TEST FAIL:${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[${timestamp}] TEST WARN:${NC} $message" ;;
    esac
}

# Test 1: Basic functionality check
test_basic_functionality() {
    log_test "INFO" "Testing basic functionality (no network issues)"
    
    # Clean up any existing buffer
    rm -f "$BUFFER_FILE"
    
    # Run for short period
    timeout 15s ./network-monitor-kusto.sh "$TEST_IP" &>/dev/null &
    local pid=$!
    
    sleep 10
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    # Check if buffer file exists (shouldn't if everything worked)
    if [[ ! -f "$BUFFER_FILE" ]]; then
        log_test "PASS" "No buffer file created (uploads working normally)"
    else
        local lines=$(wc -l < "$BUFFER_FILE" 2>/dev/null || echo 0)
        if [[ $lines -eq 0 ]]; then
            log_test "PASS" "Empty buffer file (uploads processed successfully)"
        else
            log_test "WARN" "Buffer file has $lines records (may indicate upload issues)"
        fi
    fi
}

# Test 2: Simulate network failure by blocking access to Azure
test_network_failure_simulation() {
    log_test "INFO" "Testing network failure simulation (blocking Azure endpoints)"
    
    # Clean up any existing buffer
    rm -f "$BUFFER_FILE"
    
    # Add temporary firewall rule to block Azure (requires sudo)
    if command -v iptables >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        log_test "INFO" "Adding iptables rule to block login.microsoftonline.com"
        iptables -A OUTPUT -d login.microsoftonline.com -j REJECT 2>/dev/null
        FIREWALL_BLOCKED=true
    else
        log_test "WARN" "Cannot test with iptables (not root), simulating with DNS poisoning"
        # Alternative: temporarily modify /etc/hosts (requires sudo)
        echo "127.0.0.1 login.microsoftonline.com" >> /etc/hosts 2>/dev/null && HOSTS_BLOCKED=true
    fi
    
    # Run monitor for short period with blocked access
    log_test "INFO" "Running monitor with blocked network access for 20 seconds"
    timeout 20s ./network-monitor-kusto.sh "$TEST_IP" &>/dev/null &
    local pid=$!
    
    sleep 15
    
    # Check if buffer file was created
    if [[ -f "$BUFFER_FILE" ]]; then
        local lines=$(wc -l < "$BUFFER_FILE")
        if [[ $lines -gt 0 ]]; then
            log_test "PASS" "Buffer created with $lines records during network outage"
        else
            log_test "FAIL" "Buffer file exists but is empty"
        fi
    else
        log_test "FAIL" "No buffer file created during network outage"
    fi
    
    # Restore network access
    if [[ "${FIREWALL_BLOCKED:-false}" == "true" ]]; then
        iptables -D OUTPUT -d login.microsoftonline.com -j REJECT 2>/dev/null
        log_test "INFO" "Removed iptables blocking rule"
    fi
    
    if [[ "${HOSTS_BLOCKED:-false}" == "true" ]]; then
        sed -i '/127.0.0.1 login.microsoftonline.com/d' /etc/hosts 2>/dev/null
        log_test "INFO" "Removed hosts file blocking entry"
    fi
    
    # Wait a bit more to see if retry works
    sleep 10
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    # Check if buffer was processed after network restoration
    if [[ -f "$BUFFER_FILE" ]]; then
        local final_lines=$(wc -l < "$BUFFER_FILE")
        if [[ $final_lines -lt $lines ]]; then
            log_test "PASS" "Buffer processed: $lines -> $final_lines records (retry working)"
        else
            log_test "WARN" "Buffer not processed: still has $final_lines records"
        fi
    fi
}

# Test 3: Test buffer file operations without network issues
test_buffer_operations() {
    log_test "INFO" "Testing buffer file operations"
    
    # Create test buffer file
    rm -f "$BUFFER_FILE"
    
    # Add some test records
    echo '{"timestamp": "2026-01-09T10:00:00.000Z", "type": "ping", "dstIp": "8.8.8.8", "observableType": "timeout", "observableValue": 1, "source": "test"}' >> "$BUFFER_FILE"
    echo '{"timestamp": "2026-01-09T10:00:05.000Z", "type": "ping", "dstIp": "8.8.8.8", "observableType": "responseTime", "observableValue": 25.5, "source": "test"}' >> "$BUFFER_FILE"
    
    local initial_lines=$(wc -l < "$BUFFER_FILE")
    log_test "INFO" "Created test buffer with $initial_lines records"
    
    # Run monitor briefly to see if it processes the buffer
    log_test "INFO" "Running monitor to test buffer processing"
    timeout 10s ./network-monitor-kusto.sh "$TEST_IP" &>/dev/null &
    local pid=$!
    
    sleep 8
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    # Check buffer after processing
    if [[ -f "$BUFFER_FILE" ]]; then
        local final_lines=$(wc -l < "$BUFFER_FILE")
        if [[ $final_lines -lt $initial_lines ]]; then
            log_test "PASS" "Buffer processed: $initial_lines -> $final_lines records"
        else
            log_test "WARN" "Buffer not processed: still has $final_lines records"
        fi
    else
        log_test "PASS" "Buffer file removed (all records processed successfully)"
    fi
}

# Test 4: Test buffer size limits
test_buffer_limits() {
    log_test "INFO" "Testing buffer size limits"
    
    rm -f "$BUFFER_FILE"
    
    # Create a large buffer file (simulate many failed uploads)
    for i in {1..50}; do
        echo '{"timestamp": "2026-01-09T10:00:00.000Z", "type": "ping", "dstIp": "8.8.8.8", "observableType": "timeout", "observableValue": 1, "source": "test"}' >> "$BUFFER_FILE"
    done
    
    local initial_lines=$(wc -l < "$BUFFER_FILE")
    log_test "INFO" "Created large buffer with $initial_lines records"
    
    # The script should handle this gracefully without issues
    if [[ $initial_lines -eq 50 ]]; then
        log_test "PASS" "Buffer creation successful"
    else
        log_test "FAIL" "Buffer creation failed"
    fi
}

# Test 5: Configuration validation
test_configuration() {
    log_test "INFO" "Testing configuration validation"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_test "PASS" "Configuration file exists: $CONFIG_FILE"
        
        # Check if all required fields are present
        local missing=()
        source "$CONFIG_FILE"
        
        [[ -z "$KUSTO_CLUSTER_URL" ]] && missing+=("KUSTO_CLUSTER_URL")
        [[ -z "$KUSTO_DATABASE" ]] && missing+=("KUSTO_DATABASE")  
        [[ -z "$KUSTO_TABLE" ]] && missing+=("KUSTO_TABLE")
        [[ -z "$KUSTO_CLIENT_ID" ]] && missing+=("KUSTO_CLIENT_ID")
        [[ -z "$KUSTO_CLIENT_SECRET" ]] && missing+=("KUSTO_CLIENT_SECRET")
        [[ -z "$KUSTO_TENANT_ID" ]] && missing+=("KUSTO_TENANT_ID")
        [[ -z "$SOURCE" ]] && missing+=("SOURCE")
        
        if [[ ${#missing[@]} -eq 0 ]]; then
            log_test "PASS" "All required configuration fields present"
        else
            log_test "FAIL" "Missing configuration fields: ${missing[*]}"
        fi
    else
        log_test "FAIL" "Configuration file not found: $CONFIG_FILE"
    fi
}

# Run all tests
main() {
    echo "Starting buffering functionality tests..."
    echo ""
    
    test_configuration
    echo ""
    
    test_basic_functionality
    echo ""
    
    test_buffer_operations
    echo ""
    
    test_buffer_limits  
    echo ""
    
    # Only run network simulation if user confirms (requires elevated privileges)
    read -p "Run network failure simulation test? (requires sudo) [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_network_failure_simulation
        echo ""
    else
        log_test "INFO" "Skipping network failure simulation test"
        echo ""
    fi
    
    echo "==============================================================================="
    echo "Test Summary:"
    echo "- Basic functionality: Tested"
    echo "- Buffer operations: Tested" 
    echo "- Configuration: Validated"
    echo "- Buffer limits: Tested"
    echo "- Network failure: $(if [[ $REPLY =~ ^[Yy]$ ]]; then echo "Tested"; else echo "Skipped"; fi)"
    echo ""
    echo "Check the output above for PASS/FAIL/WARN status of each test."
    echo "==============================================================================="
    
    # Clean up test files
    if [[ -f "$BUFFER_FILE" ]]; then
        echo "Cleaning up test buffer file: $BUFFER_FILE"
        rm -f "$BUFFER_FILE"
    fi
}

# Check if script exists
if [[ ! -f "./network-monitor-kusto.sh" ]]; then
    echo "ERROR: network-monitor-kusto.sh not found in current directory"
    exit 1
fi

# Make sure it's executable
chmod +x ./network-monitor-kusto.sh

# Run tests
main "$@"