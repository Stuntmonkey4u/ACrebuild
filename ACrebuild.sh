#!/bin/bash

# Source all the library files
source ./lib/core.sh
source ./lib/config.sh
source ./lib/dependencies.sh
source ./lib/update.sh
source ./lib/server.sh
source ./lib/backup.sh
source ./lib/logging.sh
source ./lib/ui.sh

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
DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX="env/dist/bin"
DEFAULT_AUTH_SERVER_LOG_FILENAME="Auth.log"
DEFAULT_WORLD_SERVER_LOG_FILENAME="Server.log"
DEFAULT_ERROR_LOG_FILENAME="Errors.log"
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
ERROR_LOG_FILENAME=""
# SCRIPT_LOG_DIR_CONF and SCRIPT_LOG_FILENAME_CONF were part of an earlier idea and are no longer used.
# SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME are loaded directly, and print_message handles pre-config state.
SCRIPT_LOG_FILE="" # Actual path to script log file, derived by load_config from SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME
POST_SHUTDOWN_DELAY_SECONDS=""
CORES="" # Runtime variable, takes its value from CORES_FOR_BUILD in config.

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


# Run the main menu function when the script starts
main_menu
