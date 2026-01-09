# Updated Network Monitor - Kusto Data Collector

## What Changed

The `network-monitor-kusto.sh` script has been completely redesigned as a **pure data collection tool** that runs alongside your existing monitoring script.

## New Approach

### Before (Threshold-Based Monitoring)
- Monitored one primary IP for latency thresholds
- Triggered diagnostic tests when thresholds exceeded
- Uploaded aggregated test results to Kusto

### Now (Continuous Data Collection)
- Continuously pings a list of specified IPs
- Uploads **every individual ping result** to Kusto
- No threshold monitoring or diagnostic triggers
- Pure data collection for real-time analysis

## Usage Pattern

**Run Both Scripts Simultaneously:**

```bash
# Terminal 1: File-based monitoring with diagnostics
./network-monitor.sh 192.168.1.1 8.8.8.8 1.1.1.1 208.67.222.222 &

# Terminal 2: Continuous Kusto data collection  
./network-monitor-kusto.sh 8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9
```

## Data Schema

Each ping result uploads these fields to Kusto:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | datetime | When the ping was sent |
| `dstIp` | string | Destination IP pinged |
| `sequenceNumber` | int | Ping sequence number |
| `responseTime` | real | Response time in ms (null if timeout) |
| `ttl` | int | Time to live (null if timeout) |
| `sourceHost` | string | Source hostname |
| `success` | bool | Whether ping succeeded |

## Benefits

✅ **Dual Operation**: Traditional monitoring + real-time data collection  
✅ **Granular Data**: Every ping result, not just summaries  
✅ **Real-time Analysis**: Immediate Kusto availability  
✅ **Flexible Queries**: Rich data for custom analysis  
✅ **No Dependencies**: Scripts operate independently  

## Sample Kusto Analysis

```kql
// Response time trends
NetworkTests
| where success == true
| summarize avg(responseTime) by dstIp, bin(timestamp, 5m)
| render timechart

// Packet loss analysis
NetworkTests
| summarize PacketLoss=(1-avg(todouble(success)))*100 by dstIp, bin(timestamp, 5m)
| render timechart

// Identify problematic periods
NetworkTests
| where not(success) or responseTime > 100
| summarize Problems=count() by dstIp, bin(timestamp, 1h)
| where Problems > 5
```

This approach gives you both traditional file-based monitoring AND comprehensive real-time data analysis!