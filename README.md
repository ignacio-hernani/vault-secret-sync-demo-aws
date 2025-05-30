# HashiCorp Vault Enterprise Secret Sync AWS Demo

This comprehensive guide demonstrates the Secret Sync functionlatiy of HashiCorp Vault Enterprise with AWS. The documentation provides detailed explanations for users with limited Kubernetes experience.

## Overview

## Architecture

## Prerequisites

## Core Concepts Demonstrated

## Implementation Guide

### Step 1: Vault Enterprise Setup

Your Vault Enterprise instance should be running from the provided `vault.sh` script. Verify the installation:

```bash
# Check if Vault is running
vault status
```

If not running, execute:
```bash
./vault.sh
```

**Technical Note**: Vault runs in Docker using "dev mode" with an unsealed state and root token. This configuration is suitable for demonstration purposes only and should never be used in production environments.