Test
# AzerothCore Rebuild/Update Script

This script is designed to help you **update**, **build**, **run**, and **manage** your **AzerothCore** server — a popular server emulator for **World of Warcraft**. It provides a simple, menu-driven interface to handle the most common server administration tasks.

The script supports both traditional (local) and **Docker-based** AzerothCore setups.

---

## Features

#### Core Functionality
- **Update Source Code**: Pulls the latest changes for your AzerothCore source code from its Git repository.
- **Rebuild Server**: Manages the `cmake` and `make` process to rebuild and reinstall the server.
- **Process Management**: Start, stop, restart, and check the status of `authserver` and `worldserver`. Supports both traditional TMUX sessions and Docker containers.
- **Update Modules**: Recursively runs `git pull` on all directories inside your `modules` folder to keep them up-to-date.

#### Setup & Configuration
- **Configurable Docker Support**: Easily manage Docker-based setups by enabling Docker Mode.
- **Smart Docker Prompt**: On first run, the script can detect a potential Docker setup and will ask if you want to enable Docker Mode automatically.
- **External Configuration File**: All settings are stored in `~/.ACrebuild/ACrebuild.conf` for easy persistence.
- **Flexible Editor Choice**: Respects your `$EDITOR` environment variable for editing configuration files, falling back to `nano`, `vi`, or `ed`.

#### Utilities & Safeguards
- **Dependency Check**: Automatically checks for essential software. If Docker mode is enabled, it will also check for the `docker` command.
- **Backup and Restore**: Create comprehensive backups of your server's databases (world, characters, auth) and configuration files.
- **Backup Dry Run**: See what a backup will do without actually creating any files.
- **Log Viewer**: View the script's own logs, or live-tail the `authserver` and `worldserver` logs.
- **Pre-build Safety Check**: Prompts you to stop running servers before a rebuild to prevent conflicts.

#### Script Maintenance
- **Self-Update**: The script can update itself to the latest version from its own Git repository.

---

## Installation

1.  **Clone the repository** to your local machine:
    ```bash
    git clone https://github.com/Stuntmonkey4u/ACrebuild.git
    cd ACrebuild
    chmod +x ACrebuild.sh
    ```
2.  **Run the script**:
    ```bash
    ./ACrebuild.sh
    ```
    The script will guide you through the initial setup.

---

## How It Works

The script provides an interactive, menu-driven interface for all its features. When you first run the script, it will help you configure the path to your AzerothCore installation.

### Docker Mode

The script can manage both traditional and Docker-based server installations. Docker mode is controlled by a setting in the configuration file (`~/.ACrebuild/ACrebuild.conf`).

**Enabling Docker Mode:**
There are two ways to enable it:

1.  **Automatic Prompt (Recommended):** On first run, if the script detects a `docker-compose.yml` file and the `docker` command, it will ask if you want to enable Docker Mode. If you agree, it will automatically update your configuration file.

2.  **Manual Toggle:** You can enable or disable Docker Mode at any time from the **"Configuration Options"** menu.

When Docker Mode is enabled, the script adapts its functionality to use `docker compose` for all server management, backup, and logging tasks.

---

## For Developers & Contributors

### Code Structure
This script has been refactored for better maintainability. The core logic is now located in the `lib/` directory, with each file responsible for a specific feature:
-   `core.sh`: Core functions and error handling.
-   `config.sh`: Configuration management.
-   `dependencies.sh`: Dependency checking.
-   `update.sh`: Script and module updating.
-   `server.sh`: Server process management.
-   `backup.sh`: Backup and restore functionality.
-   `logging.sh`: Log viewing.
-   `variables.sh`: Core functions, shared variables, and error handling.
-   `ui.sh`: All user interface elements (menus, messages).

The main `ACrebuild.sh` script is now primarily an entry point that sources these libraries and runs the main application loop.

### Contributing
If you have an improvement or idea, please make a pull request!

### Contributors (So Far)
Created by Stuntmonkey4u

---

## License

This script is licensed under the **MIT License**.

---

## Disclaimer

This script is provided as-is, with no warranties or guarantees. Use at your own risk. Make sure to backup your server data before running any script that modifies or updates your environment.
