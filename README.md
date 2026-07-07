# Universal Dev Container

A highly optimized, reusable development container that works across all project types.

## Features

- 🚀 **Fast Startup**: Optimized for <30 second container startup
- 🔧 **Auto-Detection**: Automatically detects project type and installs appropriate tools
- 🔄 **Auto-Updates**: Keep tools and extensions up-to-date automatically
- 🔒 **Security First**: Built-in security scanning with Trivy, hadolint, and git-secrets
- 📦 **Multi-Language**: Supports Node.js, Python, Go, Rust, Ruby, Java, PHP, and more
- ⚙️ **Customizable**: YAML-based configuration for easy customization

## Quick Start

### Use as GitHub Template

1. Click the "Use this template" button above
2. Create a new repository
3. Clone your new repository
4. Open in VS Code and reopen in container

### Install in Existing Project

```bash
# Quick install (replace brianoestberg with your GitHub username)
curl -sSL https://raw.githubusercontent.com/mosgarage/universal-basedevcontainer/main/install.sh | bash

# Or clone manually
git clone https://github.com/mosgarage/universal-basedevcontainer.git
cp -r universal-basedevcontainer/.devcontainer .
rm -rf universal-basedevcontainer
```

### Run Setup Wizard

```bash
./.devcontainer/scripts/setup-wizard.sh
```

## Documentation

- [Windows Setup Guide](WINDOWS-SETUP.md) - Step-by-step Windows installation
- [Configuration Guide](.devcontainer/README.md)
- [Migration Guide](.devcontainer/MIGRATION.md)
- [Sharing Guide](.devcontainer/SHARING.md)

## Supported Languages & Frameworks

The container automatically detects and configures:

- **JavaScript/Node.js**: npm, yarn, pnpm support
- **Python**: virtualenv, pip, poetry, pipenv
- **Go**: go modules, common tools
- **Rust**: cargo, rustup
- **Ruby**: bundler, rbenv/rvm
- **Java**: maven, gradle
- **PHP**: composer
- **Docker**: Docker-in-Docker support

## Quick Reference

```bash
# Install in new project
curl -sSL https://raw.githubusercontent.com/mosgarage/universal-basedevcontainer/main/install.sh | bash

# Run setup wizard
./.devcontainer/scripts/setup-wizard.sh

# Update tools
dev-update

# Run security scan
dev-scan

# Customize
edit .devcontainer/config.yaml
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## Acknowledgments

This dev container installs and configures various third-party tools:

- **VS Code Extensions**: Downloaded from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/)
  - [Claude Code](https://www.anthropic.com/) - AI coding assistant (optional, requires subscription)
  - [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer (optional, requires subscription)
  - Various open-source extensions (GitLens, Live Share, etc.)
- **Base Image**: [Ubuntu 22.04](https://ubuntu.com/) - Open source Linux distribution
- **Development Tools**: Git, Zsh, Vim, and various open-source command-line tools
- **Language Support**: Auto-detection and installation of language-specific tools

All third-party tools retain their original licenses. Users are responsible for complying with the license terms of any tools they choose to use, especially commercial tools that require subscriptions.

## License

MIT License - see [LICENSE](LICENSE) file

This license applies to the dev container configuration, scripts, and documentation created for this project. It does not apply to the third-party tools that the container installs.
