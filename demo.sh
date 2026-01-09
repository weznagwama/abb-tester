#!/bin/bash

# Demo script to show the difference between file-based and Kusto-based monitoring

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}               NETWORK MONITORING: FILE vs KUSTO COMPARISON${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

echo -e "${GREEN}ORIGINAL SCRIPT (network-monitor.sh):${NC}"
echo "  • Monitors network latency to target IP"
echo "  • Runs diagnostic tests when threshold exceeded"
echo "  • Saves results to files in results/ directory"
echo "  • Manual processing with extract-to-kusto.sh"
echo "  • Dependencies: ping, tracepath"
echo ""

echo -e "${YELLOW}NEW KUSTO SCRIPT (network-monitor-kusto.sh):${NC}"
echo "  • Continuously pings specified IP addresses"
echo "  • Uploads every individual ping result to Kusto"
echo "  • No file output or threshold monitoring"
echo "  • Pure data collection for real-time analysis"
echo "  • Designed to run alongside the original script"
echo "  • Dependencies: ping, curl, jq"
echo ""

echo -e "${BLUE}USAGE COMPARISON:${NC}"
echo ""
echo -e "${GREEN}Original:${NC}"
echo "  ./network-monitor.sh 8.8.8.8 1.1.1.1 208.67.222.222"
echo "  # Results saved to: results/1.1.1.1_ping_YYYYMMDD_HHMMSS.txt"
echo "  ./extract-to-kusto.sh  # Manual processing"
echo ""

echo -e "${YELLOW}New Kusto Version:${NC}"
echo "  # First, create configuration file:"
echo "  ./kusto-setup.sh generate-config"
echo "  # Edit kusto-config.conf with your Azure settings"
echo ""
echo "  # Then run continuous ping collection:"
echo "  ./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 208.67.222.222"
echo "  # Every ping result uploaded immediately to Kusto"
echo ""
echo "  # Run both scripts simultaneously:"
echo "  ./network-monitor.sh 192.168.1.1 8.8.8.8 1.1.1.1 &    # File-based monitoring"
echo "  ./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 9.9.9.9    # Kusto data collection"
echo ""

echo -e "${BLUE}SETUP HELPERS:${NC}"
echo ""
echo "  ./kusto-setup.sh generate-config              # Create configuration file"
echo "  ./kusto-setup.sh show-kql                    # Show table creation commands"
echo "  ./kusto-setup.sh create-app --app-name \"MyApp\"  # Create Azure AD application"  
echo "  ./kusto-setup.sh test-connection             # Verify configuration"
echo ""

echo -e "${GREEN}SAMPLE KUSTO QUERIES:${NC}"
echo ""
cat << 'EOF'
// View recent ping results with response times
NetworkTests
| where timestamp > ago(1h)
| project timestamp, dstIp, responseTime, success

// Average response time trends  
NetworkTests
| where success == true
| summarize avg(responseTime) by dstIp, bin(timestamp, 5m)
| render timechart

// Success rate analysis
NetworkTests
| summarize SuccessRate=avg(todouble(success))*100 by dstIp, bin(timestamp, 5m)
| render timechart
EOF

echo ""
echo -e "${BLUE}FILES CREATED:${NC}"
echo "  network-monitor-kusto.sh     - Main monitoring script with Kusto upload"
echo "  kusto-setup.sh              - Azure setup helper"
echo "  kusto-config.conf.template  - Configuration file template"
echo "  README-KUSTO.md             - Detailed documentation"
echo "  demo.sh                     - This demonstration script"
echo ""

echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "1. Set up Azure Data Explorer cluster"
echo "2. Run: ./kusto-setup.sh generate-config"
echo "3. Edit kusto-config.conf with your Azure settings"
echo "4. Run: ./kusto-setup.sh show-kql (copy output to Azure Data Explorer web UI)"
echo "5. Run: ./kusto-setup.sh create-app --app-name \"NetworkMonitor\""
echo "6. Update kusto-config.conf with credentials from step 5"
echo "7. Test: ./kusto-setup.sh test-connection"
echo "8. Start monitoring: ./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 9.9.9.9"
echo ""

echo -e "${GREEN}The new script is now a pure data collector that continuously pings${NC}"
echo -e "${GREEN}specified IPs and uploads every result to Kusto for real-time analysis!${NC}"
echo ""
echo -e "${BLUE}You can run both scripts simultaneously:${NC}"
echo -e "${BLUE}• File-based monitoring with diagnostics (original script)${NC}"
echo -e "${BLUE}• Continuous ping data collection to Kusto (new script)${NC}"