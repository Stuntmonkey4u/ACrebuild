# AzerothCore Update Script

This script is designed to help you **update**, **build**, and **run** **AzerothCore** — a popular server emulator for **World of Warcraft**. It simplifies the process of updating an existing AzerothCore server, checking for missing dependencies, rebuilding the server, and running it in a tmux session.

---

## Features:
- **Dependency Check**: Automatically checks for essential software like `git`, `cmake`, `make`, `clang`, `tmux`, etc. If missing, it will prompt you to install them.
- **Source Code Update**: Allows you to update your existing AzerothCore server's source code from the GitHub repository.
- **Rebuilding the Server**: Uses `cmake` and `make` to rebuild and reinstall the updated AzerothCore server.
- **Server Running**: Runs the **authserver** (authentication server) and **worldserver** (game world server) in a **tmux** session for easy monitoring.
- **Flexible Options**: Choose whether to update and rebuild the server, only rebuild it, or run it without rebuilding.

---

## Installation

1. **Clone the repository** to your local machine:

   ```bash
   git clone https://github.com/your-username/AzerothCore-Update-Script.git
   cd AzerothCore-Update-Script
   chmod +x ACrebuild.sh

2. **Run the script**
   ./ACrebuild.sh
