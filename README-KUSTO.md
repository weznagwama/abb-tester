# Network Monitor with Kusto Integration

This enhanced version of the network monitoring tool uploads results directly to Azure Data Explorer (Kusto) instead of creating local files.

## Quick Start

### 1. Setup Azure Data Explorer

First, set up your Kusto cluster and create the required table:

```bash
# Generate KQL commands for manual setup
./kusto-setup.sh show-kql

# Or create Azure AD app automatically
./kusto-setup.sh create-app --app-name "NetworkMonitorApp"

# Generate environment configuration template
./kusto-setup.sh generate-config > kusto-config.env
```

### 2. Configure Connection Settings

Create and configure the Kusto connection file:

```bash
# Generate configuration file from template
./kusto-setup.sh generate-config

# Edit the configuration file with your Azure settings
# File: kusto-config.conf
```

Edit `kusto-config.conf` with your actual values:
```bash
# Your Azure Data Explorer cluster endpoint
KUSTO_CLUSTER_URL=https://your-cluster.eastus.kusto.windows.net

# Database and table names
KUSTO_DATABASE=NetworkMonitoring
KUSTO_TABLE=NetworkTests

# Azure AD Application Credentials
KUSTO_CLIENT_ID=your-client-id-from-step1
KUSTO_CLIENT_SECRET=your-client-secret-from-step1
KUSTO_TENANT_ID=your-tenant-id
```

### 3. Run Network Monitoring

```bash
# Monitor Google DNS, test against multiple targets
./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9

# Monitor local gateway against major DNS providers
./network-monitor-kusto.sh 192.168.1.1 8.8.8.8 1.1.1.1
```

## Key Differences from Original

| Feature | Original Script | Kusto Script |
|---------|----------------|--------------|
| **Data Storage** | Local files in `results/` | Direct upload to Azure Data Explorer |
| **Real-time Analysis** | Manual processing with `extract-to-kusto.sh` | Immediate availability in Kusto |
| **Dependencies** | `ping`, `tracepath` | `ping`, `tracepath`, `curl`, `jq` |
| **Configuration** | File paths | Configuration file (`kusto-config.conf`) |
| **Scalability** | Limited by disk space | Cloud-scale with Kusto |

## Data Schema

Data is uploaded to Kusto with the following schema:

| Column | Type | Description |
|--------|------|-------------|
| `timestamp` | datetime | When the test was performed |
| `type` | string | Test type ('ping' or 'tracepath') |
| `dstIp` | string | Destination IP address tested |
| `observableType` | string | Type of measurement |
| `observableValue` | string | Measured value (latency, packet loss) |
| `sourceHost` | string | Hostname where test was run |
| `testResult` | string | Raw test output (truncated if needed) |

## Sample Kusto Queries

After data is uploaded, you can analyze it with KQL:

```kql
// View recent ping results
NetworkTests
| where type == "ping"
| where timestamp > ago(1h)
| project timestamp, dstIp, observableValue, sourceHost

// Average packet loss per destination over time
NetworkTests
| where type == "ping"
| where observableType == "Packet Loss (percent)"
| summarize avg(todouble(observableValue)) by dstIp, bin(timestamp, 5m)
| render timechart

// Internal network latency trends
NetworkTests
| where type == "tracepath"
| where observableType == "Latency to ABB internal network"
| summarize avg(todouble(observableValue)) by bin(timestamp, 5m)
| render timechart

// Identify problem periods
NetworkTests
| where type == "ping"
| where todouble(observableValue) > 10  // High packet loss
| summarize ProblemCount=count() by dstIp, bin(timestamp, 1h)
| where ProblemCount > 3
```

## Setup Scripts

### kusto-setup.sh

Helper script for Azure setup:

```bash
# Show KQL table creation commands
./kusto-setup.sh show-kql

# Create Azure AD application with proper permissions
./kusto-setup.sh create-app --app-name "MyNetworkMonitor"

# Test your configuration
./kusto-setup.sh test-connection --cluster-url "https://mycluster.eastus.kusto.windows.net"

# Generate configuration template
./kusto-setup.sh generate-config
```

## Troubleshooting

### Common Issues

1. **Configuration File Missing**
   ```bash
   ./kusto-setup.sh generate-config
   # Edit kusto-config.conf with your settings
   ```

2. **Authentication Failed**
   ```bash
   ./kusto-setup.sh test-connection
   ```

3. **Missing Dependencies**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install curl jq

   # RHEL/CentOS  
   sudo yum install curl jq
   ```

3. **Permission Denied**
   - Ensure your Azure AD app has "Database Ingestor" role in Kusto
   - Check that KUSTO_CLIENT_ID has proper permissions

4. **Table Not Found**
   ```bash
   ./kusto-setup.sh show-kql
   # Copy and run the output in Azure Data Explorer web UI
   ```

### Debug Mode

Enable verbose logging by setting:
```bash
export KUSTO_DEBUG=1
```

## Migration from Original Script

To migrate from the file-based version:

1. **Keep existing data**: Your existing files in `results/` are preserved
2. **Process historical data**: Use the original `extract-to-kusto.sh` to import old data
3. **Switch monitoring**: Start using `network-monitor-kusto.sh` for new monitoring
4. **Verify setup**: Use `kusto-setup.sh test-connection` to validate configuration

## Performance Considerations

- **Batch Uploads**: Currently uploads individual test results immediately
- **Rate Limits**: Kusto has ingestion rate limits; monitor for throttling
- **Network Usage**: Each upload requires internet connectivity
- **Fallback**: Consider hybrid approach with local backup during connectivity issues

## Security Notes

- Store Azure AD credentials securely (use Azure Key Vault in production)
- Rotate client secrets regularly
- Use managed identities when running on Azure VMs
- Restrict Kusto access to minimum required permissions

## Architecture

```
[Network Monitor] → [Azure AD Auth] → [Kusto Ingestion API] → [Azure Data Explorer]
                                                                        ↓
                                                              [KQL Queries & Dashboards]
```

The script authenticates with Azure AD using client credentials, then uploads network test results directly to Kusto using the REST ingestion API.