#!/bin/bash

# Source all the library files in the correct order
source ./lib/variables.sh
source ./lib/core.sh
source ./lib/config.sh
source ./lib/dependencies.sh
source ./lib/update.sh
source ./lib/server.sh
source ./lib/backup.sh
source ./lib/logging.sh
source ./lib/ui.sh

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

    # Check for potential docker setup and prompt user if needed
    check_and_prompt_for_docker_usage

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
                if ! is_docker_setup; then
                    run_authserver # This function no longer exits, returns to main_menu loop.
                fi
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
