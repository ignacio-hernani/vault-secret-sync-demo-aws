# Troubleshooting Guide

This guide helps you resolve common issues with the Vault Secret Sync on AWS demo.

## Quick Diagnostics 🩺

First, run the verification script to identify issues:

```bash
./verify-setup.sh
```

## Common Issues and Solutions 🛠️

### 1. Vault Issues

#### "Vault is not accessible"

**Symptoms:**
- `vault status` fails
- Error: "connection refused" or "no such host"

**Solutions:**
```bash
# Check if Vault container is running
docker ps | grep vault-enterprise

# If not running, start Vault
./vault.sh

# Wait for initialization and test
sleep 10
vault status

# Check Vault logs if still failing
docker logs vault-enterprise
```

### Check All Component Status

### Collect Logs

## Complete Reset

If all troubleshooting steps fail, completely reset the demonstration environment:

```bash
# Clean up everything
./cleanup-demo.sh

# Wait for cleanup completion
sleep 5

# Start fresh
./setup-demo.sh
```

## Support Information

### System Requirements

---

This troubleshooting guide provides comprehensive solutions for common demonstration environment issues. The demonstration is designed for educational purposes and experimentation. 