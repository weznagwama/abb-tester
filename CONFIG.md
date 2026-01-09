# Configuration File Setup Guide

The network monitoring scripts now use a configuration file (`kusto-config.conf`) instead of environment variables for storing Azure Data Explorer connection details.

## Quick Setup

1. **Generate configuration file**:
   ```bash
   ./kusto-setup.sh generate-config
   ```

2. **Edit the configuration**:
   ```bash
   # Edit kusto-config.conf with your actual Azure settings
   nano kusto-config.conf
   ```

3. **Test the configuration**:
   ```bash
   ./kusto-setup.sh test-connection
   ```

## Configuration File Format

The `kusto-config.conf` file uses simple shell variable syntax:

```bash
# Azure Data Explorer cluster endpoint
KUSTO_CLUSTER_URL=https://your-cluster.eastus.kusto.windows.net

# Database and table names
KUSTO_DATABASE=NetworkMonitoring
KUSTO_TABLE=NetworkTests

# Azure AD Application Credentials
KUSTO_CLIENT_ID=12345678-1234-1234-1234-123456789abc
KUSTO_CLIENT_SECRET=your-secret-here
KUSTO_TENANT_ID=87654321-4321-4321-4321-cba987654321

# Optional debug flag
KUSTO_DEBUG=false
```

## Security Notes

- The configuration file is automatically added to `.gitignore`
- Never commit actual credentials to version control
- Store the template (`kusto-config.conf.template`) in version control
- Each user/environment should have their own `kusto-config.conf`

## Benefits Over Environment Variables

✅ **File-based configuration**:
- Easier to manage multiple environments
- No risk of exposing secrets in shell history
- Clear documentation of required settings
- Automatic gitignore protection

✅ **Centralized settings**:
- Single file for all Kusto-related configuration
- Consistent across all scripts in the project
- Easy to backup and restore settings

✅ **Better security**:
- File permissions can be restricted (e.g., `chmod 600 kusto-config.conf`)
- No accidental exposure through environment variable dumps
- Clear separation between code and configuration

## Migration from Environment Variables

If you were previously using environment variables, convert them to the configuration file:

```bash
# Old approach (environment variables)
export KUSTO_CLUSTER_URL="https://mycluster.eastus.kusto.windows.net"
export KUSTO_CLIENT_ID="..."
# etc.

# New approach (configuration file)
./kusto-setup.sh generate-config
# Edit kusto-config.conf with the same values
```

The scripts will automatically detect and use the configuration file - no other changes needed!