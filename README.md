# AzerothCore Rebuild/Update Script

This script is designed to help you **update**, **build**, and **run** **AzerothCore** — a popular server emulator for **World of Warcraft**. It simplifies the process of updating an existing AzerothCore server, checking for missing dependencies, rebuilding the server, and running it in a tmux session.

---

## Features:
- **Dependency Check**: Automatically checks for essential software like `git`, `cmake`, `make`, `clang`, `tmux`, etc. If missing, it will prompt you to install them.
- **Source Code Update**: Allows you to update your existing AzerothCore server's source code from the GitHub repository.
- **Rebuilding the Server**: Uses `cmake` and `make` to rebuild and reinstall the updated AzerothCore server.
- **Server Running**: Runs the **authserver** (authentication server) and **worldserver** (game world server) in a **tmux** session for easy monitoring.
- **Module Update**: Helps you to update all or individual mods.
- **Flexible Options**: Choose whether to update and rebuild the server, only rebuild it, or run it without rebuilding.

---

## Installation

1. **Clone the repository** to your local machine:

   ```bash
   git clone https://github.com/Stuntmonkey4u/ACrebuild.git
   cd ACrebuild
   chmod +x ACrebuild.sh ACmod.sh

2. **Run the script**

   ```bash
   ./ACrebuild.sh

---

## How It Works

When you run the script, it presents you with a simple menu of options to choose from:

1. **Rebuild and Run the Server:** Updates the AzerothCore source code (optional), rebuilds the server, and runs both the authserver and worldserver in a tmux session.

2. **Only Rebuild the Server:** Rebuilds AzerothCore without running the server after completion.

3. **Run the Server Without Rebuilding:** Runs the server in a tmux session without rebuilding it (useful if you don't need to update the server).

4. **Update Modules:** Updates the modules that were downloaded from Github. If module a does not work, import the module's SQL files to your database.

5. **Exit:** Exits the script without making any changes.

---

## License

This script is licensed under the **MIT License**. Feel free to modify and use it as needed.

---

## Disclaimer

This script is provided as-is, with no warranties or guarantees. Use at your own risk. Make sure to backup your server data before running any script that modifies or updates your environment.

---

## Credits (So Far...)

Created by Stuntmonkey4u

