# SR7 Proxmox Scripts

A collection of scripts to automate specific tasks in Proxmox VE, customized for SR7.

## Overview

This repository contains various scripts to help manage Proxmox VE, including:

- **Container (LXC) Scripts**: Automated creation and setup of LXC containers for various services.
- **VM Scripts**: Helpers for creating Virtual Machines.
- **Tools**: Maintenance and utility scripts for Proxmox VE hosts.

## Repository Structure

- `ct/` - Scripts for creating specific LXC containers (e.g., Alpine, Node.js, databases).
- `vm/` - Scripts for creating Virtual Machines.
- `tools/` - General utility scripts (e.g., post-install setup, cleaning, updates).
- `turnkey/` - Turnkey Linux templates/scripts.

## Usage

To use these scripts, typically you would run them directly on your Proxmox VE host shell.

**Example:**
```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/Saarthaksr7/N8N-Proxmox_auto/main/ct/alpine.sh)"
```

*Note: Ensure you review scripts before running them on your system.*

## Disclaimer

This project is a customized fork/collection. "SR7" scripts are provided as-is without warranty. Use at your own risk.

## License

See the LICENSE file for details (if applicable).
