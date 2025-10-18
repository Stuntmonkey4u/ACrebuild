# AzerothCore Rebuild & Management Script

Welcome! This script is a powerful, menu-driven utility designed to help you **update**, **build**, **run**, and **manage** your **AzerothCore** server—a popular server emulator for **World of Warcraft**. It streamlines the most common server administration tasks and is built to be both user-friendly for beginners and robust for experienced administrators.

The script intelligently adapts to your setup, supporting both traditional (local) and **Docker-based** AzerothCore installations.

---

## Key Features

*   **Simple Setup**: A first-time setup wizard guides you through the initial configuration.
*   **Smart Docker Support**: Automatically detects and adapts to Docker-based setups.
*   **Update & Rebuild**: Easily update your server's source code and rebuild it with the latest changes.
*   **Server Management**: Start, stop, and restart your `authserver` and `worldserver` with ease.
*   **Module Management**: Install and update server modules from a Git URL.
*   **Backup & Restore**: Create and restore backups of your databases and configuration files.
*   **Log Viewer**: View and tail your server logs in real-time.
*   **Self-Update**: The script can update itself to the latest version.

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
    The first time you run it, the **Setup Wizard** will launch and guide you through configuration.

---

## Advanced Information

### How It Works

The script provides an interactive, menu-driven interface for all its features. All settings are saved to `~/.ACrebuild/ACrebuild.conf`. You can either edit this file directly or use the "Configuration Options" menu within the script to change your settings at any time.

#### Docker Mode

The script's real power comes from its ability to seamlessly manage both traditional and Docker-based server installations.

**Enabling Docker Mode:**
There are two ways to enable it:

1.  **Setup Wizard (Recommended):** During the first-time setup, if the script detects a `docker-compose.yml` file, it will ask if you want to enable Docker Mode.
2.  **Manual Toggle:** You can enable or disable Docker Mode at any time from the **"Configuration Options"** menu. Toggling this option will also intelligently update the default database user (`root` for Docker, `acore` for standard) if you haven't set a custom one.

When Docker Mode is enabled, the script adapts its functionality to use `docker compose` for all server management, build, backup, and logging tasks.

### For Developers & Contributors

#### Code Structure
This script has been refactored for better maintainability. The core logic is now located in the `lib/` directory, with each file responsible for a specific feature:
-   `core.sh`: Core functions and error handling.
-   `config.sh`: Configuration loading and saving.
-   `dependencies.sh`: Dependency checking.
-   `update.sh`: Script, source, and module updating logic.
-   `server.sh`: Server process management (start/stop/build).
-   `backup.sh`: Backup and restore functionality.
-   `database.sh`: Database console access.
-   `logging.sh`: Log viewing functions.
-   `wizard.sh`: The first-time setup wizard.
-   `variables.sh`: Global variables and default values.
-   `ui.sh`: All user interface elements (menus, messages).

The main `ACrebuild.sh` script is now primarily an entry point that sources these libraries and runs the main application loop.

#### Contributing
If you have an improvement or idea, please make a pull request!

### Contributors (So Far)
Created by Stuntmonkey4u

---

### License

This script is licensed under the **MIT License**.

---

### Disclaimer

This script is provided as-is, with no warranties or guarantees. Use at your own risk. Make sure to backup your server data before running any script that modifies or updates your environment.