#!/bin/bash

# Define colors for better readability in the terminal
CYAN='\033[0;36m'        # Cyan for spinner and interactive text
GREEN='\033[38;5;82m'       # Green for success messages
YELLOW='\033[1;33m'      # Yellow for warnings and prompts
RED='\033[38;5;196m'         # Red for errors and important alerts
BLUE='\033[38;5;117m'        # Blue for headers and important sections
WHITE='\033[1;37m'       # White for general text
BOLD='\033[1m'           # Bold for emphasis
NC='\033[0m'             # No Color (reset)

# SERVER_CONFIG_FILES is an array, will be kept as is for now or managed differently if needed.
SERVER_CONFIG_FILES=("authserver.conf" "worldserver.conf") # Array of config files to back up

# Process Management Variables
TMUX_SESSION_NAME="azeroth"
AUTHSERVER_PANE_TITLE="Authserver" # Used in current script, good to formalize
WORLDSERVER_PANE_TITLE="Worldserver" # Used in current script, good to formalize
WORLDSERVER_CONSOLE_COMMAND_STOP="server shutdown 1" # 300 seconds = 5 minutes for graceful shutdown

# Configuration File Variables
CONFIG_DIR="$HOME/.ACrebuild"
CONFIG_FILE="$CONFIG_DIR/ACrebuild.conf"

# Default values for configuration
DEFAULT_AZEROTHCORE_DIR="$HOME/azerothcore"
DEFAULT_BACKUP_DIR="$HOME/ac_backups"
DEFAULT_DB_USER="acore"
DEFAULT_DB_PASS=""
DEFAULT_AUTH_DB_NAME="acore_auth"
DEFAULT_CHAR_DB_NAME="acore_characters"
DEFAULT_WORLD_DB_NAME="acore_world"
DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX="env/dist/etc"
DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX="env/dist/logs"
DEFAULT_AUTH_SERVER_LOG_FILENAME="authserver.log"
DEFAULT_WORLD_SERVER_LOG_FILENAME="worldserver.log"
DEFAULT_SCRIPT_LOG_DIR="$HOME/.ACrebuild/logs"
DEFAULT_SCRIPT_LOG_FILENAME="ACrebuild.log"
DEFAULT_POST_SHUTDOWN_DELAY_SECONDS=10
DEFAULT_CORES_FOR_BUILD=""

# Runtime variables - These will be loaded from config or set to default by load_config()
AZEROTHCORE_DIR=""
BUILD_DIR=""
SCRIPT_DIR_PATH=""
SCRIPT_IS_GIT_REPO=false
AUTH_SERVER_EXEC=""
WORLD_SERVER_EXEC=""
BACKUP_DIR=""
DB_USER=""
DB_PASS=""
AUTH_DB_NAME=""
CHAR_DB_NAME=""
WORLD_DB_NAME=""
SERVER_CONFIG_DIR_PATH=""
SERVER_LOG_DIR_PATH=""
AUTH_SERVER_LOG_FILENAME="" # Renamed from AUTH_SERVER_LOG_FILE to avoid confusion with full path for clarity
WORLD_SERVER_LOG_FILENAME=""# Renamed from WORLD_SERVER_LOG_FILE to avoid confusion with full path for clarity
# SCRIPT_LOG_DIR_CONF and SCRIPT_LOG_FILENAME_CONF were part of an earlier idea and are no longer used.
# SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME are loaded directly, and print_message handles pre-config state.
SCRIPT_LOG_FILE="" # Actual path to script log file, derived by load_config from SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME
POST_SHUTDOWN_DELAY_SECONDS=""
CORES="" # Runtime variable, takes its value from CORES_FOR_BUILD in config.

# Function to check the Git status of the script's directory
check_script_git_status() {
    print_message $BLUE "Checking script's Git repository status..." true
    # Determine the absolute directory path of the script
    # Updated method for reliability, especially with symlinks or sourcing
    CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
    SCRIPT_DIR_PATH="$CURRENT_SCRIPT_DIR"

    print_message $CYAN "Script is running from: $SCRIPT_DIR_PATH" false

    if [ -d "$SCRIPT_DIR_PATH/.git" ]; then
        print_message $GREEN "  .git directory found." false
        # Confirm it's part of a Git working tree
        if git -C "$SCRIPT_DIR_PATH" rev-parse --is-inside-work-tree &>/dev/null; then
            print_message $GREEN "  Script directory is part of a Git working tree." false
            # Check if 'origin' remote is configured
            if git -C "$SCRIPT_DIR_PATH" remote get-url origin &>/dev/null; then
                print_message $GREEN "  'origin' remote is configured for the script's repository." false
                SCRIPT_IS_GIT_REPO=true
                print_message $GREEN "Script is confirmed to be in a Git repository with an 'origin' remote." true
            else
                SCRIPT_IS_GIT_REPO=false
                print_message $YELLOW "  'origin' remote is NOT configured for the script's repository." false
                print_message $YELLOW "Script is in a Git repository, but 'origin' remote is missing." true
            fi
        else
            SCRIPT_IS_GIT_REPO=false
            print_message $YELLOW "  Script directory is NOT part of a Git working tree (rev-parse check failed)." false
        fi
    else
        SCRIPT_IS_GIT_REPO=false
        print_message $YELLOW "  .git directory NOT found in script directory." false
        print_message $YELLOW "Script is not in a Git repository or .git is not accessible." true
    fi
}

# Function to check for script updates from Git repository
check_for_script_updates() {
    # This function should only run if the script is in a git repo with 'origin' remote
    if [ "$SCRIPT_IS_GIT_REPO" != true ]; then
        return
    fi

    # Check for network connectivity to github.com first
    # -c 1: send 1 ICMP ECHO_REQUEST packet
    # -W 1: wait 1 second for a response (timeout)
    # &>/dev/null: suppress all output (stdout and stderr)
    if ! ping -c 1 -W 1 github.com &>/dev/null; then
        # Silently exit if github.com is not reachable
        return
    fi

    # Silently fetch updates from 'origin' remote to update local remote-tracking branches
    # -q: quiet mode, suppresses most output
    # Errors during fetch are intentionally ignored for a silent background check.
    # If fetch fails, subsequent comparisons will likely not indicate an update, which is acceptable.
    git -C "$SCRIPT_DIR_PATH" fetch origin -q

    # Get the commit hash of the local HEAD
    # 2>/dev/null: suppress stderr if the command fails (e.g., not a git repo, though SCRIPT_IS_GIT_REPO should prevent this)
    LOCAL_HEAD=$(git -C "$SCRIPT_DIR_PATH" rev-parse HEAD 2>/dev/null)
    # If LOCAL_HEAD could not be determined, something is wrong; silently exit.
    if [ -z "$LOCAL_HEAD" ]; then
        return
    fi

    # Determine the default branch of the 'origin' remote (e.g., main, master)
    # This requires SCRIPT_DIR_PATH to be set, which is done in check_script_git_status
    DEFAULT_BRANCH=$(git -C "$SCRIPT_DIR_PATH" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')

    # If the default branch could not be determined (e.g., remote misconfiguration, or grep/awk failed),
    # then we cannot compare. Silently exit.
    if [ -z "$DEFAULT_BRANCH" ]; then
        return
    fi

    # Get the commit hash of the remote-tracking branch (e.g., refs/remotes/origin/main)
    REMOTE_HEAD=$(git -C "$SCRIPT_DIR_PATH" rev-parse "origin/$DEFAULT_BRANCH" 2>/dev/null)
    # If REMOTE_HEAD could not be determined (e.g., default branch deleted from remote, or never fetched),
    # silently exit.
    if [ -z "$REMOTE_HEAD" ]; then
        return
    fi

    # Compare the local HEAD commit with the remote HEAD commit.
    # If they are different, it means there's an update available.
    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
        # Use the existing print_message function to display the notification.
        # $YELLOW is a predefined color variable in the script.
        # The third argument 'false' means the message text will not be bold.
        echo ""
        print_message "$YELLOW" "An update is available to ACrebuild" false
    fi
}


# Function to print the message with a specific color and optional bold text
# Note: SCRIPT_LOG_DIR and SCRIPT_LOG_FILE are used here.
# These will use the global DEFAULT values until load_config() is called.
# load_config() will then update them based on config values.
print_message() {
    local color=$1
    local message=$2
    local bold=$3
    local log_message # For storing the uncolored message

    # Determine which log directory/file to use (pre-config vs post-config)
    local current_log_dir="${SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}"
    local current_log_file="${SCRIPT_LOG_FILE:-$current_log_dir/$DEFAULT_SCRIPT_LOG_FILENAME}"

    # Create SCRIPT_LOG_DIR if it doesn't exist
    if [ ! -d "$current_log_dir" ]; then
        mkdir -p "$current_log_dir" || echo "WARNING: Could not create script log directory $current_log_dir. Logging to file will be disabled for this message."
    fi

    # Prepare message for logging (remove color codes)
    # Using echo -e to interpret escape sequences, then sed to remove them.
    log_message=$(echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g')

    # Append timestamped message to SCRIPT_LOG_FILE
    if [ -d "$current_log_dir" ]; then # Check again in case creation failed
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_message" >> "$current_log_file"
    fi

    # Print to console with color
    if [ "$bold" = true ]; then
        echo -e "${color}${BOLD}${message}${NC}"
    else
        echo -e "${color}${message}${NC}"
    fi
}

# Function to load configuration from file or set defaults
load_config() {
    print_message $BLUE "Loading configuration..." true

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR" || { print_message $RED "FATAL: Could not create config directory $CONFIG_DIR. Exiting." true; exit 1; }

    if [ ! -f "$CONFIG_FILE" ]; then
        print_message $YELLOW "Configuration file not found. Creating default config at $CONFIG_FILE." false
        create_default_config
        # if create_default_config failed to make the file, we might be in trouble.
        if [ ! -f "$CONFIG_FILE" ]; then
            print_message $RED "FATAL: Default config file could not be created. Please check permissions. Exiting." true
            exit 1
        fi
    fi

    # Source the configuration file
    # Disable unbound variable errors temporarily if config is incomplete
    set +u
    . "$CONFIG_FILE"
    set -u # Re-enable unbound variable errors

    # --- Assign variables from config or use defaults if missing ---
    AZEROTHCORE_DIR="${AZEROTHCORE_DIR:-$DEFAULT_AZEROTHCORE_DIR}"
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    DB_USER="${DB_USER:-$DEFAULT_DB_USER}"
    # DB_PASS is intentionally not defaulted here if empty in config, to force prompt.
    # However, if the var is COMPLETELY ABSENT from config, DEFAULT_DB_PASS ("") should be used.
    # The `:-` operator handles if the var is unset or null. If it's set to empty string in config, it remains empty.
    DB_PASS="${DB_PASS:-$DEFAULT_DB_PASS}"
    AUTH_DB_NAME="${AUTH_DB_NAME:-$DEFAULT_AUTH_DB_NAME}"
    CHAR_DB_NAME="${CHAR_DB_NAME:-$DEFAULT_CHAR_DB_NAME}"
    WORLD_DB_NAME="${WORLD_DB_NAME:-$DEFAULT_WORLD_DB_NAME}"

    local server_config_suffix="${SERVER_CONFIG_DIR_PATH_SUFFIX:-$DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX}"
    local server_log_suffix="${SERVER_LOG_DIR_PATH_SUFFIX:-$DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX}"

    AUTH_SERVER_LOG_FILENAME="${AUTH_SERVER_LOG_FILENAME:-$DEFAULT_AUTH_SERVER_LOG_FILENAME}"
    WORLD_SERVER_LOG_FILENAME="${WORLD_SERVER_LOG_FILENAME:-$DEFAULT_WORLD_SERVER_LOG_FILENAME}"

    # SCRIPT_LOG_DIR_CONF and SCRIPT_LOG_FILENAME_CONF are read from config file
    # Then we set the main SCRIPT_LOG_DIR and SCRIPT_LOG_FILE used by print_message
    SCRIPT_LOG_DIR="${SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}" # This uses the SCRIPT_LOG_DIR var from config file
    SCRIPT_LOG_FILENAME="${SCRIPT_LOG_FILENAME:-$DEFAULT_SCRIPT_LOG_FILENAME}" # Uses SCRIPT_LOG_FILENAME from config

    POST_SHUTDOWN_DELAY_SECONDS="${POST_SHUTDOWN_DELAY_SECONDS:-$DEFAULT_POST_SHUTDOWN_DELAY_SECONDS}"
    CORES="${CORES_FOR_BUILD:-$DEFAULT_CORES_FOR_BUILD}" # CORES is the runtime var, CORES_FOR_BUILD is from config

    # --- Update dynamic paths based on loaded/defaulted AZEROTHCORE_DIR ---
    BUILD_DIR="$AZEROTHCORE_DIR/build"
    SERVER_CONFIG_DIR_PATH="$AZEROTHCORE_DIR/$server_config_suffix"
    SERVER_LOG_DIR_PATH="$AZEROTHCORE_DIR/$server_log_suffix"
    AUTH_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/authserver"
    WORLD_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/worldserver"

    # Update final SCRIPT_LOG_FILE path
    # This ensures print_message uses the configured path from now on.
    SCRIPT_LOG_FILE="$SCRIPT_LOG_DIR/$SCRIPT_LOG_FILENAME"

    # Ensure the (potentially new) SCRIPT_LOG_DIR for print_message exists
    if [ ! -d "$SCRIPT_LOG_DIR" ]; then
        mkdir -p "$SCRIPT_LOG_DIR" || echo "WARNING: Could not create configured script log directory $SCRIPT_LOG_DIR."
    fi

    print_message $GREEN "Configuration loaded successfully." true
}

# Function to save a configuration value to the config file
save_config_value() {
    local key_to_save="$1"
    local value_to_save="$2"
    local temp_config_file="$CONFIG_DIR/ACrebuild.conf.tmp"

    # Check if config file exists, if not, something is wrong (should have been created by load_config)
    if [ ! -f "$CONFIG_FILE" ]; then
        print_message $RED "Error: Config file $CONFIG_FILE not found. Cannot save value." true
        create_default_config # Attempt to recreate it
        if [ ! -f "$CONFIG_FILE" ]; then
             print_message $RED "Failed to recreate config file. Save aborted." true
             return 1
        fi
    fi

    # Escape common special characters in the value for sed: \, &, /, newline
    # For basic paths and simple strings, this might be overkill or needs more robust handling
    # For now, let's assume values are relatively simple or paths.
    # A more robust solution might use awk or a different tool for complex values.
    local temp_escaped_value="${value_to_save//\\/\\\\}" # Escape backslashes: \ -> \\
    local escaped_value="${temp_escaped_value//\"/\\\"}"  # Escape double quotes: " -> \"

    # Check if the key exists
    if grep -q "^${key_to_save}=" "$CONFIG_FILE"; then
        # Key exists, update it
        # Using a temporary file for safer sed operation
        sed "s|^${key_to_save}=.*|${key_to_save}=\"${escaped_value}\"|" "$CONFIG_FILE" > "$temp_config_file" && mv "$temp_config_file" "$CONFIG_FILE"
        if [ $? -eq 0 ]; then
            print_message $GREEN "Configuration value '$key_to_save' updated in $CONFIG_FILE." false
        else
            print_message $RED "Error updating '$key_to_save' in $CONFIG_FILE." true
            rm -f "$temp_config_file"
            return 1
        fi
    else
        # Key does not exist, append it
        # Ensure this matches the config file format, e.g., KEY="VALUE"
        echo "${key_to_save}=\"${escaped_value}\"" >> "$CONFIG_FILE"
        if [ $? -eq 0 ]; then
            print_message $GREEN "Configuration value '$key_to_save' added to $CONFIG_FILE." false
        else
            print_message $RED "Error adding '$key_to_save' to $CONFIG_FILE." true
            return 1
        fi
    fi
    return 0
}

# Function to create the default configuration file
create_default_config() {
    print_message $CYAN "Creating default configuration file at $CONFIG_FILE..." true

    # Ensure CONFIG_DIR exists
    mkdir -p "$CONFIG_DIR" || { print_message $RED "FATAL: Could not create config directory $CONFIG_DIR. Exiting." true; exit 1; }

    cat > "$CONFIG_FILE" << EOF
# ACrebuild Configuration File
# This file stores settings for the AzerothCore Rebuild script.
# Lines starting with # are comments.

# Path to your AzerothCore installation directory
AZEROTHCORE_DIR="$DEFAULT_AZEROTHCORE_DIR"

# Path to your backup directory
BACKUP_DIR="$DEFAULT_BACKUP_DIR"

# Database credentials
DB_USER="$DEFAULT_DB_USER"
DB_PASS="$DEFAULT_DB_PASS" # Leave empty to be prompted (recommended for security)
AUTH_DB_NAME="$DEFAULT_AUTH_DB_NAME"
CHAR_DB_NAME="$DEFAULT_CHAR_DB_NAME"
WORLD_DB_NAME="$DEFAULT_WORLD_DB_NAME"

# Suffix for the server configuration directory (relative to AZEROTHCORE_DIR)
# Example: env/dist/etc
SERVER_CONFIG_DIR_PATH_SUFFIX="$DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX"

# Suffix for the server log directory (relative to AZEROTHCORE_DIR)
# Example: env/dist/logs
SERVER_LOG_DIR_PATH_SUFFIX="$DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX"

# Filename for the auth server log (located in SERVER_LOG_DIR_PATH)
AUTH_SERVER_LOG_FILENAME="$DEFAULT_AUTH_SERVER_LOG_FILENAME"

# Filename for the world server log (located in SERVER_LOG_DIR_PATH)
WORLD_SERVER_LOG_FILENAME="$DEFAULT_WORLD_SERVER_LOG_FILENAME"

# Directory for the ACrebuild script's own log files
SCRIPT_LOG_DIR="$DEFAULT_SCRIPT_LOG_DIR"

# Filename for the ACrebuild script's log file
SCRIPT_LOG_FILENAME="$DEFAULT_SCRIPT_LOG_FILENAME"

# Number of CPU cores to use for building AzerothCore
# Leave empty or set to a number (e.g., 4). If empty, script will ask or use all available.
CORES_FOR_BUILD="$DEFAULT_CORES_FOR_BUILD"

# Number of seconds to wait after port 8085 is free before force-closing server panes.
# This allows extra time for database writes or other cleanup tasks.
POST_SHUTDOWN_DELAY_SECONDS="$DEFAULT_POST_SHUTDOWN_DELAY_SECONDS"

EOF
    if [ $? -eq 0 ]; then
        print_message $GREEN "Default configuration file created successfully." true
    else
        print_message $RED "Error creating default configuration file. Please check permissions for $CONFIG_DIR." true
        # Not exiting here, load_config will handle the error if file is unusable
    fi
}

# Function to check if essential dependencies are installed
check_dependencies() {
    echo""
    print_message $BLUE "Checking for essential dependencies..." true
    MISSING_DEPENDENCIES=() # Initialize the array here

    # List of dependencies to check
    DEPENDENCIES=("git" "cmake" "make" "clang" "clang++" "tmux" "nc") # Added nc for netcat
    for DEP in "${DEPENDENCIES[@]}"; do
        command -v "$DEP" &>/dev/null
        if [ $? -ne 0 ]; then
            print_message $RED "$DEP is not installed. Please install it before continuing." false
            MISSING_DEPENDENCIES+=("$DEP")
        fi
    done

    # If there are missing dependencies, prompt the user to install them
    if [ ${#MISSING_DEPENDENCIES[@]} -gt 0 ]; then
        ask_to_install_dependencies
    else
        print_message $GREEN "All required dependencies are installed.\n" true
    fi
}

# Function to ask if the user wants to install missing dependencies
ask_to_install_dependencies() {
    echo ""
    print_message $YELLOW "The following dependencies are required but missing: ${MISSING_DEPENDENCIES[*]}" true
    print_message $YELLOW "Would you like to try and install them now? (y/n)" true
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        install_dependencies
        echo ""
        print_message $GREEN "Dependencies installation attempt finished." true
        print_message $BLUE "Please check the output above for any errors. Returning to main menu..." true
        sleep 3
        main_menu
    else
        echo ""
        print_message $RED "--------------------------------------------------------------------" true
        print_message $RED "Critical: Cannot proceed without the required dependencies. Exiting..." true
        print_message $RED "--------------------------------------------------------------------" true
        exit 1
    fi
}

# Function to install the missing dependencies
install_dependencies() {
    print_message $BLUE "Attempting to install missing dependencies..." true
    for DEP in "${MISSING_DEPENDENCIES[@]}"; do
        print_message $YELLOW "Installing $DEP..." false
        sudo apt install -y "$DEP" || { print_message $RED "Error: Failed to install $DEP. Please install it manually and restart the script. Exiting." true; exit 1; }
        print_message $GREEN "$DEP installed successfully." false
    done
}

# Function to ask the user where their AzerothCore is installed
# This function is called AFTER load_config() has run at least once.
ask_for_core_installation_path() {
    local current_ac_dir="$AZEROTHCORE_DIR" # From loaded config
    echo ""
    print_message $YELLOW "AzerothCore Installation Path Setup" true
    print_message $CYAN "The current AzerothCore directory is set to: $current_ac_dir" false
    print_message $YELLOW "Press ENTER to keep the current path, or enter a new path:" false
    read -r user_input_path

    if [ -n "$user_input_path" ] && [ "$user_input_path" != "$current_ac_dir" ]; then
        print_message $YELLOW "You entered a new path: $user_input_path" false
        # Basic validation: check if directory exists (optional, could be a new setup)
        if [ ! -d "$user_input_path" ]; then
            print_message $YELLOW "Warning: The specified directory does not currently exist." false
            print_message $YELLOW "Make sure it's correct if you proceed to save." false
        fi

        print_message $YELLOW "Save this new path to the configuration file? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]$ ]]; then
            save_config_value "AZEROTHCORE_DIR" "$user_input_path"
            if [ $? -eq 0 ]; then
                print_message $GREEN "AzerothCore directory saved to configuration." true
                # Reload config to update all related paths and variables
                print_message $CYAN "Reloading configuration to apply changes..." false
                load_config
            else
                print_message $RED "Failed to save AzerothCore directory. Using runtime value: $user_input_path" true
                # Manually update runtime AZEROTHCORE_DIR and related paths for current session if save failed
                AZEROTHCORE_DIR="$user_input_path"
                BUILD_DIR="$AZEROTHCORE_DIR/build"
                SERVER_CONFIG_DIR_PATH="$AZEROTHCORE_DIR/$DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX"
                SERVER_LOG_DIR_PATH="$AZEROTHCORE_DIR/$DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX"
                AUTH_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/authserver"
                WORLD_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
            fi
        else
            print_message $CYAN "New path will be used for this session only." false
            # Manually update runtime AZEROTHCORE_DIR and related paths for current session
            AZEROTHCORE_DIR="$user_input_path"
            BUILD_DIR="$AZEROTHCORE_DIR/build"
            SERVER_CONFIG_DIR_PATH="$AZEROTHCORE_DIR/$DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX"
            SERVER_LOG_DIR_PATH="$AZEROTHCORE_DIR/$DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX"
            AUTH_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/authserver"
            WORLD_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
        fi
    elif [ -z "$user_input_path" ]; then
        print_message $GREEN "Keeping current path: $current_ac_dir" false
    else
        print_message $GREEN "Path unchanged: $current_ac_dir" false
    fi

    # Display final active paths (these are now set by load_config if save was successful, or manually if not)
    print_message $BLUE "Effective paths for this session:" true
    print_message $GREEN " AzerothCore Directory: $AZEROTHCORE_DIR" false
    print_message $GREEN " Build Directory:       $BUILD_DIR" false
    print_message $GREEN " Auth Server Exec:    $AUTH_SERVER_EXEC" false
    print_message $GREEN " World Server Exec:   $WORLD_SERVER_EXEC" false
    print_message $GREEN " Server Config Dir:   $SERVER_CONFIG_DIR_PATH" false
    print_message $GREEN " Server Log Dir Path: $SERVER_LOG_DIR_PATH" false
    echo ""
}

# Function to download updates to AzerothCore
update_source_code() {
    print_message $YELLOW "Updating your AzerothCore source code..." true
    cd "$AZEROTHCORE_DIR" || handle_error "Failed to change directory to $AZEROTHCORE_DIR"
    
    # Fetch updates from the remote repository (only update tracking branches)
    git fetch origin || handle_error "Git fetch failed"
    
    # Automatically detect the default branch (e.g., 'main' or 'master')
    DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    
    # Check if there are any new commits in the remote repository
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$DEFAULT_BRANCH")  # Use the detected default branch

    if [ "$LOCAL" != "$REMOTE" ]; then
        print_message $YELLOW "New commits found. Pulling updates..." true
        # Pull the latest changes (merge them into the local branch)
        git pull origin "$DEFAULT_BRANCH" || handle_error "Git pull failed"
    else
        print_message $GREEN "No new commits. Local repository is up to date." true
    fi
    
    print_message $GREEN "AzerothCore source code updated successfully.\n" true
}

# Function to display a welcome message
welcome_message() {
    clear
    print_message $BLUE "----------------------------------------------" true
    print_message $BLUE "Welcome to AzerothCore Rebuild!           " true
    print_message $BLUE "----------------------------------------------" true
    echo ""
    print_message $BLUE "This script provides an interactive way to manage your AzerothCore server, including:" true
    print_message $BLUE "  - Updating the AzerothCore source code." true
    print_message $BLUE "  - Rebuilding the server with the latest changes." true
    print_message $BLUE "  - Running your AzerothCore server (authserver and worldserver)." true
    print_message $BLUE "  - Updating server modules conveniently." true
    echo ""
    print_message $BLUE "----------------------------------------------" true
    echo ""
}

# Function to display the menu
show_menu() {
    echo ""
    print_message $BLUE "================== MAIN MENU ==================" true
    echo ""
    print_message $YELLOW "Select an option:" true
    echo ""
    print_message $CYAN " Server Operations:" true
    print_message $YELLOW "  [1] Rebuild and Run Server        (Shortcut: R)" false
    print_message $YELLOW "  [2] Rebuild Server Only           (Shortcut: U)" false
    # [3] Run Server Only (Shortcut: S) has been removed
    print_message $YELLOW "  [3] Update Server Modules         (Shortcut: M)" false # Was [4]
    echo ""
    print_message $CYAN " Server Management & Configuration:" true
    print_message $YELLOW "  [4] Process Management            (Shortcut: P)" false # Was [5]
    print_message $YELLOW "  [5] Backup/Restore Options        (Shortcut: B)" false # Was [6]
    print_message $YELLOW "  [6] Log Viewer                    (Shortcut: L)" false # Was [7]
    print_message $YELLOW "  [7] Configuration Options         (Shortcut: C)" false # Was [8]
    echo ""
    print_message $CYAN " Script Maintenance:" true
    if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
        print_message $YELLOW "  [8] Self-Update ACrebuild Script  (Shortcut: A)" false
    fi
    print_message $CYAN " Exit:" true
    print_message $YELLOW "  [9] Quit Script                   (Shortcut: Q)" false # Renumbered from [8]
    echo ""
    print_message $BLUE "-----------------------------------------------" true
}

# Function to display current configuration
show_current_configuration() {
    echo ""
    print_message $BLUE "---------------- ACTIVE CONFIGURATION ---------------" true
    print_message $CYAN "Settings are loaded from: $CONFIG_FILE" false
    print_message $CYAN "If a value is empty, the script may use defaults or prompt you." false
    echo ""
    print_message $GREEN " AzerothCore Install Dir: $AZEROTHCORE_DIR" false
    print_message $GREEN " Cores for Build:         $CORES" false
    echo ""
    print_message $CYAN " Paths (derived from AzerothCore Install Dir):" false
    print_message $GREEN "  Build Directory:        $BUILD_DIR" false
    print_message $GREEN "  Auth Server Exec:     $AUTH_SERVER_EXEC" false
    print_message $GREEN "  World Server Exec:    $WORLD_SERVER_EXEC" false
    print_message $GREEN "  Server Config Dir:    $SERVER_CONFIG_DIR_PATH" false
    print_message $GREEN "  Server Log Dir:       $SERVER_LOG_DIR_PATH" false
    echo ""
    print_message $CYAN " Backup Configuration:" false
    print_message $GREEN "  Backup Directory:       $BACKUP_DIR" false
    print_message $GREEN "  DB User for Backups:    $DB_USER" false
    print_message $GREEN "  DB Password for Backups: ${DB_PASS:+****** (set)}" false # Show if set, but not the value
    print_message $GREEN "  Auth DB Name:           $AUTH_DB_NAME" false
    print_message $GREEN "  Characters DB Name:     $CHAR_DB_NAME" false
    print_message $GREEN "  World DB Name:          $WORLD_DB_NAME" false
    echo ""
    print_message $CYAN " Log File Configuration:" false
    print_message $GREEN "  Script Log Directory:   $SCRIPT_LOG_DIR" false
    print_message $GREEN "  Script Log Filename:    $SCRIPT_LOG_FILENAME" false
    print_message $GREEN "  Auth Server Log File:   $AUTH_SERVER_LOG_FILENAME" false
    print_message $GREEN "  World Server Log File:  $WORLD_SERVER_LOG_FILENAME" false
    echo ""
    print_message $BLUE "----------------------------------------------------" true
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
    echo "" # Add a newline after the key press
}

# Function to display configuration management menu
show_config_management_menu() {
    echo ""
    print_message $BLUE "=========== CONFIGURATION MANAGEMENT MENU ============" true
    echo ""
    print_message $YELLOW "Select an option:" true
    echo ""
    print_message $YELLOW "  [1] View Current Configuration" false
    print_message $YELLOW "  [2] Edit Configuration File ($CONFIG_FILE)" false
    print_message $YELLOW "  [3] Reset Configuration to Defaults" false
    print_message $YELLOW "  [4] Return to Main Menu" false
    echo ""
    print_message $BLUE "----------------------------------------------------" true
    handle_config_management_choice
}

# Function to handle configuration management menu choices
handle_config_management_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-4]: ${NC}")" config_choice
    case $config_choice in
        1)
            show_current_configuration
            ;;
        2)
            print_message $CYAN "Attempting to open $CONFIG_FILE with nano..." false
            if command -v nano &> /dev/null; then
                nano "$CONFIG_FILE"
            elif command -v vi &> /dev/null; then
                print_message $YELLOW "nano not found, using vi..." false
                vi "$CONFIG_FILE"
            elif command -v ed &> /dev/null; then
                print_message $YELLOW "nano and vi not found, using ed..." false
                ed "$CONFIG_FILE"
            else
                print_message $RED "No suitable text editor (nano, vi, ed) found." true
            fi
            print_message $CYAN "Reloading configuration after edit..." true
            load_config # Reload config after editing
            ;;
        3)
            print_message $RED "${BOLD}WARNING: This will delete your current configuration file and reset all settings to default.${NC}" true
            print_message $YELLOW "Are you sure you want to proceed? (y/n)" true
            read -r confirm_reset
            if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
                print_message $CYAN "Deleting $CONFIG_FILE..." false
                rm -f "$CONFIG_FILE"
                if [ $? -eq 0 ]; then
                    print_message $GREEN "Configuration file deleted." false
                else
                    print_message $RED "Error deleting configuration file. Check permissions." true
                fi
                print_message $CYAN "Reloading and creating default configuration..." false
                load_config # This will call create_default_config if file is missing
                print_message $GREEN "Configuration has been reset to defaults." true
            else
                print_message $GREEN "Configuration reset aborted." false
            fi
            ;;
        4)
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-4)." false
            ;;
    esac
    # After an action, explicitly call show_config_management_menu again
    if [[ "$config_choice" != "4" ]]; then
        # Adding a small pause and clear before showing the menu again for better UX
        read -n 1 -s -r -p "Press any key to return to Configuration Management menu..."
        clear
        show_config_management_menu
    fi
}


# Function to display backup and restore menu
show_backup_restore_menu() {
    echo ""
    print_message $BLUE "============== BACKUP/RESTORE MENU ==============" true
    echo ""
    print_message $YELLOW "Select an option:" true
    echo ""
    print_message $YELLOW "  [1] Create Backup" false
    print_message $YELLOW "  [2] Restore from Backup" false
    print_message $YELLOW "  [3] Return to Main Menu" false
    echo ""
    print_message $BLUE "-----------------------------------------------" true
    handle_backup_restore_choice # Call a new handler for this menu
}

# Function to display log viewer menu
show_log_viewer_menu() {
    echo ""
    print_message $BLUE "================== LOG VIEWER MENU ==================" true
    echo ""
    print_message $YELLOW "Select a log to view:" true
    echo ""
    print_message $YELLOW "  [1] View Script Log (ACrebuild.log)" false
    print_message $YELLOW "  [2] View Auth Server Log (authserver.log)" false
    print_message $YELLOW "  [3] View World Server Log (worldserver.log)" false
    print_message $YELLOW "  [4] Return to Main Menu" false
    echo ""
    print_message $BLUE "---------------------------------------------------" true
    handle_log_viewer_choice # Call a new handler for this menu
}

# Function to display process management menu
show_process_management_menu() {
    echo ""
    print_message $BLUE "=========== PROCESS MANAGEMENT MENU ============" true
    echo ""
    print_message $YELLOW "Select an option:" true
    echo ""
    print_message $YELLOW "  [1] Start Servers" false
    print_message $YELLOW "  [2] Stop Servers" false
    print_message $YELLOW "  [3] Restart Servers" false
    print_message $YELLOW "  [4] Check Server Status" false
    print_message $YELLOW "  [5] Return to Main Menu" false
    echo ""
    print_message $BLUE "-----------------------------------------------" true
    handle_process_management_choice # Call a new handler for this menu
}

# Function to handle process management menu choices
handle_process_management_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" proc_choice
    case $proc_choice in
        1)
            start_servers
            ;;
        2)
            stop_servers
            ;;
        3)
            restart_servers
            ;;
        4)
            check_server_status
            ;;
        5)
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-5)." false
            ;;
    esac
    # After an action, explicitly call show_process_management_menu again
    if [[ "$proc_choice" != "5" ]]; then
        # Adding a small pause and clear before showing the menu again for better UX
        read -n 1 -s -r -p "Press any key to return to Process Management menu..."
        clear
        show_process_management_menu
    fi
}

# Function to handle log viewer menu choices
handle_log_viewer_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-4]: ${NC}")" log_choice
    case $log_choice in
        1)
            view_script_log
            ;;
        2)
            view_auth_log
            ;;
        3)
            view_world_log
            ;;
        4)
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-4)." false
            ;;
    esac
    # After an action, explicitly call show_log_viewer_menu again
    if [[ "$log_choice" != "4" ]]; then
        show_log_viewer_menu
    fi
}

# Function to handle backup/restore menu choices
handle_backup_restore_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-3]: ${NC}")" backup_choice
    case $backup_choice in
        1)
            create_backup
            ;;
        2)
            restore_backup
            ;;
        3)
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-3)." false
            # We can optionally call show_backup_restore_menu again or just let it return
            ;;
    esac
    # After an action, explicitly call show_backup_restore_menu again to re-display it
    # unless the choice was to return to the main menu.
    if [[ "$backup_choice" != "3" ]]; then
        show_backup_restore_menu
    fi
}

# Function to self-update the script from its Git repository
self_update_script() {
    print_message $BLUE "--- ACrebuild Script Self-Update ---" true

    # Ensure SCRIPT_DIR_PATH is set (should be by check_script_git_status)
    if [ -z "$SCRIPT_DIR_PATH" ]; then
        print_message $RED "Error: Script directory path not set. Cannot determine location for update." true
        return 1
    fi

    print_message $CYAN "Changing to script directory: $SCRIPT_DIR_PATH" false
    cd "$SCRIPT_DIR_PATH" || { print_message $RED "Error: Could not change to script directory '$SCRIPT_DIR_PATH'. Update aborted." true; return 1; }

    # Fetch Updates
    print_message $CYAN "Fetching remote updates for ACrebuild.sh..." false
    if ! git fetch origin; then
        print_message $RED "Error: 'git fetch origin' failed. Update aborted." true
        # Attempt to change back to original directory if possible, though not critical for script exit/restart
        OLDPWD_PREV="${OLDPWD:-$HOME}" # Fallback if OLDPWD is not set
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    # Determine Default Branch
    DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    if [ -z "$DEFAULT_BRANCH" ]; then
        print_message $RED "Error: Could not determine the default remote branch (e.g., main, master). Update aborted." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi
    print_message $CYAN "Default remote branch detected as: $DEFAULT_BRANCH" false

    # Check for Updates
    LOCAL_HEAD=$(git rev-parse HEAD)
    REMOTE_HEAD=$(git rev-parse "origin/$DEFAULT_BRANCH")

    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        print_message $GREEN "ACrebuild.sh is already up to date (version $LOCAL_HEAD)." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 0 # Success, no update needed
    fi

    # Updates Available
    print_message $YELLOW "An update is available for ACrebuild.sh." true
    print_message $YELLOW "  Current version: $LOCAL_HEAD" false
    print_message $YELLOW "  Available version: $REMOTE_HEAD" false

    # Check for Local Changes
    # `git status --porcelain` outputs machine-readable status. Empty means no changes.
    if [ -n "$(git status --porcelain)" ]; then
        print_message $RED "You have local uncommitted changes in the script directory." true
        print_message $RED "Please commit or stash them before updating to prevent conflicts." true
        print_message $RED "Update aborted." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    # Ask for Confirmation
    echo ""
    print_message $YELLOW "Do you want to pull the latest changes? (y/n)" true
    read -r updateConfirm
    if [[ ! "$updateConfirm" =~ ^[Yy]$ ]]; then
        print_message $GREEN "Self-update cancelled by user." false
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 0 # User cancelled, not an error
    fi

    # Perform Update
    print_message $CYAN "Pulling latest changes from origin/$DEFAULT_BRANCH..." false
    if ! git pull origin "$DEFAULT_BRANCH"; then
        print_message $RED "Error: 'git pull' failed. Update aborted. You might need to resolve conflicts manually." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    print_message $GREEN "ACrebuild.sh updated successfully!" true
    print_message $YELLOW "Restarting the script to apply changes..." true
    sleep 2 # Give user a moment to read the message

    # Change back to the original directory before exec, if possible,
    # so the restarted script starts from the same CWD as the user initially ran it from.
    OLDPWD_PREV="${OLDPWD:-$HOME}"
    cd "$OLDPWD_PREV" &>/dev/null

    local script_actual_name=$(basename "${BASH_SOURCE[0]}")
    exec "$SCRIPT_DIR_PATH/$script_actual_name" "$@" # Replace current script process with the new version
    # If exec fails for some reason (it shouldn't normally), exit to prevent unexpected behavior.
    print_message $RED "Error: Failed to restart the script with exec. Please restart it manually." true
    exit 1
}

# Function to view a log file
view_log_file() {
    local log_file_path=$1
    local view_mode_prompt=$2 # true if we should prompt for mode, false if using a default (less)

    if [ ! -f "$log_file_path" ]; then
        print_message $RED "Log file not found: $log_file_path" true
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
        return 1
    fi

    local chosen_mode=""
    if [ "$view_mode_prompt" = true ]; then
        echo ""
        print_message $YELLOW "How do you want to view '$log_file_path'?" true
        print_message $CYAN "  [L] Less (scroll/browse)" false
        print_message $CYAN "  [T] Tail -f (live view)" false
        print_message $CYAN "  [C] Cancel" false
        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [L/T/C]: ${NC}")" mode_choice
        echo ""
        case $mode_choice in
            [Ll]) chosen_mode="less" ;;
            [Tt]) chosen_mode="tail_f" ;;
            [Cc]) print_message $GREEN "Log viewing cancelled." false; return ;;
            *) print_message $RED "Invalid mode selected. Defaulting to 'less'." false; chosen_mode="less" ;;
        esac
    else
        chosen_mode="less" # Default mode if not prompting
    fi

    print_message $GREEN "Opening $log_file_path with $chosen_mode..." false
    # Adding a small delay so the user can see the message before less/tail takes over the screen
    sleep 1
    clear

    if [ "$chosen_mode" = "less" ]; then
        less "$log_file_path"
    elif [ "$chosen_mode" = "tail_f" ]; then
        tail -f "$log_file_path"
    fi
    # After exiting less or tail -f, clear and show a message
    clear
    print_message $GREEN "Exited log view. Press any key to return to the Log Viewer menu..." true
    read -n 1 -s -r
    echo ""
}

view_script_log() {
    print_message $CYAN "Accessing script log..." false
    view_log_file "$SCRIPT_LOG_FILE" false # false means use default mode 'less'
}

view_auth_log() {
    print_message $CYAN "Accessing auth server log..." false
    local full_auth_log_path="$SERVER_LOG_DIR_PATH/$AUTH_SERVER_LOG_FILENAME"
    view_log_file "$full_auth_log_path" true # true means prompt for view mode
}

view_world_log() {
    print_message $CYAN "Accessing world server log..." false
    local full_world_log_path="$SERVER_LOG_DIR_PATH/$WORLD_SERVER_LOG_FILENAME"
    view_log_file "$full_world_log_path" true # true means prompt for view mode
}

# Function to list available backups
list_backups() {
    print_message $BLUE "--- Available Backups ---" true
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        print_message $YELLOW "No backups found in $BACKUP_DIR." false
        return 1
    fi

    print_message $CYAN "Available backup files in $BACKUP_DIR:" false
    i=0 # Ensure i is reset if list_backups is called multiple times in a session
    BACKUP_FILES=() # Ensure array is reset before populating
    for backup_file in "$BACKUP_DIR"/*.tar.gz; do
        print_message $WHITE "  [$((i+1))] $(basename "$backup_file")" false
        BACKUP_FILES[i]="$backup_file" # Store full path
        i=$((i+1))
    done
    echo ""
    return 0
}

# Function to create a backup
create_backup() {
    print_message $BLUE "--- Starting Backup Creation ---" true

    local current_db_user="$DB_USER" # From loaded config
    local new_db_user_entered=false

    if [ -z "$current_db_user" ]; then
        print_message $YELLOW "Database username is not set." true
        print_message $YELLOW "Enter the database username (e.g., acore):" true
        read -r db_user_input
        if [ -n "$db_user_input" ]; then
            DB_USER="$db_user_input" # Use for this session
            new_db_user_entered=true
        else
            print_message $RED "Database username cannot be empty for backup. Aborting." true
            return 1
        fi
    fi

    # If a new DB user was entered, or if the configured one is different from default and user might want to change it
    if [ "$new_db_user_entered" = true ] ; then
        print_message $YELLOW "Save database user '$DB_USER' to configuration? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]$ ]]; then
            save_config_value "DB_USER" "$DB_USER"
        fi
    fi

    # Handle DB Password
    # If DB_PASS is empty after loading config, always prompt.
    if [ -z "$DB_PASS" ]; then
        print_message $YELLOW "Enter the database password for user '$DB_USER':" true
        read -s new_db_pass
        echo "" # Newline after hidden input
        DB_PASS_RUNTIME="$new_db_pass" # Use this for the current operation

        if [ -n "$DB_PASS_RUNTIME" ]; then # Only offer to save if a password was actually entered
            print_message $YELLOW "Save this database password to configuration? (Not Recommended for security)" true
            print_message $RED "${BOLD}WARNING: Saving passwords in plaintext is a security risk!${NC}" true
            print_message $YELLOW "Choose 'y' only if you understand the implications. (y/n)" true
            read -r save_pass_choice
            if [[ "$save_pass_choice" =~ ^[Yy]$ ]]; then
                save_config_value "DB_PASS" "$DB_PASS_RUNTIME"
                DB_PASS="$DB_PASS_RUNTIME" # Ensure the global DB_PASS is also set if saved
            fi
        fi
    else
        # DB_PASS was loaded from config, use it directly for this operation.
        # No prompt unless we add an option to change saved passwords.
        print_message $CYAN "Using saved database password for user '$DB_USER'." false
        DB_PASS_RUNTIME="$DB_PASS"
    fi

    # Ensure we use the potentially runtime-only password for mysqldump
    local effective_db_pass="$DB_PASS_RUNTIME"


    # Create BACKUP_DIR if it doesn't exist
    if [ ! -d "$BACKUP_DIR" ]; then
        print_message $CYAN "Backup directory $BACKUP_DIR does not exist. Creating it..." false
        mkdir -p "$BACKUP_DIR" || { print_message $RED "Failed to create backup directory $BACKUP_DIR. Please check permissions." true; return 1; }
    fi

    # Create a timestamped subdirectory for the current backup
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_SUBDIR="$BACKUP_DIR/backup_$TIMESTAMP"
    mkdir -p "$BACKUP_SUBDIR" || { print_message $RED "Failed to create timestamped backup subdirectory $BACKUP_SUBDIR." true; return 1; }
    print_message $GREEN "Created backup subdirectory: $BACKUP_SUBDIR" false

    # Backup databases
    DATABASES=("$AUTH_DB_NAME" "$CHAR_DB_NAME" "$WORLD_DB_NAME")
    for DB_NAME in "${DATABASES[@]}"; do
        print_message $CYAN "Backing up database: $DB_NAME..." false
        mysqldump -u"$DB_USER" -p"$effective_db_pass" "$DB_NAME" > "$BACKUP_SUBDIR/$DB_NAME.sql"
        if [ $? -ne 0 ]; then
            print_message $RED "Error backing up database $DB_NAME. Check credentials (user: '$DB_USER') and mysqldump installation." true
            # Optional: cleanup partially created backup directory?
            rm -rf "$BACKUP_SUBDIR"
            # Clear runtime password attempt
            DB_PASS_RUNTIME=""
            return 1
        else
            print_message $GREEN "Database $DB_NAME backed up successfully." false
        fi
    done
    # Clear runtime password after use
    DB_PASS_RUNTIME=""

    # Copy server configuration files
    print_message $CYAN "Backing up server configuration files..." false
    for CONFIG_FILE in "${SERVER_CONFIG_FILES[@]}"; do
        if [ -f "$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE" ]; then
            cp "$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE" "$BACKUP_SUBDIR/"
            if [ $? -ne 0 ]; then
                print_message $RED "Error copying configuration file $CONFIG_FILE." true
                # Decide if this is a fatal error for the backup
            else
                print_message $GREEN "Configuration file $CONFIG_FILE backed up." false
            fi
        else
            print_message $YELLOW "Warning: Configuration file $SERVER_CONFIG_DIR_PATH/$CONFIG_FILE not found. Skipping." false
        fi
    done

    # Create a .tar.gz archive of the timestamped subdirectory
    ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
    print_message $CYAN "Creating archive $ARCHIVE_NAME..." false
    tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "backup_$TIMESTAMP"
    if [ $? -ne 0 ]; then
        print_message $RED "Error creating archive $ARCHIVE_NAME." true
        rm -rf "$BACKUP_SUBDIR" # Clean up subdir if archiving failed
        return 1
    else
        print_message $GREEN "Archive $ARCHIVE_NAME created successfully in $BACKUP_DIR." false
    fi

    # Remove the temporary timestamped subdirectory
    print_message $CYAN "Cleaning up temporary backup directory..." false
    rm -rf "$BACKUP_SUBDIR"
    print_message $GREEN "Backup process completed successfully." true
    echo ""
    read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
    echo ""
}

# Function to restore from a backup
restore_backup() {
    print_message $BLUE "--- Starting Restore Process ---" true
    echo ""

    BACKUP_FILES=() # Ensure array is reset
    list_backups
    if [ $? -ne 0 ]; then # No backups found or error in list_backups
        read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
        echo ""
        return 1
    fi

    print_message $YELLOW "Enter the number of the backup to restore:" true
    read -r backup_choice
    echo ""

    # Validate input
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#BACKUP_FILES[@]} ]; then
        print_message $RED "Invalid selection. Please enter a valid number from the list." true
        read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
        echo ""
        return 1
    fi

    SELECTED_BACKUP_FILE="${BACKUP_FILES[$((backup_choice-1))]}"
    print_message $CYAN "You selected to restore: $(basename "$SELECTED_BACKUP_FILE")" false

    local current_db_user="$DB_USER" # From loaded config
    local new_db_user_entered=false
    local DB_PASS_RUNTIME="" # To hold password for current session if not saved

    if [ -z "$current_db_user" ]; then
        print_message $YELLOW "Database username is not set." true
        print_message $YELLOW "Enter the database username (e.g., acore):" true
        read -r db_user_input
        if [ -n "$db_user_input" ]; then
            DB_USER="$db_user_input" # Use for this session
            new_db_user_entered=true
        else
            print_message $RED "Database username cannot be empty for restore. Aborting." true
            return 1
        fi
    fi

    if [ "$new_db_user_entered" = true ] ; then
        print_message $YELLOW "Save database user '$DB_USER' to configuration? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]$ ]]; then
            save_config_value "DB_USER" "$DB_USER"
        fi
    fi

    # Handle DB Password for restore
    if [ -z "$DB_PASS" ]; then # DB_PASS is from config, if empty, prompt
        print_message $YELLOW "Enter the database password for user '$DB_USER' (needed for restore):" true
        read -s new_db_pass # Read into a temporary variable
        echo "" # Newline after hidden input
        DB_PASS_RUNTIME="$new_db_pass" # Use this for the current operation

        if [ -n "$DB_PASS_RUNTIME" ]; then
            print_message $YELLOW "Save this database password to configuration? (Not Recommended for security)" true
            print_message $RED "${BOLD}WARNING: Saving passwords in plaintext is a security risk!${NC}" true
            print_message $YELLOW "Choose 'y' only if you understand the implications. (y/n)" true
            read -r save_pass_choice
            if [[ "$save_pass_choice" =~ ^[Yy]$ ]]; then
                save_config_value "DB_PASS" "$DB_PASS_RUNTIME"
                DB_PASS="$DB_PASS_RUNTIME" # Update global for consistency if saved
            fi
        fi
    else
        print_message $CYAN "Using saved database password for user '$DB_USER'." false
        DB_PASS_RUNTIME="$DB_PASS" # Use loaded password
    fi

    local effective_db_pass="$DB_PASS_RUNTIME"

    print_message $RED "WARNING: This will overwrite your current databases and configuration files." true
    print_message $YELLOW "Ensure your AzerothCore servers (authserver and worldserver) are STOPPED before proceeding." true
    print_message $YELLOW "Are you sure you want to continue? (y/n)" true
    read -r confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        print_message $GREEN "Restore process aborted by user." true
        return 1
    fi

    TEMP_RESTORE_DIR="$BACKUP_DIR/restore_temp_$(date +"%Y%m%d_%H%M%S")"
    mkdir -p "$TEMP_RESTORE_DIR" || { print_message $RED "Failed to create temporary restore directory." true; return 1; }

    print_message $CYAN "Extracting backup archive..." false
    tar -xzf "$SELECTED_BACKUP_FILE" -C "$TEMP_RESTORE_DIR"
    if [ $? -ne 0 ]; then
        print_message $RED "Error extracting backup archive." true
        rm -rf "$TEMP_RESTORE_DIR"
        return 1
    fi
    print_message $GREEN "Backup extracted to temporary directory: $TEMP_RESTORE_DIR" false

    # The tarball was created with a top-level directory like "backup_YYYYMMDD_HHMMSS"
    # We need to find this directory name to correctly path to the SQL files and configs.
    # Assuming there's only one directory inside TEMP_RESTORE_DIR after extraction.
    EXTRACTED_CONTENT_DIR=$(find "$TEMP_RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ -z "$EXTRACTED_CONTENT_DIR" ] || [ ! -d "$EXTRACTED_CONTENT_DIR" ]; then
        print_message $RED "Could not find the extracted content directory within $TEMP_RESTORE_DIR." true
        rm -rf "$TEMP_RESTORE_DIR"
        return 1
    fi
    print_message $CYAN "Content extracted to: $EXTRACTED_CONTENT_DIR" false


    # Restore databases
    DATABASES=("$AUTH_DB_NAME" "$CHAR_DB_NAME" "$WORLD_DB_NAME")
    for DB_NAME in "${DATABASES[@]}"; do
        SQL_FILE="$EXTRACTED_CONTENT_DIR/$DB_NAME.sql"
        if [ ! -f "$SQL_FILE" ]; then
            print_message $YELLOW "Warning: SQL file for database $DB_NAME not found in backup. Skipping." false
            continue
        fi
        print_message $CYAN "Restoring database: $DB_NAME..." false
        mysql -u"$DB_USER" -p"$effective_db_pass" "$DB_NAME" < "$SQL_FILE"
        if [ $? -ne 0 ]; then
            print_message $RED "Error restoring database $DB_NAME. Check credentials (user: '$DB_USER') and mysql client." true
            # Consider if we should stop or try to restore other things. For now, let's stop.
            rm -rf "$TEMP_RESTORE_DIR"
            DB_PASS_RUNTIME="" # Clear runtime password
            return 1
        else
            print_message $GREEN "Database $DB_NAME restored successfully." false
        fi
    done
    DB_PASS_RUNTIME="" # Clear runtime password after use

    # Restore configuration files
    print_message $CYAN "Restoring server configuration files..." false
    if [ ! -d "$SERVER_CONFIG_DIR_PATH" ]; then
        print_message $YELLOW "Warning: Server config directory $SERVER_CONFIG_DIR_PATH does not exist. Creating it." false
        mkdir -p "$SERVER_CONFIG_DIR_PATH" || { print_message $RED "Failed to create $SERVER_CONFIG_DIR_PATH. Config restore aborted." true; rm -rf "$TEMP_RESTORE_DIR"; return 1; }
    fi

    for CONFIG_FILE in "${SERVER_CONFIG_FILES[@]}"; do
        BACKED_UP_CONFIG_FILE="$EXTRACTED_CONTENT_DIR/$CONFIG_FILE"
        if [ -f "$BACKED_UP_CONFIG_FILE" ]; then
            cp "$BACKED_UP_CONFIG_FILE" "$SERVER_CONFIG_DIR_PATH/"
            if [ $? -ne 0 ]; then
                print_message $RED "Error restoring configuration file $CONFIG_FILE to $SERVER_CONFIG_DIR_PATH." true
            else
                print_message $GREEN "Configuration file $CONFIG_FILE restored." false
            fi
        else
            print_message $YELLOW "Warning: Backed up config file $CONFIG_FILE not found in archive. Skipping." false
        fi
    done

    # Clean up
    print_message $CYAN "Cleaning up temporary restore directory..." false
    rm -rf "$TEMP_RESTORE_DIR"
    print_message $GREEN "Restore process completed successfully." true
    echo ""
    read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
    echo ""
}

# Function to handle user input for the main menu.
# It maps both numeric choices and letter shortcuts to actions or sub-menus.
# For actions that don't lead to a build/run cycle (e.g., showing a sub-menu),
# it resets BUILD_ONLY and RUN_SERVER flags and returns to the main menu loop.
handle_menu_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [R, U, M, P, B, L, C, A, Q, or 1-9]: ${NC}")" choice # Prompt updated
    case $choice in
        1|[Rr]) # [1] Rebuild and Run Server
            RUN_SERVER=true
            BUILD_ONLY=true
            ;;
        2|[Uu]) # [2] Rebuild Server Only
            RUN_SERVER=false
            BUILD_ONLY=true
            ;;
        # Option [3] (Run Server Only) was removed.
        3|[Mm]) # [3] Update Server Modules
            MODULE_DIR="${AZEROTHCORE_DIR}/modules"
            update_modules "$MODULE_DIR"
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        4|[Pp]) # [4] Process Management
            show_process_management_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        5|[Bb]) # [5] Backup/Restore Options
            show_backup_restore_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        6|[Ll]) # [6] Log Viewer
            show_log_viewer_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        7|[Cc]) # [7] Configuration Options
            show_config_management_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        8|[Aa]) # [8] Self-Update ACrebuild Script
            if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
                self_update_script # Call the new function
            else
                print_message $RED "Cannot self-update: This script is not in a recognized Git repository or 'origin' remote is missing." true
            fi
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        9|[Qq]) # [9] Quit Script (Renumbered from 8)
            echo ""
            print_message $GREEN "Exiting. Thank you for using the AzerothCore Rebuild Tool!" true
            exit 0
            ;;
        *)
            echo ""
            print_message $RED "Invalid choice. Please select a valid option from the menu." false
            return
            ;;
    esac
}

# Function to ask for confirmation before updating or building.
# This function performs several pre-build checks:
# 1. Checks if Authserver (port 3724) or Worldserver (port 8085) seem to be running using 'nc'.
# 2. If servers appear active, it prompts the user to stop them.
# 3. If user agrees to stop:
#    a. Calls `stop_servers()`.
#    b. Re-checks ports to confirm successful shutdown. If still active, aborts build.
# 4. If user declines to stop active servers, aborts build.
# 5. If servers are stopped (or were not running), proceeds to ask about updating source code.
# 6. Finally, calls `ask_for_cores()`.
# Returns 0 if all checks pass and user confirms, allowing the build to proceed.
# Returns 1 if any check fails or user aborts, signaling to cancel the build.
ask_for_update_confirmation() {
    print_message $BLUE "--- Build Preparation ---" true

    # Step 1: Check if servers are running using port checks
    local auth_port_active=false
    local world_port_active=false
    if nc -z localhost 3724 &>/dev/null; then auth_port_active=true; fi
    if nc -z localhost 8085 &>/dev/null; then world_port_active=true; fi

    # Step 2 & 3: If servers active, prompt to stop
    if [ "$auth_port_active" = true ] || [ "$world_port_active" = true ]; then
        print_message $YELLOW "Servers appear to be running (ports 3724 and/or 8085 are active)." true
        print_message $YELLOW "It is strongly recommended to stop them before rebuilding." true
        print_message $YELLOW "Would you like to attempt to stop the servers now? (y/n)" true
        read -r stop_choice
        if [[ "$stop_choice" =~ ^[Yy]$ ]]; then
            # Step 3a: Call stop_servers()
            stop_servers
            local stop_result=$? # Capture return status of stop_servers (though currently it always returns 0)

            # Step 3b: Re-check ports to confirm successful shutdown
            if nc -z localhost 3724 &>/dev/null || nc -z localhost 8085 &>/dev/null; then
                # This condition means either stop_servers() didn't effectively stop them, or they restarted quickly.
                print_message $RED "Failed to stop servers (ports still active after stop attempt; stop_servers status: $stop_result)." true
                print_message $RED "Rebuild aborted to prevent issues. Please stop servers manually via Process Management." true
                return 1 # Abort build
            else
                print_message $GREEN "Servers stopped successfully." true
            fi
        else
            # Step 4: User chose not to stop servers
            print_message $RED "User chose not to stop servers. Rebuild aborted." true
            return 1 # Abort build
        fi
    else
        # Servers were not detected as running by port check
        print_message $GREEN "Servers appear to be stopped (ports 3724 and 8085 are not active)." false
    fi

    # Step 5: Ask about updating source code
    echo "" # Add a space before the next question
    while true; do
        print_message $YELLOW "Would you like to update the AzerothCore source code before rebuilding? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]$ ]]; then
            echo ""
            print_message $GREEN "Skipping source code update. Proceeding with build preparation...\n" true
            break
        else
            echo ""
            print_message $RED "Invalid input. Please enter 'y' for yes or 'n' for no." false
        fi
    done

    # Ask the user how many cores to use for building, after update or skipping
    ask_for_cores
    return 0 # Proceed with build
}

# Function to ask the user how many cores they want to use for the build
ask_for_cores() {
    local current_cores_for_build="$CORES" # CORES is the runtime var, loaded from CORES_FOR_BUILD
    local available_cores_system=$(nproc)

    echo ""
    print_message $YELLOW "CPU Core Selection for Building" true
    if [ -n "$current_cores_for_build" ]; then
        print_message $CYAN "Currently configured cores for build: $current_cores_for_build" false
    else
        print_message $CYAN "Cores for build not set in config. Will use system default or prompt." false
    fi
    print_message $YELLOW "Available CPU cores on this system: $available_cores_system" false
    print_message $YELLOW "Press ENTER to use default (all available: $available_cores_system), or enter number of cores:" false
    read -r user_cores_input

    local new_cores_value=""

    if [ -z "$user_cores_input" ]; then
        new_cores_value=$available_cores_system
        print_message $GREEN "Defaulting to $new_cores_value (all available) cores for this session." true
    elif ! [[ "$user_cores_input" =~ ^[0-9]+$ ]]; then
        print_message $RED "Invalid input: '$user_cores_input' is not a number. Using $available_cores_system cores for this session." true
        new_cores_value=$available_cores_system
    elif [ "$user_cores_input" -eq 0 ]; then
        print_message $RED "Cannot use 0 cores. Using 1 core for this session." true
        new_cores_value=1
    elif [ "$user_cores_input" -gt "$available_cores_system" ]; then
        print_message $RED "Cannot use more cores than available ($available_cores_system). Using $available_cores_system for this session." true
        new_cores_value=$available_cores_system
    else
        new_cores_value="$user_cores_input"
        print_message $GREEN "Using $new_cores_value core(s) for this session." true
    fi

    # Update runtime CORES variable for current session
    CORES="$new_cores_value"

    # Offer to save if the new value is different from what was loaded (or if loaded was empty and now we have a value)
    if [ "$new_cores_value" != "$current_cores_for_build" ] || ([ -z "$current_cores_for_build" ] && [ -n "$new_cores_value" ]); then
        print_message $YELLOW "Save $new_cores_value cores to configuration for future builds? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]$ ]]; then
            save_config_value "CORES_FOR_BUILD" "$new_cores_value"
            if [ $? -eq 0 ]; then
                print_message $GREEN "Cores for build ($new_cores_value) saved to configuration." true
            else
                print_message $RED "Failed to save cores for build." true
            fi
        else
            print_message $CYAN "Cores for build setting ($new_cores_value) will be used for this session only." false
        fi
    fi
    echo ""
}

# Function to build and install AzerothCore with spinner
build_and_install_with_spinner() {
    echo ""
    print_message $BLUE "--- Starting AzerothCore Build and Installation ---" true
    print_message $YELLOW "Building and installing AzerothCore... This may take a while." true

    # Ensure BUILD_DIR is correctly updated
    if [ ! -d "$BUILD_DIR" ]; then
        handle_error "Build directory $BUILD_DIR does not exist. Please check your AzerothCore path."
    fi

    # Run cmake with the provided options
    cd "$BUILD_DIR" || handle_error "Failed to change directory to $BUILD_DIR. Ensure the path is correct."

    echo ""
    print_message $CYAN "Running CMake configuration..." true
    cmake ../ -DCMAKE_INSTALL_PREFIX="$AZEROTHCORE_DIR/env/dist/" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static || handle_error "CMake configuration failed. Check CMake logs in $BUILD_DIR for details."

    echo ""
    print_message $CYAN "Running make install with $CORES core(s)..." true
    make -j "$CORES" install || handle_error "Build process ('make install') failed. Check the output above and logs in $BUILD_DIR for details."
    echo ""
    print_message $GREEN "--- AzerothCore Build and Installation Completed Successfully ---" true
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    print_message "$YELLOW" "Starting authserver for a quick test and waiting for it to be ready..." true

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Wait for the authserver to be ready by checking if the server is listening on the specified port
    AUTH_SERVER_PORT=3724  # Replace this with the actual port your authserver uses
    printf "%b" "${GREEN}Waiting for authserver to be ready on port $AUTH_SERVER_PORT... "

    # Wait for authserver to start accepting connections (max wait 60 seconds)
    for i in {1..60}; do
        nc -z localhost "$AUTH_SERVER_PORT" &>/dev/null && break # Fixed: Silencing nc output
        sleep 1
        printf "%b" "." # Simple visual feedback during wait
    done

    # If we didn't break out of the loop, the server isn't ready
    if ! nc -z localhost "$AUTH_SERVER_PORT" &>/dev/null; then # Fixed: Silencing nc output in check as well
        printf "\n" # Newline after dots
        handle_error "Authserver did not start within the expected time frame."
    fi

    printf "%b%s%b\n" "\n${GREEN}Authserver is ready! Waiting 5 seconds before closing..."
    sleep 5

    # Kill the authserver process
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null  # Wait for the authserver process to properly exit

    print_message "$GREEN" "Authserver test shutdown complete." true
}

# Function to start servers in TMUX.
# Creates a new TMUX session if one doesn't exist, with a specific split-pane layout:
# - Window 0, Pane 0 (left/top, $TMUX_SESSION_NAME:0.0): Authserver, titled with $AUTHSERVER_PANE_TITLE.
# - Window 0, Pane 1 (right/bottom, $TMUX_SESSION_NAME:0.1): Worldserver, titled with $WORLDSERVER_PANE_TITLE.
# If a session exists and appears to be correctly configured (2 panes in window 0), it informs the user.
# If session exists but misconfigured, it advises manual intervention.
# This function should NOT exit the script itself.
# Returns 0 on successful start command issuance, 1 on failure to start, 2 if servers might already be running.
start_servers() {
    print_message $BLUE "--- Attempting to Start AzerothCore Servers ---" true

    # Check if tmux is installed
    if ! command -v tmux &> /dev/null; then
        print_message $RED "TMUX is not installed. Please install it to manage servers." true
        return 1
    fi

    # Paths to executables, ensure they exist
    local auth_exec_path="$AZEROTHCORE_DIR/env/dist/bin/authserver"
    local world_exec_path="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
    local server_bin_dir="$AZEROTHCORE_DIR/env/dist/bin" # Base directory for cd

    if [ ! -f "$auth_exec_path" ]; then
        print_message $RED "Authserver executable not found at $auth_exec_path" true
        return 1
    fi
    if [ ! -f "$world_exec_path" ]; then
        print_message $RED "Worldserver executable not found at $world_exec_path" true
        return 1
    fi

    # Check if the session already exists
    if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' already exists." false

        # Check if window 0 exists and has two panes (our expected layout).
        local pane_count
        pane_count=$(tmux list-panes -t "$TMUX_SESSION_NAME:0" 2>/dev/null | wc -l) # Target window 0 specifically

        if [ "$pane_count" -eq 2 ]; then
            # Further checks could verify titles or processes, but for now, 2 panes is a good sign.
            print_message $GREEN "TMUX session '$TMUX_SESSION_NAME' appears to have a split-pane setup in window 0." false
            print_message $YELLOW "Servers might be running. Use 'Check Server Status' or 'Stop/Restart'." false
            return 2 # Indicate servers might be running / session active
        else
            # Session exists, but not in the expected split-pane state (e.g., wrong number of panes in window 0).
            print_message $RED "Session '$TMUX_SESSION_NAME' exists but is not in the expected 2-pane configuration for window 0." true
            print_message $YELLOW "Please use 'Stop Servers' (which might kill the session) and then 'Start Servers' again for a clean setup." true
            return 1 # Indicate misconfiguration
        fi
    else
        # Create new session if it doesn't exist
        print_message $CYAN "Creating new TMUX session '$TMUX_SESSION_NAME' with split-pane layout..." false
        # Create session detached, it will have one window (0) and one pane (0.0) by default.
        tmux new-session -s "$TMUX_SESSION_NAME" -d
        if [ $? -ne 0 ]; then
            print_message $RED "Failed to create new TMUX session." true
            return 1
        fi
        sleep 1 # Give TMUX a moment to initialize

        # Set title for the first pane (Authserver)
        tmux select-pane -t "$TMUX_SESSION_NAME:0.0" -T "$AUTHSERVER_PANE_TITLE"

        print_message $CYAN "Starting Authserver in the first pane ($TMUX_SESSION_NAME:0.0)..." false
        tmux send-keys -t "$TMUX_SESSION_NAME:0.0" "cd '$server_bin_dir' && '$auth_exec_path'" C-m

        # Wait for Authserver to be ready by checking its port
        AUTH_SERVER_PORT=3724
        print_message $CYAN "Waiting for authserver to be ready on port $AUTH_SERVER_PORT (max 60 seconds)..." false
        SPINNER=('\' '|' '/' '-')
        for i in {1..60}; do
            echo -ne "${CYAN}Checking port $AUTH_SERVER_PORT: attempt $i/60 ${SPINNER[$((i % ${#SPINNER[@]}))]} \r${NC}"
            nc -z localhost $AUTH_SERVER_PORT && break
            sleep 1
        done
        echo -ne "\r${NC}                                                                          \r" # Clear spinner line

        if ! nc -z localhost $AUTH_SERVER_PORT; then
            print_message $RED "Authserver did not start or become ready on port $AUTH_SERVER_PORT within 60 seconds." true
            print_message $RED "Check TMUX session '$TMUX_SESSION_NAME' (pane '$AUTHSERVER_PANE_TITLE') for errors." true
            tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null # Clean up the partially started session
            return 1
        fi
        print_message $GREEN "Authserver appears to be ready." true

        # Split the current window (window 0, pane 0.0) horizontally to create pane 0.1 for Worldserver
        print_message $CYAN "Splitting window and starting Worldserver in the second pane..." false
        tmux split-window -h -t "$TMUX_SESSION_NAME:0.0"
        if [ $? -ne 0 ]; then
            print_message $RED "Failed to split TMUX window." true
            tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null # Clean up
            return 1
        fi
        sleep 1 # Give TMUX a moment

        # Set title for the new pane (Worldserver, now pane 0.1)
        tmux select-pane -t "$TMUX_SESSION_NAME:0.1" -T "$WORLDSERVER_PANE_TITLE"

        print_message $CYAN "Starting Worldserver in the second pane ($TMUX_SESSION_NAME:0.1)..." false
        tmux send-keys -t "$TMUX_SESSION_NAME:0.1" "cd '$server_bin_dir' && '$world_exec_path'" C-m

        # Wait for Worldserver to be ready by checking its port
        local WORLD_SERVER_PORT=8085 # Define Worldserver port
        print_message $CYAN "Waiting for worldserver to be ready on port $WORLD_SERVER_PORT (max 60 seconds)..." false
        local world_spinner_chars=('\' '|' '/' '-') # Local spinner for this wait
        local world_ready=false
        for i in {1..60}; do
            # Use echo -ne to keep spinner on the same line
            echo -ne "\r${CYAN}Checking port $WORLD_SERVER_PORT: attempt $i/60 ${world_spinner_chars[$((i % ${#world_spinner_chars[@]}))]} ${NC} "
            if nc -z localhost $WORLD_SERVER_PORT &>/dev/null; then
                world_ready=true
                break
            fi
            sleep 1
        done
        echo -ne "\r${NC}                                                                          \r" # Clear spinner line

        if [ "$world_ready" = false ]; then
            print_message $RED "Worldserver did not start or become ready on port $WORLD_SERVER_PORT within 60 seconds." true
            print_message $RED "Check TMUX session '$TMUX_SESSION_NAME' (pane '$WORLDSERVER_PANE_TITLE') for errors." true
            # Note: Authserver is already running. The script will return 1, and the user might need to manually stop.
            # Consider if TMUX session should be killed here if worldserver fails. For now, matching authserver failure behavior.
            # tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null # Optionally kill session
            return 1 # Indicate failure
        else
            print_message $GREEN "Worldserver appears to be ready." true
        fi

        print_message $GREEN "Servers started in a split-pane layout in TMUX session '$TMUX_SESSION_NAME'." false
    fi

    # Common success messages
    echo ""
    print_message $CYAN "----------------------------------------------------------------------" true
    print_message $WHITE "\n  AzerothCore servers should now be starting/running in TMUX session '$TMUX_SESSION_NAME'." true
    print_message $YELLOW "  Authserver runs in the left pane ($AUTHSERVER_PANE_TITLE), Worldserver in the right pane ($WORLDSERVER_PANE_TITLE) of the first window." false
    echo ""
    print_message $CYAN "  To manage your server and view console output:" true
    print_message $WHITE "    ${BOLD}tmux attach -t $TMUX_SESSION_NAME${NC}" true
    echo ""
    print_message $CYAN "  Inside TMUX: Ctrl+B, then D to detach. Ctrl+B, <arrow_key> to switch panes." true
    print_message $CYAN "----------------------------------------------------------------------" true
    echo ""
    return 0 # Success
}

# Function to stop servers running in the TMUX split-pane layout
# Attempts graceful shutdown for Worldserver, then kills panes.
# Kills session if it becomes empty.
stop_servers() {
    print_message $BLUE "--- Attempting to Stop AzerothCore Servers ---" true

    # Check if TMUX is installed
    if ! command -v tmux &> /dev/null; then
        print_message $RED "TMUX is not installed. Cannot manage servers." true
        return 1
    fi

    # Check if the TMUX session exists
    if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' not found. Servers are likely not running." false
        return 0 # Not an error, just nothing to do
    fi

    print_message $CYAN "TMUX session '$TMUX_SESSION_NAME' found." false

    # Define pane targets based on the split-pane layout (window 0, panes 0.0 and 0.1)
    local auth_target_pane="$TMUX_SESSION_NAME:0.0" # Authserver in left/top pane
    local world_target_pane="$TMUX_SESSION_NAME:0.1" # Worldserver in right/bottom pane
    local world_pane_exists=false
    local auth_pane_exists=false

    # Check if worldserver pane (0.1) exists.
    # We check by index as titles can be unreliable if manually changed by user.
    # `tmux list-panes -t "$TMUX_SESSION_NAME:0"` lists panes in window 0.
    # Grep for `^1:` (pane index 1) or use more specific format if titles are set with select-pane -T
    if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then # Check if pane 0.1 exists
        world_pane_exists=true
    fi

    if $world_pane_exists; then
        print_message $YELLOW "Sending graceful shutdown command ('$WORLDSERVER_CONSOLE_COMMAND_STOP') to Worldserver pane ($world_target_pane)..." false
        tmux send-keys -t "$world_target_pane" "$WORLDSERVER_CONSOLE_COMMAND_STOP" C-m

        # Wait for Worldserver to shut down by checking port 8085
        local shutdown_timer=0
        local max_shutdown_wait=300 # 300 seconds = 5 minutes
        print_message $CYAN "Waiting for Worldserver (port 8085) to shut down (up to $max_shutdown_wait seconds)..." false
        local spinner_chars="/-\\|"

        while nc -z localhost 8085 &>/dev/null; do
            shutdown_timer=$((shutdown_timer + 1))
            if [ "$shutdown_timer" -gt "$max_shutdown_wait" ]; then
                print_message $RED "Worldserver did not shut down within $max_shutdown_wait seconds. Proceeding with pane kill." true
                break
            fi
            local char_index=$((shutdown_timer % ${#spinner_chars}))
            echo -ne "\r${CYAN}Waiting... ${spinner_chars:$char_index:1} (Attempt: $shutdown_timer/$max_shutdown_wait)${NC}  "
            sleep 1
        done
        echo -ne "\r${NC}                                                                          \r" # Clear spinner line

        if ! nc -z localhost 8085 &>/dev/null; then
            print_message $GREEN "Worldserver on port 8085 has shut down." false
        fi

        # Check if a post-shutdown delay is configured and positive
        if [ -n "$POST_SHUTDOWN_DELAY_SECONDS" ] && [ "$POST_SHUTDOWN_DELAY_SECONDS" -gt 0 ]; then
            print_message $CYAN "Waiting an additional ${POST_SHUTDOWN_DELAY_SECONDS}s for any final server processes to complete..." false
            sleep "$POST_SHUTDOWN_DELAY_SECONDS"
        fi

        # Re-check if pane 0.1 still exists after graceful shutdown attempt
        if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then
             print_message $YELLOW "Worldserver pane ($world_target_pane) still exists. Forcing closure." false
             tmux kill-pane -t "$world_target_pane" 2>/dev/null || print_message $RED "Failed to kill Worldserver pane $world_target_pane." false
        else
            print_message $GREEN "Worldserver pane ($world_target_pane) closed (likely from graceful shutdown or port closure)." false
        fi
    else
        print_message $YELLOW "Worldserver pane ($world_target_pane) not found." false
    fi

    # Check if authserver pane (0.0) exists
    if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^0$"; then # Check if pane 0.0 exists
        auth_pane_exists=true
    fi

    if $auth_pane_exists; then
        print_message $YELLOW "Stopping Authserver pane ($auth_target_pane) by sending C-c and killing pane..." false
        tmux send-keys -t "$auth_target_pane" C-c # Send Ctrl+C
        sleep 2 # Brief pause for C-c to take effect
        tmux kill-pane -t "$auth_target_pane" 2>/dev/null || print_message $RED "Failed to kill Authserver pane $auth_target_pane." false
        print_message $GREEN "Authserver pane ($auth_target_pane) stop command issued and pane killed." false
    else
        print_message $YELLOW "Authserver pane ($auth_target_pane) not found." false
    fi

    # After attempting to kill panes, check if the session should be killed.
    # If window 0 is now empty (no panes left), kill the session.
    if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        if ! tmux list-panes -t "$TMUX_SESSION_NAME:0" &> /dev/null; then
             print_message $CYAN "No more panes in window 0 of session '$TMUX_SESSION_NAME'. Killing session..." false
             tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
             print_message $GREEN "TMUX Session '$TMUX_SESSION_NAME' killed." false
        else
             # This might happen if kill-pane failed or if user created other panes/windows.
             print_message $YELLOW "Session '$TMUX_SESSION_NAME' still active. Panes might still exist." false
             print_message $YELLOW "Consider manual check: tmux attach -t $TMUX_SESSION_NAME" false
        fi
    fi
    print_message $GREEN "Server stop process completed." true
    return 0
}

# Function to restart servers
restart_servers() {
    print_message $BLUE "--- Attempting to Restart AzerothCore Servers ---" true

    stop_servers
    local stop_status=$?
    if [ $stop_status -ne 0 ]; then
        print_message $RED "Server stop phase failed. Aborting restart." true
        return 1
    fi

    print_message $CYAN "Waiting for 10 seconds before starting servers again..." true
    sleep 10

    start_servers
    local start_status=$?
    if [ $start_status -ne 0 ] && [ $start_status -ne 2 ]; then # 2 means already running, which is odd here but not a failure to start
        print_message $RED "Server start phase failed. Please check messages." true
        return 1
    elif [ $start_status -eq 2 ]; then
         print_message $YELLOW "Servers reported as already running during start phase. This is unexpected after a stop. Please check status." true
    fi

    print_message $GREEN "Server restart process initiated." true
    # Note: start_servers prints its own success/attach messages.
    return 0
}

# Function to check server status in TMUX
# This function checks for the TMUX session, then specific panes for Authserver and Worldserver.
# It attempts to identify processes by:
#   1. Direct PID command arguments: Checks if the command running under pane_pid is the server.
#   2. Child processes of pane_pid: Checks if the server is a child of the main pane process.
# It also checks if server ports (3724 for Auth, 8085 for World) are listening.
# Status messages are color-coded:
#   GREEN:  Process name matches and port is listening. Strongest indication of a healthy server.
#           For Worldserver, if PID is shared with Auth, GREEN if port is listening (process check is complex).
#   YELLOW: Partial success or indeterminate state. E.g.,
#           - Port listening but process name not confirmed.
#           - Process name confirmed but port not listening.
#           - Server/pane stopped or not found as expected.
#   RED:    Pane PID found, but both process name and port checks are negative/problematic.
check_server_status() {
    print_message $BLUE "--- Checking AzerothCore Server Status ---" true

    # Check if TMUX is installed
    if ! command -v tmux &> /dev/null; then
        print_message $RED "TMUX is not installed. Cannot determine server status." true
        return 1
    fi

    # Check if the TMUX session exists
    if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
        print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' is not running." false
        print_message $GREEN "Authserver: Stopped (TMUX session not found)" false # Simplified message
        print_message $GREEN "Worldserver: Stopped (TMUX session not found)" false # Simplified message
        return 0
    fi

    print_message $GREEN "TMUX Session '$TMUX_SESSION_NAME': Running" false

    # Define pane targets (pane 0.0 for Authserver, 0.1 for Worldserver in window 0)
    local auth_server_pane="$TMUX_SESSION_NAME:0.0"
    local world_server_pane="$TMUX_SESSION_NAME:0.1"

    # Variables for Authserver status
    local auth_pid=""
    local auth_direct_match_found=false
    local auth_child_match_found=false
    local auth_process_likely_running=false
    local auth_port_listening=false
    local auth_status_msg=""
    local auth_status_color=$YELLOW # Default to yellow for indeterminate/warning states

    # Variables for Worldserver status
    local world_pid=""
    local world_direct_match_found=false
    local world_child_match_found=false
    local world_process_likely_running=false
    local world_port_listening=false
    local world_status_msg=""
    local world_status_color=$YELLOW # Default to yellow
    local world_pid_is_shared_with_auth=false # Flag to check if worldserver pane PID is same as authserver

    # --- Authserver Check ---
    # Get PID of the process in the Authserver pane
    auth_pid=$(tmux list-panes -t "$auth_server_pane" -F "#{pane_pid}" 2>/dev/null | head -n 1)
    if [ -n "$auth_pid" ]; then
        # 1. Direct Process Check: Check if the command for auth_pid is 'authserver'
        if ps -p "$auth_pid" -o args= | grep -Eq "(^|/)authserver(\s|$|--)"; then
            auth_direct_match_found=true
        fi
        # 2. Child Process Check: If direct match failed, check if 'authserver' is a child process of auth_pid
        # This handles cases where the pane might be running a shell that then launched the server.
        if ! $auth_direct_match_found; then
            if ps -o args= -H --ppid "$auth_pid" | grep -Eq "(^|/)authserver(\s|$|--)"; then
                auth_child_match_found=true
            fi
        fi
        # Process is considered likely running if either direct or child match was found
        if $auth_direct_match_found || $auth_child_match_found; then
            auth_process_likely_running=true
        fi
    fi

    # Authserver Port Check (Port 3724)
    if nc -z localhost 3724 &>/dev/null; then
        auth_port_listening=true
    fi

    # Construct Authserver Status Message based on findings
    if $auth_port_listening && $auth_process_likely_running; then
        auth_status_msg="Authserver: Running (PID: $auth_pid, Process Name OK), Port 3724: Listening"
        auth_status_color=$GREEN
    elif $auth_port_listening && ! $auth_process_likely_running; then
        auth_status_msg="Authserver: Port 3724 Listening (Process name check inconclusive for pane PID $auth_pid)"
        # Stays YELLOW as port is good, but process name is unexpected for the pane's direct/child PID.
    elif ! $auth_port_listening && $auth_process_likely_running; then
        auth_status_msg="Authserver: Process Found (PID: $auth_pid, Name OK), Port 3724: Not Listening"
        # Stays YELLOW as process is there but port is not responding.
    elif [ -n "$auth_pid" ]; then # Pane PID exists but process name not matched AND port not listening
        auth_status_msg="Authserver: Pane $auth_server_pane active (PID: $auth_pid), but process/port non-responsive."
        auth_status_color=$RED # More critical: pane active, but server seems dead/unresponsive.
    else # Pane or PID for Authserver not found
        auth_status_msg="Authserver: Stopped (Pane $auth_server_pane not found or no PID)"
        # Stays YELLOW as this is a clear "stopped" state for this pane.
    fi
    print_message "$auth_status_color" "$auth_status_msg" false

    # --- Worldserver Check ---
    # Get PID of the process in the Worldserver pane
    world_pid=$(tmux list-panes -t "$world_server_pane" -F "#{pane_pid}" 2>/dev/null | head -n 1)

    # Check if Worldserver pane PID is the same as Authserver pane PID
    if [ -n "$world_pid" ] && [ "$world_pid" == "$auth_pid" ]; then
        world_pid_is_shared_with_auth=true
        # If PIDs are shared, process name check for worldserver against this PID is complex/misleading.
        # We will rely more on port status for worldserver in this specific scenario.
    fi

    # Perform process name check for Worldserver only if PID is not shared (or if world_pid is empty, this block is skipped)
    if [ -n "$world_pid" ] && [ "$world_pid_is_shared_with_auth" = false ]; then
        # 1. Direct Process Check for Worldserver
        if ps -p "$world_pid" -o args= | grep -Eq "(^|/)worldserver(\s|$|--)"; then
            world_direct_match_found=true
        fi
        # 2. Child Process Check for Worldserver
        if ! $world_direct_match_found; then
            if ps -o args= -H --ppid "$world_pid" | grep -Eq "(^|/)worldserver(\s|$|--)"; then
                world_child_match_found=true
            fi
        fi
        if $world_direct_match_found || $world_child_match_found; then
            world_process_likely_running=true
        fi
    fi

    # Worldserver Port Check (Port 8085)
    if nc -z localhost 8085 &>/dev/null; then
        world_port_listening=true
    fi

    # Construct Worldserver Status Message based on findings
    if $world_port_listening; then
        if $world_process_likely_running; then # Implies PIDs were different and name check passed
            world_status_msg="Worldserver: Running (PID: $world_pid, Process Name OK), Port 8085: Listening"
            world_status_color=$GREEN
        elif $world_pid_is_shared_with_auth; then
             # If PIDs are shared, port listening is the strongest positive signal for Worldserver.
             world_status_msg="Worldserver: Port 8085 Listening (Process name check complex due to shared pane PID with Authserver: $world_pid)"
             world_status_color=$GREEN
        else # Port listening, but process name check failed (and PID not shared or was different and still failed)
            world_status_msg="Worldserver: Port 8085 Listening (Process name check inconclusive for pane PID $world_pid)"
            # Stays YELLOW
        fi
    else # Port not listening
        if $world_process_likely_running; then # Implies PIDs were different and name check passed
            world_status_msg="Worldserver: Process Found (PID: $world_pid, Name OK), Port 8085: Not Listening"
            # Stays YELLOW
        elif [ -n "$world_pid" ]; then # Pane PID exists but port not listening AND (process name not confirmed OR PID shared)
            if $world_pid_is_shared_with_auth; then
                 world_status_msg="Worldserver: Pane $world_server_pane active (PID: $world_pid, shared with Authserver), Port 8085: Not Listening."
            else # PID not shared, but process name check failed
                 world_status_msg="Worldserver: Pane $world_server_pane active (PID: $world_pid), but Worldserver process/port non-responsive."
            fi
            world_status_color=$RED # More critical
        else # Pane or PID for Worldserver not found
            world_status_msg="Worldserver: Stopped (Pane $world_server_pane not found or no PID)"
            # Stays YELLOW
        fi
    fi
    print_message "$world_status_color" "$world_status_msg" false

    echo ""
    print_message $CYAN "Note: Status is based on TMUX pane PIDs, process arguments (direct & child), and port checks." false
    print_message $CYAN "For definitive status, attach to TMUX: tmux attach -t $TMUX_SESSION_NAME" false
    return 0
}

# Function to run worldserver and authserver in tmux session
# This is the original entry point from Main Menu option [3]
run_tmux_session() {
    # This function will now primarily be a wrapper around start_servers
    # and then handle the script exit as it did before.
    clear
    echo ""

    start_servers
    local start_status=$?

    if [ $start_status -eq 0 ]; then
        # Success message is already printed by start_servers
        # This function, when called from main menu option 3, should exit the script.
        exit 0
    elif [ $start_status -eq 2 ]; then
        # Servers might be running or session active, message already printed by start_servers
        # In this context (direct "Run Server Only"), we still inform and exit.
        print_message $YELLOW "To attach to the existing session: tmux attach -t $TMUX_SESSION_NAME" true
        exit 0 # Exit script as this option implies "I just want to run it (or ensure it's running)"
    else
        print_message $RED "Server startup failed. Please check messages above." true
        # Original script might have exited via handle_error. For this path, exiting with error is reasonable.
        exit 1
    fi
    # Fallback, though should be covered by exits above.
    RUN_SERVER=false
    BUILD_ONLY=false
}

# Function to run a command and capture its output
run_command() {
    local command=$1
    local cwd=$2
    if [ -z "$cwd" ]; then
        eval "$command"
    else
        (cd "$cwd" && eval "$command")
    fi
}

# Function to update a specific module by pulling the latest changes
update_module() {
    local module_dir=$1
    print_message $BLUE "Attempting to pull latest changes for module $(basename "$module_dir")..." false # Changed to print_message and basename
    if run_command "git pull" "$module_dir"; then
        print_message $GREEN "Successfully updated module $(basename "$module_dir")." false
    else
        print_message $RED "Failed to update module $(basename "$module_dir"). Please check output above for errors (e.g., merge conflicts, detached HEAD, network issues)." true
    fi
}

# Function to check for updates in modules
update_modules() {
    local module_dir=$1

    if [ ! -d "$module_dir" ]; then
        echo ""
        print_message $RED "Error: The module directory '$module_dir' does not exist." true
        print_message $RED "Please ensure the path is correct or create the directory if necessary." true
        return
    fi

    echo ""
    print_message $BLUE "=== Starting Update Check for Modules in '$module_dir' ===" true
    echo ""

    modules_with_updates=()
    found_git_repo=false

    for module in "$module_dir"/*; do
        if [ -d "$module" ] && [ -d "$module/.git" ]; then
            found_git_repo=true
            print_message $GREEN "Found Git repository: $(basename "$module")" false

            # Fetch the latest changes from the remote repository
            print_message $CYAN "Fetching updates for $(basename "$module")..." false
            run_command "git fetch origin" "$module"

            local=$(run_command "git rev-parse @" "$module")
            remote=$(run_command "git rev-parse @{u}" "$module") # Check against upstream tracking branch

            if [ "$local" != "$remote" ]; then
                print_message $YELLOW "Update available for $(basename "$module")!" true
                modules_with_updates+=("$module")
            else
                print_message $GREEN "$(basename "$module") is already up to date." true
            fi
            echo "" 
        fi
    done

    if ! $found_git_repo; then
        echo ""
        print_message $YELLOW "No Git repositories found in subdirectories of '$module_dir'." true
        print_message $BLUE "Module updates are skipped if no .git directories are present in module subfolders." true
        return
    fi
    
    if [ ${#modules_with_updates[@]} -eq 0 ]; then
        echo ""
        print_message $GREEN "All modules with Git repositories are already up to date." true
        return
    fi

    while true; do
        echo ""
        print_message $BLUE "============ MODULE UPDATE OPTIONS ============" true # Changed heading
        echo ""
        if [ ${#modules_with_updates[@]} -gt 0 ]; then
            print_message $YELLOW "The following modules have updates available:" true
            for module_path_item in "${modules_with_updates[@]}"; do
                # Using a bullet point for each module
                print_message $YELLOW "  • $(basename "$module_path_item")" false
            done
        fi
        echo ""
        print_message $CYAN "Select an action:" true # Changed to CYAN for sub-heading
        echo ""
        print_message $YELLOW "  [1] Update All Modules           (Shortcut: A)" false
        print_message $YELLOW "  [2] Update Specific Modules      (Shortcut: S)" false
        print_message $YELLOW "  [3] Quit Module Update           (Shortcut: Q)" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true # Added footer
        # Separate the prompt color from user input
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice ([A]ll, [S]pecific, [Q]uit, or 1-3): ${NC}")" choice
        echo ""

        if [[ "$choice" == "3" || "$choice" =~ ^[Qq]$ ]]; then
            print_message $GREEN "Exiting module update. Returning to main menu..." true
            return
        elif [[ "$choice" == "1" || "$choice" =~ ^[Aa]$ ]]; then
            print_message $YELLOW "Are you sure you want to update all listed modules? (y/n)" true
            read confirm
            if [[ "${confirm,,}" == "y" ]]; then
                for module_to_update in "${modules_with_updates[@]}"; do
                    update_module "$module_to_update"
                done
                echo ""
                print_message $GREEN "All selected modules have been updated successfully." true
                return 
            else
                print_message $RED "Update canceled." false
            fi
        elif [[ "$choice" == "2" || "$choice" =~ ^[Ss]$ ]]; then
            while true;
            do
                echo ""
                # Changed heading for specific module update
                print_message $BLUE "-------- SPECIFIC MODULE UPDATE --------" true
                echo ""
                if [ ${#modules_with_updates[@]} -eq 0 ]; then
                    print_message $GREEN "No more modules available to update in this session." true
                    # Added a footer here as well for consistency before breaking
                    print_message $BLUE "-----------------------------------------------" true
                    break # Break from specific module selection, back to A/S/Q
                fi
                print_message $YELLOW "Available modules for update:" false
                for i in "${!modules_with_updates[@]}"; do
                    # Formatting as "[i+1] module_name"
                    print_message $YELLOW "  [$((i+1))] $(basename "${modules_with_updates[i]}")" false
                done
                local back_option_number=$(( ${#modules_with_updates[@]} + 1 ))
                print_message $YELLOW "  [$back_option_number] Back to previous menu" false
                echo ""
                print_message $BLUE "-----------------------------------------------" true # Added footer
                # Updated prompt to reflect the dynamic back_option_number
                read -p "$(echo -e "${YELLOW}${BOLD}Enter module number to update or $back_option_number to go back: ${NC}")" specific_choice
                echo ""

                if ! [[ "$specific_choice" =~ ^[0-9]+$ ]]; then
                    print_message $RED "Invalid input: '$specific_choice' is not a number." true
                    continue
                fi

                # Using the dynamic back_option_number for comparison
                if [ "$specific_choice" -eq "$back_option_number" ]; then
                    break # Break from specific module selection, back to A/S/Q
                fi

                if [ "$specific_choice" -ge 1 ] && [ "$specific_choice" -le ${#modules_with_updates[@]} ]; then
                    module_index=$((specific_choice-1))
                    module_path_to_update=${modules_with_updates[$module_index]}
                    print_message $YELLOW "Are you sure you want to update $(basename "$module_path_to_update")? (y/n)" true
                    read confirm
                    if [[ "${confirm,,}" == "y" ]]; then
                        update_module "$module_path_to_update"
                        # Remove updated module from list
                        unset 'modules_with_updates[module_index]'
                        modules_with_updates=("${modules_with_updates[@]}") # Re-index array
                        print_message $GREEN "$(basename "$module_path_to_update") update process finished." true

                        # Check if all modules have been updated
                        if [ ${#modules_with_updates[@]} -eq 0 ]; then
                            print_message $GREEN "All available module updates completed. Returning to main menu..." true
                            return # Return from update_modules to the main menu loop
                        fi
                    else
                        print_message $RED "Update canceled for $(basename "$module_path_to_update")." false
                    fi
                else
                    print_message $RED "Invalid module number: $specific_choice. Please choose from the list." true
                fi
            done
        else
            print_message $RED "Invalid choice. Please enter A, S, Q, or 1-3." true
        fi
    done
}

# Main function to start the script
main_menu() {
    clear

    # Display welcome message
    welcome_message

    # Load configuration first
    load_config

    # Check the script's own Git status
    check_script_git_status
    check_for_script_updates

    # Check for dependencies
    check_dependencies

    # Ask for core installation path (which now uses/updates config)
    ask_for_core_installation_path

    # Show the menu in a loop
    while true; do
        show_menu
        handle_menu_choice

        # Proceed with selected action
        # Proceed with selected action only if flags are set
        if [ "$BUILD_ONLY" = true ] || [ "$RUN_SERVER" = true ]; then
            local can_proceed_with_build=true
            if [ "$BUILD_ONLY" = true ]; then
                ask_for_update_confirmation # This function now also calls ask_for_cores
                local build_prep_status=$?
                if [ $build_prep_status -ne 0 ]; then
                    can_proceed_with_build=false # Abort build
                    # Reset flags as build is aborted
                    BUILD_ONLY=false
                    RUN_SERVER=false
                fi

                if [ "$can_proceed_with_build" = true ]; then
                    build_and_install_with_spinner
                fi
            fi

            if [ "$RUN_SERVER" = true ] && [ "$can_proceed_with_build" = true ]; then
                # If only running the server, and no build was done, we still need to ensure paths are set.
                # ask_for_core_installation_path is called at the start, so paths should be known.
                run_tmux_session # This function now exits the script.
            elif [ "$BUILD_ONLY" = true ] && [ "$RUN_SERVER" = false ]; then
                # This case is for "Rebuild Only" - run temporary authserver
                run_authserver # This function no longer exits, returns to main_menu loop.
            fi
        # This case handles when only module update was chosen and completed.
        # Or if an invalid main menu choice was entered and returned.
        # No specific message needed here as update_modules gives feedback.
        fi
        
        # Reset action flags after execution for the next loop iteration
        RUN_SERVER=false
        BUILD_ONLY=false
    done
}

# Function to run a countdown timer and wait for user input
run_countdown_timer() {
    local DURATION=$1
    local USER_INPUT=""
    local TIMEOUT=$DURATION

    while [[ $TIMEOUT -gt 0 ]]; do
        MINUTES=$((TIMEOUT / 60))
        SECONDS=$((TIMEOUT % 60))
        # Use \r to return cursor to the beginning of the line for continuous update
        printf "\r${YELLOW}${BOLD}Enter your choice (y/n): Defaulting to 'yes' in %02d:%02d... ${NC}" "$MINUTES" "$SECONDS"

        read -r -t 1 USER_INPUT

        if [[ -n "$USER_INPUT" ]]; then
            echo "" # Newline after user input
            if [[ "$USER_INPUT" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                return 0 # Yes
            elif [[ "$USER_INPUT" =~ ^[Nn]([Oo])?$ ]]; then
                return 1 # No
            else
                # Optional: Handle invalid input during countdown differently, or let it be handled by the caller
                print_message $RED "\nInvalid input: '$USER_INPUT'. Please enter 'y' or 'n'." false
                # For now, let's treat invalid input as 'no' to avoid accidental 'yes' on typo, or simply re-prompt.
                # Re-prompting by continuing the loop. Let's clear the invalid input message.
                printf "\r%80s\r" " " # Clear the line
                USER_INPUT="" # Reset user input to continue loop or timeout
                # Or, to be strict, uncomment below and exit/return specific code for invalid input
                # return 2 # Invalid input code
            fi
        fi

        TIMEOUT=$((TIMEOUT - 1))
    done

    echo "" # Newline after timeout
    return 0 # Timeout (default to Yes)
}

# Function to handle errors
handle_error() {
    local error_message="$1"
    echo "" # Add whitespace before error
    print_message $RED "--------------------------------------------------------------------" true
    print_message $RED "ERROR: $error_message" true

    if [[ "$error_message" == *"CMake configuration failed"* || "$error_message" == *"Build process ('make install') failed"* ]]; then
        print_message $YELLOW "A build failure occurred. Would you like to run 'make clean' to try and fix it?" true

        run_countdown_timer 900 # Call the countdown function (900 seconds = 15 minutes)
        local countdown_result=$?

        if [ $countdown_result -eq 0 ]; then # User chose 'yes' or timed out
            print_message $GREEN "Running 'make clean'..." true
            if [ -d "$BUILD_DIR" ]; then
                (cd "$BUILD_DIR" && make clean) || print_message $RED "Warning: 'make clean' encountered an error, but attempting rebuild anyway." false
            else
                print_message $RED "Build directory $BUILD_DIR not found. Cannot run 'make clean'." true
            fi
            print_message $BLUE "Attempting to rebuild..." true
            build_and_install_with_spinner
            print_message $GREEN "Rebuild process finished." true
            exit 0
        elif [ $countdown_result -eq 1 ]; then # User chose 'no'
            print_message $RED "Skipping 'make clean'. Exiting." true
            print_message $RED "--------------------------------------------------------------------" true
            exit 1
        # Optional: Handle other return codes from run_countdown_timer if you added them (e.g., for invalid input)
        # else
        #     print_message $RED "Invalid response from countdown. Exiting." true
        #     exit 1
        fi
    elif [[ "$error_message" == *"authserver executable not found"* ]]; then
        print_message $RED "Suggestion: Ensure AzerothCore was built successfully and the path is correct." true
    elif [[ "$error_message" == *"TMUX session"* ]]; then
        print_message $RED "Suggestion: Ensure TMUX is installed ('sudo apt install tmux') and functioning correctly." true
    fi
    print_message $RED "--------------------------------------------------------------------" true
    exit 1
}

# Run the main menu function when the script starts
main_menu
