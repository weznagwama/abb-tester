#!/bin/bash

# Quick Network Test Runner
# Simplified wrapper for common network testing scenarios

# Common IP addresses for testing
GOOGLE_DNS="8.8.8.8"
CLOUDFLARE_DNS="1.1.1.1"
OPENDNS="208.67.222.222"
QUAD9_DNS="9.9.9.9"

show_usage() {
    echo "Quick Network Test Runner"
    echo "Usage: $0 <scenario> [test_ip]"
    echo ""
    echo "Scenarios:"
    echo "  local     - Test local gateway (requires test_ip parameter)"
    echo "  dns       - Test against major DNS providers"
    echo "  mixed     - Test mixed services (DNS + CDN)"
    echo "  custom    - Custom test (requires test_ip parameter)"
    echo ""
    echo "Examples:"
    echo "  $0 local 192.168.1.1"
    echo "  $0 dns 8.8.8.8"
    echo "  $0 mixed 1.1.1.1"
    echo "  $0 custom 203.50.2.71"
}

case "$1" in
    "local")
        if [ -z "$2" ]; then
            echo "Error: test_ip required for local scenario"
            show_usage
            exit 1
        fi
        echo "Starting local network test (monitoring: $2)"
        echo "Diagnostic targets: Google DNS, Cloudflare DNS, OpenDNS"
        ./network-monitor.sh "$2" "$GOOGLE_DNS" "$CLOUDFLARE_DNS" "$OPENDNS"
        ;;
    "dns")
        if [ -z "$2" ]; then
            echo "Error: test_ip required for DNS scenario"
            show_usage
            exit 1
        fi
        echo "Starting DNS provider test (monitoring: $2)"
        echo "Diagnostic targets: Major DNS providers"
        ./network-monitor.sh "$2" "$GOOGLE_DNS" "$CLOUDFLARE_DNS" "$OPENDNS" "$QUAD9_DNS"
        ;;
    "mixed")
        if [ -z "$2" ]; then
            echo "Error: test_ip required for mixed scenario"
            show_usage
            exit 1
        fi
        echo "Starting mixed service test (monitoring: $2)"
        echo "Diagnostic targets: DNS providers + other services"
        ./network-monitor.sh "$2" "$GOOGLE_DNS" "$CLOUDFLARE_DNS" "8.8.4.4" "1.0.0.1"
        ;;
    "custom")
        if [ -z "$2" ]; then
            echo "Error: test_ip required for custom scenario"
            show_usage
            exit 1
        fi
        echo "Starting custom test (monitoring: $2)"
        echo "Enter diagnostic IP addresses (space-separated): "
        read -r diagnostic_ips
        if [ -z "$diagnostic_ips" ]; then
            echo "Using default diagnostic targets"
            ./network-monitor.sh "$2" "$GOOGLE_DNS" "$CLOUDFLARE_DNS"
        else
            ./network-monitor.sh "$2" $diagnostic_ips
        fi
        ;;
    *)
        show_usage
        exit 1
        ;;
esac