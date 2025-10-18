# AzerothCore Rebuild & Management Script

This script is a powerful, menu-driven utility designed to help you **update**, **build**, **run**, and **manage** your **AzerothCore** server — a popular server emulator for **World of Warcraft**. It streamlines the most common server administration tasks and is built to be both user-friendly for beginners and robust for experienced administrators.

The script intelligently adapts to your setup, supporting both traditional (local) and **Docker-based** AzerothCore installations.

---

## Key Features

#### Smart Setup & Configuration
- **First-Time Setup Wizard**: On the very first run, a setup wizard will guide you through the essential settings (like your installation path and Docker mode), making initial configuration a breeze.
- **Mode-Aware Logic**: The script automatically detects your setup type (Docker vs. standard) and adjusts its functionality accordingly.
  - **Dependency Checks**: Only checks for relevant dependencies (`git` and `docker` for Docker mode, `cmake`, `clang`, etc., for standard mode).
  - **Prompts & Error Handling**: Hides irrelevant questions (like CPU core count in Docker) and provides mode-specific, helpful advice on build failures.
- **External Configuration**: All settings are stored in `~/.ACrebuild/ACrebuild.conf` for easy persistence and manual editing.
- **Configuration Validation**: A dedicated menu option to validate your settings, checking for valid paths and verifying the database connection to catch errors proactively.

#### Core Functionality
- **Update Source Code**: Pulls the latest changes for your AzerothCore source from its Git repository.
- **Rebuild Server**: Manages the `cmake`/`make` process for standard builds and `docker compose build` for Docker builds.
- **Process Management**: Start, stop, restart, and check the status of `authserver` and `worldserver`. The "Restart" command intelligently starts stopped containers instead of failing.
- **Module Management**:
  - **Interactive Module Installation**: Install new modules easily by simply providing a Git URL. The script handles cloning and SQL installation.
  - **Update Modules**: Recursively runs `git pull` on all modules in your `modules` folder.
  - **Automated SQL Installation**: After updating a module, the script automatically detects new `.sql` files and offers to import them into the correct database, saving a tedious manual step.

#### Utilities & Safeguards
- **Robust Backup & Restore**: Create and restore comprehensive backups of your databases (`world`, `characters`, `auth`) and configuration files.
  - **Smart Container Handling**: If your database container is stopped, the backup, restore, and database console functions will offer to start it temporarily for the operation and shut it down afterward.
- **Log Viewer**:
  - **Standard View**: View any log file using `less`.
  - **Live View**: Tail server logs in real-time (`tail -f` or `docker compose logs -f`) for easy debugging.
- **Direct Database Console**: A main menu option to get a direct MySQL command-line shell, whether you're using Docker or a local database.
- **Pre-build Safety Check**: Prompts you to stop running servers before a rebuild to prevent conflicts.

#### Script Maintenance
- **Self-Update**: The script can update itself to the latest version from its own Git repository, with a prominent notification in the main menu when an update is available.

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

## How It Works

The script provides an interactive, menu-driven interface for all its features. All settings are saved to `~/.ACrebuild/ACrebuild.conf`. You can either edit this file directly or use the "Configuration Options" menu within the script to change your settings at any time.

### Docker Mode

The script's real power comes from its ability to seamlessly manage both traditional and Docker-based server installations.

**Enabling Docker Mode:**
There are two ways to enable it:

1.  **Setup Wizard (Recommended):** During the first-time setup, if the script detects a `docker-compose.yml` file, it will ask if you want to enable Docker Mode.
2.  **Manual Toggle:** You can enable or disable Docker Mode at any time from the **"Configuration Options"** menu. Toggling this option will also intelligently update the default database user (`root` for Docker, `acore` for standard) if you haven't set a custom one.

When Docker Mode is enabled, the script adapts its functionality to use `docker compose` for all server management, build, backup, and logging tasks.

---

## For Developers & Contributors

### Code Structure
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
