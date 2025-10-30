#!/bin/bash

cd "$(dirname "$0")" || exit 1

# Source all the library files in the correct order
source ./lib/variables.sh
source ./lib/core.sh
source ./lib/config.sh
source ./lib/dependencies.sh
source ./lib/update.sh
source ./lib/server.sh
source ./lib/backup.sh
source ./lib/database.sh
source ./lib/logging.sh
source ./lib/ui.sh
source ./lib/wizard.sh
source ./lib/validation.sh
source ./lib/cron.sh

# This function sources all libraries and runs initial setup checks.
initialize() {
    source ./lib/variables.sh
    source ./lib/core.sh
    source ./lib/config.sh
    source ./lib/dependencies.sh
    source ./lib/update.sh
    source ./lib/server.sh
    source ./lib/backup.sh
    source ./lib/database.sh
    source ./lib/logging.sh
    source ./lib/ui.sh
    source ./lib/wizard.sh
    source ./lib/validation.sh
    source ./lib/cron.sh

    load_config
    check_dependencies
}

# Main interactive menu function
main_menu() {
    clear
    check_script_git_status
    check_for_script_updates
    check_and_prompt_for_docker_usage

    # Main menu loop
    while true; do
        show_menu
        handle_menu_choice

        if [ "$BUILD_ONLY" = true ] || [ "$RUN_SERVER" = true ]; then
            local can_proceed_with_build=true
            if [ "$BUILD_ONLY" = true ]; then
                ask_for_update_confirmation
                if [ $? -ne 0 ]; then
                    can_proceed_with_build=false
                    BUILD_ONLY=false
                    RUN_SERVER=false
                fi

                if [ "$can_proceed_with_build" = true ]; then
                    build_and_install_with_spinner
                    # After build, if not running server, do post-build test for non-docker
                    if [ "$RUN_SERVER" = false ] && ! is_docker_setup; then
                        run_authserver
                    fi
                fi
            fi

            if [ "$RUN_SERVER" = true ] && [ "$can_proceed_with_build" = true ]; then
                run_tmux_session # This function now exits the script
            fi
        fi
        
        # Reset flags for the next loop iteration
        RUN_SERVER=false
        BUILD_ONLY=false
    done
}

# --- Script Entry Point ---

# Always run initialization first
initialize

# Check for command-line flags to determine script mode
if [ "${1-}" == "--run-backup" ]; then
    create_backup --non-interactive
    exit 0
else
    # Default to interactive main menu
    main_menu
fi
