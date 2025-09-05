#!/bin/bash

# This file contains all the UI-related functions
# such as menus, messages, and user interaction handlers.

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
    # Docker mode indicator
    if is_docker_setup; then
        print_message $CYAN "       ✨ Docker Mode Active ✨" true
    fi
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
            print_message $CYAN "Attempting to open $CONFIG_FILE for editing..." false
            # Prioritize $EDITOR variable if it is set and points to an executable command
            if [ -n "$EDITOR" ] && command -v "$EDITOR" &> /dev/null; then
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
    print_message $YELLOW "  [2] Create Backup (Dry Run)" false
    print_message $YELLOW "  [3] Restore from Backup" false
    print_message $YELLOW "  [4] Return to Main Menu" false
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
    print_message $YELLOW "  [2] View Auth Server Log ($AUTH_SERVER_LOG_FILENAME)" false # Use variable here
    print_message $YELLOW "  [3] View Server Log ($WORLD_SERVER_LOG_FILENAME)" false   # Use variable here (for Server.log)
    print_message $YELLOW "  [4] View SQL Error Log ($ERROR_LOG_FILENAME)" false  # New entry, use variable
    print_message $YELLOW "  [5] Return to Main Menu" false # Renumbered
    echo ""
    print_message $BLUE "---------------------------------------------------" true
    handle_log_viewer_choice
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
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" log_choice # Updated prompt
    case $log_choice in
        1) view_script_log ;;
        2) view_auth_log ;;
        3) view_world_log ;;
        4) view_error_log ;; # New case
        5) # Return to Main Menu - Updated case number
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-5)." false # Updated message
            ;;
    esac
    # After an action, explicitly call show_log_viewer_menu again
    if [[ "$log_choice" != "5" ]]; then # Updated condition
        show_log_viewer_menu
    fi
}

# Function to handle backup/restore menu choices
handle_backup_restore_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-4]: ${NC}")" backup_choice
    case $backup_choice in
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
            print_message $GREEN "Returning to Main Menu..." false
            return
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-4)." false
            # We can optionally call show_backup_restore_menu again or just let it return
            ;;
    esac
    # After an action, explicitly call show_backup_restore_menu again to re-display it
    # unless the choice was to return to the main menu.
    if [[ "$backup_choice" != "4" ]]; then
        show_backup_restore_menu
    fi
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
