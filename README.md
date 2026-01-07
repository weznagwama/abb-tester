# Network Testing Scripts

This directory contains network latency monitoring and diagnostic tools.

## Scripts

### `network-monitor.sh` - Main Network Monitor
Continuously monitors latency to a target IP and runs parallel diagnostic tests when thresholds are exceeded.

**Usage:**
```bash
./network-monitor.sh <test_ip> <diagnostic_ip1> [diagnostic_ip2] [diagnostic_ip3] ...
```

**Features:**
- Continuous latency monitoring with configurable threshold (default: 100ms)
- Parallel diagnostic tests (ping + traceroute) when latency exceeds threshold
- Results saved to separate files per IP address
- Colored console output with timestamps
- Graceful shutdown with Ctrl+C
- 15-second cooldown between diagnostic runs

**Examples:**
```bash
# Monitor local gateway, test against major DNS providers
./network-monitor.sh 192.168.1.1 8.8.8.8 1.1.1.1 208.67.222.222

# Monitor Google DNS, test against multiple targets
./network-monitor.sh 8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222
```

### `quick-test.sh` - Quick Test Runner
Simplified wrapper for common testing scenarios.

**Usage:**
```bash
./quick-test.sh <scenario> [test_ip]
```

**Scenarios:**
- `local` - Test local gateway against major DNS providers
- `dns` - Test DNS provider against other DNS services
- `mixed` - Test against mixed services (DNS + CDN)
- `custom` - Custom test with user-specified diagnostic targets

**Examples:**
```bash
./quick-test.sh local 192.168.1.1
./quick-test.sh dns 8.8.8.8
./quick-test.sh mixed 1.1.1.1
```

## Configuration

You can modify these settings in `network-monitor.sh`:
- `LATENCY_THRESHOLD` - Latency threshold in milliseconds (default: 100ms)
- `CHECK_INTERVAL` - Time between latency checks in seconds (default: 5s)
- `PING_COUNT` - Number of pings for diagnostic tests (default: 10)
- `TRACEROUTE_HOPS` - Maximum hops for traceroute (default: 30)
- `OUTPUT_DIR` - Directory for result files (default: ./results)

## Output Files

When diagnostic tests are triggered, results are saved to:
- `results/<ip>_ping_<timestamp>.txt` - Ping test results
- `results/<ip>_traceroute_<timestamp>.txt` - Traceroute results

Timestamp format: `YYYYMMDD_HHMMSS`

## Requirements

- `ping` command
- `traceroute` command
- Bash shell

The script will check for these dependencies on startup.

## Tips

1. **Choose appropriate threshold**: For local networks, 50ms might be better. For internet services, 100-200ms may be more appropriate.

2. **Monitor different targets**: 
   - Local gateway (192.168.x.1) for LAN issues
   - DNS servers (8.8.8.8) for internet connectivity
   - Specific services for application-related issues

3. **Use multiple diagnostic IPs**: Include a mix of local and remote targets to isolate whether issues are local network, ISP, or destination-specific.

4. **Run in background**: Use `nohup ./network-monitor.sh ... &` to run continuously in background.

## Common Use Cases

1. **ISP Connection Monitoring**:
   ```bash
   ./network-monitor.sh 8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9
   ```

2. **Local Network Issues**:
   ```bash
   ./network-monitor.sh 192.168.1.1 8.8.8.8 192.168.1.1
   ```

3. **Gaming/Streaming Latency**:
   ```bash
   ./network-monitor.sh <game-server-ip> 8.8.8.8 1.1.1.1
   ```