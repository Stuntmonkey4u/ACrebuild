#!/bin/bash

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
    # Set DB_USER default based on whether USE_DOCKER is true
    USE_DOCKER="${USE_DOCKER:-$DEFAULT_USE_DOCKER}"
    if [ "$USE_DOCKER" = true ]; then
        DB_USER="${DB_USER:-$DEFAULT_DB_USER_DOCKER}"
    else
        DB_USER="${DB_USER:-$DEFAULT_DB_USER}"
    fi
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
    ERROR_LOG_FILENAME="${ERROR_LOG_FILENAME:-$DEFAULT_ERROR_LOG_FILENAME}"

    # SCRIPT_LOG_DIR_CONF and SCRIPT_LOG_FILENAME_CONF are read from config file
    # Then we set the main SCRIPT_LOG_DIR and SCRIPT_LOG_FILE used by print_message
    SCRIPT_LOG_DIR="${SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}" # This uses the SCRIPT_LOG_DIR var from config file
    SCRIPT_LOG_FILENAME="${SCRIPT_LOG_FILENAME:-$DEFAULT_SCRIPT_LOG_FILENAME}" # Uses SCRIPT_LOG_FILENAME from config

    POST_SHUTDOWN_DELAY_SECONDS="${POST_SHUTDOWN_DELAY_SECONDS:-$DEFAULT_POST_SHUTDOWN_DELAY_SECONDS}"
    CORES="${CORES_FOR_BUILD:-$DEFAULT_CORES_FOR_BUILD}" # CORES is the runtime var, CORES_FOR_BUILD is from config
    USE_DOCKER="${USE_DOCKER:-$DEFAULT_USE_DOCKER}"

    # --- Assign non-user-configurable variables from defaults ---
    AUTH_PORT="${DEFAULT_AUTH_PORT}"
    WORLD_PORT="${DEFAULT_WORLD_PORT}"

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

# Filename for the server errors log (located in SERVER_LOG_DIR_PATH)
ERROR_LOG_FILENAME="$DEFAULT_ERROR_LOG_FILENAME"

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

# Set to 'true' to enable Docker mode, 'false' otherwise.
# If this is true, the script will use 'docker compose' for server management.
USE_DOCKER="$DEFAULT_USE_DOCKER"
EOF
    local cat_exit_code=$?
    if [ $cat_exit_code -eq 0 ]; then
        print_message $GREEN "Default configuration file created successfully." true
        # Set permissions to 600 (read/write for owner only) for security
        chmod 600 "$CONFIG_FILE" 2>/dev/null || print_message $YELLOW "Warning: Could not set permissions for $CONFIG_FILE. Please set them manually to 600." false
    else
        print_message $RED "Error creating default configuration file. Please check permissions for $CONFIG_DIR." true
        # Not exiting here, load_config will handle the error if file is unusable
    fi
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
