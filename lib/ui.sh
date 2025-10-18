#!/bin/bash

# This file contains all the UI-related functions
# such as menus, messages, and user interaction handlers.

# Function to display a welcome message
welcome_message() {
    clear
    print_message $BLUE "----------------------------------------------" true
    print_message $BLUE "Welcome to ACebuild!           " true
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
    # Docker mode indicator
    if is_docker_setup; then
        print_message $CYAN "     ✨ Docker Setup Detected ✨" true
    fi
    # Update notification
    if [ "$SCRIPT_UPDATE_AVAILABLE" = true ]; then
        print_message $YELLOW "   ✨ An update is available for this script! ✨" true
    fi
    echo ""
    print_message $YELLOW "Select an option:" true
    echo ""
    print_message $CYAN " Core Actions:" true
    print_message $YELLOW "  [1] Rebuild and Run Server" false
    print_message $YELLOW "  [2] Rebuild Server Only" false
    echo ""
    print_message $CYAN " Management & Tools:" true
    print_message $YELLOW "  [3] Module Management" false
    print_message $YELLOW "  [4] Server Management" false
    print_message $YELLOW "  [5] Log Viewer" false
    print_message $YELLOW "  [6] Backup & Restore" false
    print_message $YELLOW "  [7] Configuration" false
    if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
        print_message $YELLOW "  [8] Self-Update ACrebuild Script" false
    fi
    echo ""
    print_message $CYAN " Exit:" true
    local quit_option=8
    if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
        quit_option=9
    fi
    print_message $YELLOW "  [$quit_option] Quit Script" false
    echo ""
    print_message $BLUE "-----------------------------------------------" true
}

# Function to check for a potential Docker setup and prompt the user to enable it.
# This should only run once on startup if the conditions are met.
check_and_prompt_for_docker_usage() {
    # Conditions to check:
    # 1. A docker-compose.yml file exists in the AzerothCore directory.
    # 2. The 'docker' command is available on the system.
    # 3. The USE_DOCKER flag is currently false.
    if [ -f "$AZEROTHCORE_DIR/docker-compose.yml" ] && [ -n "$DOCKER_EXEC_PATH" ] && [ "$USE_DOCKER" = false ]; then
        echo ""
        print_message $BLUE "------------------- Docker Setup Detected --------------------" true
        print_message $YELLOW "We've detected a 'docker-compose.yml' file and the 'docker' command." false
        print_message $YELLOW "It looks like you might be running a Docker-based setup." false
        print_message $CYAN "The script is currently in non-Docker mode." false
        print_message $YELLOW "Would you like to enable Docker Mode now? (y/n)" true
        read -r docker_choice
        if [[ "$docker_choice" =~ ^[Yy]$ ]]; then
            print_message $GREEN "Enabling Docker Mode and saving to configuration..." true
            save_config_value "USE_DOCKER" "true"
            # Reload config to ensure the change is active for the current session
            load_config
        else
            print_message $CYAN "Keeping Docker Mode disabled for this session." false
            print_message $CYAN "You can enable it later in the Configuration Options menu." false
        fi
        print_message $BLUE "------------------------------------------------------------" true
        echo ""
    fi
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
}

# Function to display configuration management menu
show_config_management_menu() {
    while true; do
        clear
        echo ""
        print_message $BLUE "=========== CONFIGURATION MANAGEMENT MENU ============" true
        echo ""
        local docker_status_msg="DISABLED"
        if [ "$USE_DOCKER" = true ]; then
            docker_status_msg="ENABLED"
        fi
        print_message $CYAN "Docker Mode is currently: $docker_status_msg" false
        echo ""
        print_message $YELLOW "Select an option:" true
        echo ""
        print_message $YELLOW "  [1] View Current Configuration" false
        print_message $YELLOW "  [2] Edit Configuration File ($CONFIG_FILE)" false
        print_message $YELLOW "  [3] Toggle Docker Mode" false
        print_message $YELLOW "  [4] Validate Current Settings" false
        print_message $YELLOW "  [5] Reset Configuration to Defaults" false
        print_message $YELLOW "  [6] Return to Main Menu" false
        echo ""
        print_message $BLUE "----------------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-6]: ${NC}")" config_choice
        case "$config_choice" in
            1)
                show_current_configuration
                ;;
            2)
                print_message $CYAN "Attempting to open $CONFIG_FILE for editing..." false
                # Prioritize $EDITOR variable if it is set and points to an executable command
                # Use ${EDITOR-} to avoid unbound variable error if 'set -u' is active
                if [ -n "${EDITOR-}" ] && command -v "$EDITOR" &> /dev/null; then
                    print_message $CYAN "Using editor from \$EDITOR environment variable: $EDITOR" false
                    "$EDITOR" "$CONFIG_FILE"
                elif command -v nano &> /dev/null; then
                    print_message $CYAN "Using nano..." false
                    nano "$CONFIG_FILE"
                elif command -v vi &> /dev/null; then
                    print_message $YELLOW "nano not found, using vi..." false
                    vi "$CONFIG_FILE"
                elif command -v ed &> /dev/null; then
                    print_message $YELLOW "nano and vi not found, using ed..." false
                    ed "$CONFIG_FILE"
                else
                    print_message $RED "No suitable text editor (nano, vi, ed, or from \$EDITOR) found." true
                fi
                print_message $CYAN "Reloading configuration after edit..." true
                load_config # Reload config after editing
                ;;
            3)
                local new_docker_mode
                local confirm_toggle
                print_message $YELLOW "Are you sure you want to toggle Docker Mode? (y/n)" true
                read -r confirm_toggle
                if [[ "$confirm_toggle" =~ ^[Yy]$ ]]; then
                    if [ "$USE_DOCKER" = true ]; then
                        new_docker_mode=false
                        print_message $GREEN "Disabling Docker Mode." false
                        # If current DB user is the Docker default, switch it to the standard default
                        if [ "$DB_USER" == "$DEFAULT_DB_USER_DOCKER" ]; then
                            print_message $CYAN "Switching DB_USER to standard default '$DEFAULT_DB_USER'." false
                            save_config_value "DB_USER" "$DEFAULT_DB_USER"
                        fi
                    else
                        new_docker_mode=true
                        print_message $GREEN "Enabling Docker Mode." false
                        # If current DB user is the standard default, switch it to the Docker default
                        if [ "$DB_USER" == "$DEFAULT_DB_USER" ]; then
                            print_message $CYAN "Switching DB_USER to Docker default '$DEFAULT_DB_USER_DOCKER'." false
                            save_config_value "DB_USER" "$DEFAULT_DB_USER_DOCKER"
                        fi
                    fi
                    save_config_value "USE_DOCKER" "$new_docker_mode"
                    # Reload config to make the change active immediately
                    load_config
                else
                    print_message $GREEN "Docker Mode toggle cancelled." false
                fi
                ;;
            4)
                validate_settings
                ;;
            5)
                print_message $RED "${BOLD}WARNING: This will delete your current configuration file and reset all settings to default.${NC}" true
                print_message $YELLOW "Are you sure you want to proceed? (y/n)" true
                read -r confirm_reset
                if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
                    print_message $CYAN "Deleting $CONFIG_FILE..." false
                    rm -f "$CONFIG_FILE"
                    if [ "$?" -eq 0 ]; then
                        print_message $GREEN "Configuration file deleted." false
                    else
                        print_message $RED "Error deleting configuration file. Check permissions." true
                    fi
                    # The wizard will now run on the next load_config call
                    print_message $CYAN "Configuration has been reset. The setup wizard will run next." true
                    load_config
                else
                    print_message $GREEN "Configuration reset aborted." false
                fi
                ;;
            6)
                print_message $GREEN "Returning to Main Menu..." false
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-6)." false
                ;;
        esac

        # Adding a small pause before showing the menu again for better UX
        if [[ "$config_choice" != "5" ]]; then
             read -n 1 -s -r -p "Press any key to return to Configuration Management menu..."
        fi
    done
}


# Function to display backup and restore menu
show_backup_restore_menu() {
    while true; do
        clear
        echo ""
        print_message $BLUE "============== BACKUP/RESTORE MENU ==============" true
        echo ""
        print_message $YELLOW "Select an option:" true
        echo ""
        print_message $YELLOW "  [1] Create Backup" false
        print_message $YELLOW "  [2] Create Backup (Dry Run)" false
        print_message $YELLOW "  [3] Restore from Backup" false
        print_message $YELLOW "  [4] Manage Automated Backups" false
        print_message $YELLOW "  [5] Return to Main Menu" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" backup_choice
        case "$backup_choice" in
            1)
                create_backup
                ;;
            2)
                create_backup_dry_run
                ;;
            3)
                restore_backup
                ;;
            4)
                show_automated_backup_menu
                ;;
            5)
                print_message $GREEN "Returning to Main Menu..." false
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-5)." false
                ;;
        esac
        # Adding a small pause before showing the menu again for better UX
        # Only pause if we are not entering another submenu and not exiting
        if [[ "$backup_choice" != "4" && "$backup_choice" != "5" ]]; then
            read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
        fi
    done
}

# Function to display the automated backup management menu
show_automated_backup_menu() {
    if ! command -v crontab &>/dev/null; then
        print_message $RED "Error: 'crontab' command not found. This feature is not supported on your system." true
        read -n 1 -s -r -p "Press any key to return..."
        return 1
    fi

    check_cron_service
    local cron_status=$?
    if [ $cron_status -ne 0 ]; then
        print_message $RED "Error: The cron service is not running on your system." true
        print_message $YELLOW "Automated backups cannot be scheduled without the cron daemon." true
        print_message $YELLOW "On most systems, you can enable it with: sudo systemctl enable --now cron" true
        read -n 1 -s -r -p "Press any key to return..."
        return 1
    fi

    while true; do
        clear
        echo ""
        print_message $BLUE "========== AUTOMATED BACKUP MANAGEMENT ==========" true
        echo ""
        print_message $YELLOW "Select an option:" true
        echo ""
        print_message $YELLOW "  [1] Setup or Change Schedule" false
        print_message $YELLOW "  [2] View Current Schedule" false
        print_message $YELLOW "  [3] Disable Automated Backups" false
        print_message $YELLOW "  [4] Return to Backup/Restore Menu" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-4]: ${NC}")" backup_mgmt_choice
        case "$backup_mgmt_choice" in
            1) setup_backup_schedule ;;
            2) view_backup_schedule ;;
            3) disable_automated_backups ;;
            4) break ;;
            *) print_message $RED "Invalid choice. Please select a valid option." false ;;
        esac
        if [[ "$backup_mgmt_choice" != "4" ]]; then
            read -n 1 -s -r -p "Press any key to return to the Automated Backup menu..."
        fi
    done
}

# Function to display log viewer menu
show_log_viewer_menu() {
    while true; do
        clear
        echo ""
        print_message $BLUE "================== LOG VIEWER MENU ==================" true
        echo ""
        print_message $YELLOW "Select a log to view:" true
        echo ""
        print_message $CYAN "  Standard View (less):" true
        print_message $YELLOW "    [1] View Auth Server Log ($AUTH_SERVER_LOG_FILENAME)" false
        print_message $YELLOW "    [2] View World Server Log ($WORLD_SERVER_LOG_FILENAME)" false
        print_message $YELLOW "    [3] View SQL Error Log ($ERROR_LOG_FILENAME)" false
        echo ""
        print_message $CYAN "  Live View (tail -f):" true
        print_message $YELLOW "    [4] Live View Auth Server Log" false
        print_message $YELLOW "    [5] Live View World Server Log" false
        echo ""
        print_message $CYAN "  Cron/Scheduled Task Logs:" true
        print_message $YELLOW "    [6] View Automated Backup Log" false
        echo ""
        print_message $YELLOW "  [7] Return to Main Menu" false
        echo ""
        print_message $BLUE "---------------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-7]: ${NC}")" log_choice
        case "$log_choice" in
            1) view_auth_log ;;
            2) view_world_log ;;
            3) view_error_log ;;
            4) view_auth_log_live ;;
            5) view_world_log_live ;;
            6) view_cron_log ;;
            7)
                print_message $GREEN "Returning to Main Menu..." false
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-7)." false
                ;;
        esac
        # No pause here, as log viewers handle their own exit.
    done
}

# Function to display module management menu
show_module_management_menu() {
    while true; do
        clear
        echo ""
        print_message $BLUE "============= MODULE MANAGEMENT MENU =============" true
        echo ""
        print_message $YELLOW "Select an option:" true
        echo ""
        print_message $YELLOW "  [1] Install New Module" false
        print_message $YELLOW "  [2] Update Server Modules" false
        print_message $YELLOW "  [3] Return to Main Menu" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-3]: ${NC}")" module_choice
        case "$module_choice" in
            1)
                install_module
                ;;
            2)
                MODULE_DIR="${AZEROTHCORE_DIR}/modules"
                update_modules "$MODULE_DIR"
                ;;
            3)
                print_message $GREEN "Returning to Main Menu..." false
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-3)." false
                ;;
        esac
        # Adding a small pause before showing the menu again for better UX
        # Only pause if we are not exiting
        if [[ "$module_choice" != "3" ]]; then
            read -n 1 -s -r -p "Press any key to return to Module Management menu..."
        fi
    done
}

# Function to display server management menu
show_server_management_menu() {
    while true; do
        clear
        echo ""
        print_message $BLUE "============ SERVER MANAGEMENT MENU ============" true
        echo ""
        print_message $YELLOW "Select an option:" true
        echo ""
        print_message $YELLOW "  [1] Process Management" false
        print_message $YELLOW "  [2] Database Console" false
        print_message $YELLOW "  [3] Return to Main Menu" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-3]: ${NC}")" server_mgmt_choice
        case "$server_mgmt_choice" in
            1)
                show_process_management_menu
                ;;
            2)
                database_console
                ;;
            3)
                print_message $GREEN "Returning to Main Menu..." false
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-3)." false
                ;;
        esac
    done
}

# Function to display process management menu
show_process_management_menu() {
    while true; do
        clear
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

        echo ""
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" proc_choice
        case "$proc_choice" in
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
                break
                ;;
            *)
                print_message $RED "Invalid choice. Please select a valid option (1-5)." false
                ;;
        esac
        # Adding a small pause before showing the menu again for better UX
        # Only pause if we are not exiting
        if [[ "$proc_choice" != "5" ]]; then
            read -n 1 -s -r -p "Press any key to return to Process Management menu..."
        fi
    done
}

# Function to handle user input for the main menu.
# It maps both numeric choices and letter shortcuts to actions or sub-menus.
# For actions that don't lead to a build/run cycle (e.g., showing a sub-menu),
# it resets BUILD_ONLY and RUN_SERVER flags and returns to the main menu loop.
handle_menu_choice() {
    local max_option
    if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
        max_option=9
    else
        max_option=8
    fi

    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-$max_option]: ${NC}")" choice
    case "$choice" in
        1) # Rebuild and Run Server
            RUN_SERVER=true
            BUILD_ONLY=true
            ;;
        2) # Rebuild Server Only
            RUN_SERVER=false
            BUILD_ONLY=true
            ;;
        3) # Module Management
            show_module_management_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        4) # Server Management
            show_server_management_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        5) # Log Viewer
            show_log_viewer_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        6) # Backup/Restore Options
            show_backup_restore_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        7) # Configuration Options
            show_config_management_menu
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        8) # Self-Update ACrebuild Script or Quit
            if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
                self_update_script
            else
                # This is the "Quit" option when not in a git repo
                echo ""
                print_message $GREEN "Exiting. Thank you for using the AzerothCore Rebuild Tool!" true
                exit 0
            fi
            RUN_SERVER=false
            BUILD_ONLY=false
            return
            ;;
        9) # Quit Script
            if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
                # This is the "Quit" option when self-update is available
                echo ""
                print_message $GREEN "Exiting. Thank you for using the AzerothCore Rebuild Tool!" true
                exit 0
            else
                # This case is hit if user enters 8 but self-update is not an option
                print_message $RED "Invalid choice. Please select a valid option from the menu." false
            fi
            return
            ;;
        *)
            echo ""
            print_message $RED "Invalid choice. Please select a valid option from the menu." false
            return
            ;;
    esac
}
