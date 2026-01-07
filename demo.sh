#!/bin/bash

# Test script to demonstrate the network monitor functionality
# This script temporarily modifies the latency threshold to trigger diagnostics

echo "Network Monitor Test Demo"
echo "========================"
echo ""
echo "This demo will:"
echo "1. Set an extremely low latency threshold (1ms) to guarantee triggering diagnostics"
echo "2. Reduce cooldown period to allow quicker diagnostic runs"
echo "3. Monitor 8.8.8.8 for 25 seconds"
echo "4. Run diagnostics against 1.1.1.1 and 208.67.222.222 when triggered"
echo ""
echo "Press Ctrl+C to stop early, or wait 25 seconds for auto-stop"
echo ""

# Create a temporary version with demo settings
cp network-monitor.sh network-monitor-demo.sh

# Modify settings for demo purposes - very low threshold and short cooldown
sed -i 's/LATENCY_THRESHOLD=100/LATENCY_THRESHOLD=1/' network-monitor-demo.sh
sed -i 's/diagnostic_cooldown=15/diagnostic_cooldown=10/' network-monitor-demo.sh

echo "Starting demo with 1ms threshold (this will definitely trigger diagnostics)..."
echo "Diagnostic tests will run every 10 seconds when triggered."
echo ""

# Run the demo for longer to ensure diagnostics complete
timeout 25s ./network-monitor-demo.sh 8.8.8.8 1.1.1.1 208.67.222.222

echo ""
echo "Demo completed! Check the ./results directory for diagnostic output files."
echo ""

# Clean up
rm -f network-monitor-demo.sh

# Show any result files created
if [ -d "./results" ] && [ "$(ls -A ./results 2>/dev/null)" ]; then
    echo "Generated diagnostic files:"
    ls -la ./results/
else
    echo "No diagnostic files were generated (latency may have been consistently low)."
fi