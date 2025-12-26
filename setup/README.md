# Development Environment Setup

This folder contains scripts to set up prerequisites for the AWS Serverless SaaS Workshop.

## Quick Start

1. **Install prerequisites** (first-time setup):
   ```bash
   ./install.sh
   ```

2. **Verify installation**:
   ```bash
   ./check-versions.sh
   ```

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Installs all required tools (AWS CLI, SAM CLI, Node.js, CDK, etc.) |
| `check-versions.sh` | Validates that all prerequisites meet minimum version requirements |
| `increase-disk-size.sh` | (EC2 only) Expands EBS volume to 50 GiB |

## Requirements

The workshop requires:
- Python ≥ 3.8
- AWS CLI v2
- SAM CLI ≥ 1.53.0
- Node.js ≥ 18.x (required for CDK 2.40+)
- AWS CDK ≥ 2.40.0
- git-remote-codecommit

## Supported Platforms

- Ubuntu/Debian (apt)
- Amazon Linux/RHEL (yum)
- GitHub Codespaces
- Any Linux with manual dependency installation
