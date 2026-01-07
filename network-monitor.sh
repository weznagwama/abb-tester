#!/bin/bash

# Network Latency Monitor and Diagnostic Tool
# Usage: ./network-monitor.sh <test_ip> <diagnostic_ip1> [diagnostic_ip2] [diagnostic_ip3] ...
#
# This script continuously monitors latency to a test IP and runs parallel 
# diagnostic tests when latency exceeds the threshold.

# Configuration
LATENCY_THRESHOLD=50  # milliseconds - adjust as needed
CHECK_INTERVAL=2       # seconds between checks
PING_COUNT=50         # number of pings for diagnostic tests
TRACEROUTE_HOPS=30    # max hops for traceroute
OUTPUT_DIR="./results" # directory for result files

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
                          NETWORK LATENCY MONITOR
===============================================================================

NAME
    network-monitor.sh - Continuous network latency monitor with diagnostics

SYNOPSIS
    network-monitor.sh <test_ip> <diagnostic_ip1> [diagnostic_ip2] ...

DESCRIPTION
    Monitors network latency to a target IP and automatically runs parallel
    diagnostic tests when latency exceeds configurable thresholds.

    Features:
    • Continuous latency monitoring with configurable intervals
    • Automatic parallel diagnostics (ping + tracepath) when issues detected
    • Results saved to timestamped files for analysis
    • Smart cooldown prevents excessive testing during outages
    • Colored console output with real-time status updates

REQUIRED ARGUMENTS
    test_ip         IP to monitor continuously (e.g., 8.8.8.8, 192.168.1.1)
    diagnostic_ip   One or more IPs to test when threshold exceeded

CURRENT CONFIGURATION
EOF
    printf "    Latency threshold:    %dms (triggers diagnostics)\n" "$LATENCY_THRESHOLD"
    printf "    Check interval:       %ds (between latency checks)\n" "$CHECK_INTERVAL"  
    printf "    Diagnostic pings:     %d packets per test\n" "$PING_COUNT"
    printf "    Results directory:    %s\n" "$OUTPUT_DIR"
    printf "    Cooldown period:      15s (between diagnostic runs)\n"
    cat << 'EOF'

OPERATION MODES
    Normal Monitoring:
        ✓ Green latency display updates every 5 seconds
        ✓ Single line output shows: [TIME] Latency: XXms
        
    High Latency Detection:  
        ⚠ Yellow warnings when threshold exceeded
        ⚠ Requires 2 consecutive high readings to trigger
        
    Diagnostic Mode:
        🔍 Parallel ping tests to all diagnostic targets
        🔍 Parallel tracepath analysis to map network routes  
        🔍 Results automatically saved to timestamped files
        🔍 Cooldown prevents excessive testing

OUTPUT FILES
    Files saved to results/ directory with format:
    
    <ip-address>_ping_<YYYYMMDD_HHMMSS>.txt
        Complete ping statistics (min/avg/max/loss)
        
    <ip-address>_tracepath_<YYYYMMDD_HHMMSS>.txt  
        Network route trace showing each hop
        
    <YYYYMMDD>.kql
        Daily KQL datatable with extracted metrics for Kusto ingestion
        • Ping results: packet loss percentages
        • Tracepath results: latency to ABB internal network (10.241.5.62)

USAGE EXAMPLES
    ISP Connection Monitoring:
        ./network-monitor.sh 8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9
        
    Local Network Troubleshooting:
        ./network-monitor.sh 192.168.1.1 8.8.8.8 1.1.1.1
        
    Service-Specific Monitoring:
        ./network-monitor.sh your-server.com 8.8.8.8 192.168.1.1

CONTROL
    Start:      ./network-monitor.sh <args>
    Stop:       Press Ctrl+C for graceful shutdown
    Background: nohup ./network-monitor.sh <args> > monitor.log 2>&1 &

STOPPING BACKGROUND PROCESSES
    Find and stop by process name:
        pkill -f "network-monitor.sh"
        
    Find process ID and stop:
        ps aux | grep network-monitor.sh
        kill <PID>
        
    Stop all instances (careful!):
        killall -f network-monitor.sh
        
    Check if running:
        pgrep -f "network-monitor.sh" || echo "Not running"

REQUIREMENTS
    Commands:   ping, tracepath (checked automatically)
    Access:     Network connectivity to target IPs
    Storage:    Write permission for results directory

EXIT CODES
    0    Normal shutdown
    1    Invalid arguments or missing dependencies

TIPS
    • Use stable targets: DNS servers (8.8.8.8) or gateways (192.168.1.1)
    • Mix local/remote diagnostics to isolate problem sources
    • Adjust threshold: 50ms+ for internet, 10ms+ for LAN
    • Check results/ directory for detailed diagnostic data

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

# Function to extract latency from ping output
get_latency() {
    local target="$1"
    local ping_result
    
    # Single ping to get current latency
    ping_result=$(ping -c 1 -W 2 "$target" 2>/dev/null | grep "time=" | sed -n 's/.*time=\([0-9.]*\) ms.*/\1/p')
    
    if [[ -n "$ping_result" ]]; then
        # Convert to integer for comparison
        echo "${ping_result}" | cut -d'.' -f1
    else
        # Return high value if ping failed
        echo "9999"
    fi
}

# Function to append test results to daily KQL file
append_to_kql() {
    local test_type="$1"     # 'ping' or 'tracepath'
    local target_ip="$2"     # destination IP
    local result_file="$3"   # path to result file
    local timestamp="$4"     # timestamp from filename
    
    # Extract date for daily KQL filename (YYYYMMDD format)
    local date_part=$(echo "$timestamp" | cut -d'_' -f1)
    local kql_file="${OUTPUT_DIR}/${date_part}.kql"
    local lock_file="${kql_file}.lock"
    
    # Use file locking to prevent race conditions from parallel processes
    (
        flock -x 200
        
        # Convert timestamp to ISO format for KQL
        local year="${date_part:0:4}"
        local month="${date_part:4:2}"
        local day="${date_part:6:2}"
        local time_part=$(echo "$timestamp" | cut -d'_' -f2)
        local hour="${time_part:0:2}"
        local minute="${time_part:2:2}"
        local second="${time_part:4:2}"
        local iso_timestamp="${year}-${month}-${day}T${hour}:${minute}:${second}.000Z"
        
        local observable_type=""
        local observable_value=""
        
        if [[ "$test_type" == "ping" ]]; then
            # Extract packet loss percentage from ping file
            observable_type="Packet Loss (percent)"
            observable_value=$(grep -o '[0-9]\+% packet loss' "$result_file" | grep -o '[0-9]\+' | head -1)
            
            if [[ -z "$observable_value" ]]; then
                log "WARN" "No packet loss data found in $result_file"
                return 1
            fi
            
        elif [[ "$test_type" == "tracepath" ]]; then
            # Extract latency to 10.241.5.62 from tracepath file
            observable_type="Latency to ABB internal network"
            local latency_line=$(grep "10\.241\.5\.62" "$result_file" | head -1)
            
            if [[ -n "$latency_line" ]]; then
                observable_value=$(echo "$latency_line" | grep -o '[0-9]\+\.[0-9]\+ms' | grep -o '[0-9]\+\.[0-9]\+' | head -1)
            fi
            
            if [[ -z "$observable_value" ]]; then
                # Skip this entry if 10.241.5.62 hop not found
                return 0
            fi
        else
            log "ERROR" "Unknown test type: $test_type"
            return 1
        fi
        
        # Create KQL file with header if it doesn't exist
        if [[ ! -f "$kql_file" ]]; then
            cat > "$kql_file" << 'EOF'
datatable(timestamp: datetime, type: string, dstIp: string, observableType: string, observableValue: string) [
EOF
        fi
        
        # Always remove closing bracket to ensure clean state
        sed -i '/^]$/d' "$kql_file"
        
        # Build the entry line
        local entry_line="    datetime($iso_timestamp), '$test_type', '$target_ip', '$observable_type', '$observable_value'"
        
        # Check if this is the first data entry
        if grep -q "datetime" "$kql_file"; then
            # Not first entry, add comma to last line then add new entry
            sed -i '$ s/$/,/' "$kql_file"
            echo "$entry_line" >> "$kql_file"
        else
            # First entry, just add without comma
            echo "$entry_line" >> "$kql_file"
        fi
        
        # Add closing bracket
        echo "]" >> "$kql_file"
        
        log "SUCCESS" "Appended $test_type result to $kql_file: $observable_type = $observable_value"
        
    ) 200>"$lock_file"
}

# Function to run diagnostic ping test
run_ping_test() {
    local target="$1"
    local output_file="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "INFO" "Starting ping test to $target"
    
    {
        echo "=== PING TEST TO $target ==="
        echo "Timestamp: $timestamp"
        echo "Test duration: ${PING_COUNT} packets"
        echo ""
        
        ping -c "$PING_COUNT" "$target" 2>&1
        
        echo ""
        echo "=== END PING TEST ==="
        echo ""
    } > "$output_file"
    
    log "SUCCESS" "Ping test to $target completed -> $output_file"
    
    # Extract timestamp from filename for KQL processing
    local file_timestamp=$(basename "$output_file" .txt | sed "s/.*_ping_//")
    append_to_kql "ping" "$target" "$output_file" "$file_timestamp"
}

# Function to run diagnostic traceroute test
run_traceroute_test() {
    local target="$1"
    local output_file="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "INFO" "Starting tracepath to $target"
    
    {
        echo "=== TRACEPATH TO $target ==="
        echo "Timestamp: $timestamp"
        echo "Max hops: $TRACEROUTE_HOPS"
        echo ""
        
        # Use tracepath and ensure it completes fully
        tracepath "$target" 2>&1
        
        echo ""
        echo "=== END TRACEPATH ==="
        echo ""
    } > "$output_file"
    
    log "SUCCESS" "Tracepath to $target completed -> $output_file"
    
    # Extract timestamp from filename for KQL processing
    local file_timestamp=$(basename "$output_file" .txt | sed "s/.*_tracepath_//")
    append_to_kql "tracepath" "$target" "$output_file" "$file_timestamp"
}

# Function to run all diagnostic tests in parallel
run_diagnostic_tests() {
    local diagnostic_ips=("$@")
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local pids=()
    
    log "WARN" "Latency threshold exceeded! Running diagnostic tests..."
    
    # Create results directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    # Start all ping tests in parallel
    for ip in "${diagnostic_ips[@]}"; do
        local ping_file="${OUTPUT_DIR}/${ip}_ping_${timestamp}.txt"
        run_ping_test "$ip" "$ping_file" &
        pids+=($!)
    done
    
    # Start all traceroute tests in parallel
    for ip in "${diagnostic_ips[@]}"; do
        local trace_file="${OUTPUT_DIR}/${ip}_tracepath_${timestamp}.txt"
        run_traceroute_test "$ip" "$trace_file" &
        pids+=($!)
    done
    
    # Wait for all background processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    log "SUCCESS" "All diagnostic tests completed. Results saved in $OUTPUT_DIR"
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

# Signal handler for graceful shutdown
cleanup() {
    log "INFO" "Received interrupt signal. Stopping network monitor..."
    # Allow any running diagnostics to complete before exiting
    log "INFO" "Waiting for any running diagnostics to complete..."
    wait 2>/dev/null
    exit 0
}

# Main monitoring loop
main() {
    # Check arguments
    if [ $# -lt 2 ]; then
        show_usage
        exit 1
    fi
    
    local test_ip="$1"
    shift
    local diagnostic_ips=("$@")
    
    # Validate IP addresses
    if ! validate_ip "$test_ip"; then
        log "ERROR" "Invalid test IP address: $test_ip"
        exit 1
    fi
    
    for ip in "${diagnostic_ips[@]}"; do
        if ! validate_ip "$ip"; then
            log "ERROR" "Invalid diagnostic IP address: $ip"
            exit 1
        fi
    done
    
    # Test initial connectivity
    if ! test_connectivity "$test_ip" "${diagnostic_ips[@]}"; then
        log "ERROR" "Initial connectivity test failed"
        exit 1
    fi
    
    # Set up signal handler
    trap cleanup SIGINT SIGTERM
    
    # Display configuration
    log "INFO" "Starting network latency monitor"
    log "INFO" "Test IP: $test_ip"
    log "INFO" "Diagnostic IPs: ${diagnostic_ips[*]}"
    log "INFO" "Latency threshold: ${LATENCY_THRESHOLD}ms"
    log "INFO" "Check interval: ${CHECK_INTERVAL}s"
    echo ""
    
    # Main monitoring loop
    local consecutive_high=0
    local last_diagnostic_time=0
    local diagnostic_cooldown=15  # 15 seconds cooldown between diagnostic runs
    
    while true; do
        local current_latency=$(get_latency "$test_ip")
        local current_time=$(date +%s)
        
        if [[ "$current_latency" != "9999" ]]; then
            if [[ "$current_latency" -gt "$LATENCY_THRESHOLD" ]]; then
                consecutive_high=$((consecutive_high + 1))
                log "WARN" "High latency detected: ${current_latency}ms (threshold: ${LATENCY_THRESHOLD}ms) [${consecutive_high} consecutive]"
                
                # Run diagnostics if we've had high latency and enough time has passed
                local time_since_last=$((current_time - last_diagnostic_time))
                if [[ "$consecutive_high" -ge 2 ]] && [[ "$time_since_last" -gt "$diagnostic_cooldown" ]]; then
                    if [[ "$last_diagnostic_time" -gt 0 ]]; then
                        local seconds_since_last=$time_since_last
                        log "INFO" "Previous diagnostics were ${seconds_since_last} seconds ago - running new diagnostics"
                    fi
                    run_diagnostic_tests "${diagnostic_ips[@]}"
                    last_diagnostic_time=$current_time
                    consecutive_high=0
                elif [[ "$consecutive_high" -ge 2 ]]; then
                    local time_remaining=$((diagnostic_cooldown - time_since_last))
                    log "INFO" "Diagnostic cooldown active - ${time_remaining}s remaining before next diagnostic run"
                fi
            else
                if [[ "$consecutive_high" -gt 0 ]]; then
                    log "SUCCESS" "Latency back to normal: ${current_latency}ms"
                fi
                consecutive_high=0
                echo -ne "\r${GREEN}[$(date '+%H:%M:%S')] Latency: ${current_latency}ms${NC}    "
            fi
        else
            consecutive_high=$((consecutive_high + 1))
            log "ERROR" "Ping failed to $test_ip [${consecutive_high} consecutive failures]"
            
            # Run diagnostics on ping failures too
            local time_since_last=$((current_time - last_diagnostic_time))
            if [[ "$consecutive_high" -ge 2 ]] && [[ "$time_since_last" -gt "$diagnostic_cooldown" ]]; then
                if [[ "$last_diagnostic_time" -gt 0 ]]; then
                    local seconds_since_last=$time_since_last
                    log "INFO" "Previous diagnostics were ${seconds_since_last} seconds ago - running new diagnostics"
                fi
                run_diagnostic_tests "${diagnostic_ips[@]}"
                last_diagnostic_time=$current_time
                consecutive_high=0
            elif [[ "$consecutive_high" -ge 2 ]]; then
                local time_remaining=$((diagnostic_cooldown - time_since_last))
                log "INFO" "Ping failure diagnostic cooldown active - ${time_remaining}s remaining"
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Check if required tools are installed
check_dependencies() {
    local missing=()
    
    if ! command -v ping >/dev/null 2>&1; then
        missing+=("ping")
    fi
    
    if ! command -v tracepath >/dev/null 2>&1; then
        missing+=("tracepath")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing required tools: ${missing[*]}"
        log "ERROR" "Please install missing tools and try again"
        exit 1
    fi
}

# Check dependencies before starting
check_dependencies

# Run main function with all arguments
main "$@"