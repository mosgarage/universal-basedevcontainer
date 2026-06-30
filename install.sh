#!/bin/bash
# Quick installer for Universal Basedevcontainer
set -euo pipefail

echo "Installing Universal Basedevcontainer..."

# Check if .devcontainer already exists
if [[ -d ".devcontainer" ]]; then
    echo "Error: .devcontainer directory already exists!"
    read -p "Backup and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv .devcontainer .devcontainer.backup.$(date +%s)
    else
        exit 1
    fi
fi

# Download from main branch (contains latest fixes)
REPO="${GITHUB_USER:-mosgarage}/universal-basedevcontainer"
DOWNLOAD_URL="https://github.com/$REPO/archive/main.tar.gz"
echo "Downloading from main branch..."

# Download and extract
echo "Downloading..."
curl -L "$DOWNLOAD_URL" -o devcontainer.tar.gz
tar xzf devcontainer.tar.gz --strip=1
rm devcontainer.tar.gz

# Run setup wizard
if [[ -x ".devcontainer/scripts/setup-wizard.sh" ]]; then
    echo ""
    echo "Running setup wizard..."
    ./.devcontainer/scripts/setup-wizard.sh
fi

echo ""
echo "✓ Universal Basedevcontainer installed successfully!"
echo "  Open this folder in VS Code and reopen in container"