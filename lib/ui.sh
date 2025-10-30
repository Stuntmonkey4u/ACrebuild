#!/bin/bash

# This file contains all the UI-related functions
# such as menus, messages, and user interaction handlers.

# Function to display a welcome message
welcome_message() {
    clear
    print_message "$BLUE" "----------------------------------------------" true
    print_message "$BLUE" "Welcome to ACebuild!           " true
    print_message "$BLUE" "----------------------------------------------" true
    echo ""
    print_message "$BLUE" "This script provides an interactive way to manage your AzerothCore server." true
    echo ""
}

# Function to display the menu
show_menu() {
    echo ""
    print_message "$BLUE" "================== MAIN MENU ==================" true
    if is_docker_setup; then
        print_message "$CYAN" "     ✨ Docker Setup Detected ✨" true
    fi
    if [ "$SCRIPT_UPDATE_AVAILABLE" = true ]; then
        print_message "$YELLOW" "   ✨ An update is available for this script! ✨" true
    fi
    echo ""
    print_message "$YELLOW" "Select an option:" true
    echo ""
    print_message "$CYAN" " Core Actions:" true
    print_message "$YELLOW" "  [1] Rebuild and Run Server" false
    print_message "$YELLOW" "  [2] Rebuild Server Only" false
    echo ""
    print_message "$CYAN" " Management & Tools:" true
    print_message "$YELLOW" "  [3] Module Management" false
    print_message "$YELLOW" "  [4] Server Management" false
    print_message "$YELLOW" "  [5] Log Viewer" false
    print_message "$YELLOW" "  [6] Backup & Restore" false
    print_message "$YELLOW" "  [7] Configuration" false
    local quit_option=8
    if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
        print_message "$YELLOW" "  [8] Self-Update ACrebuild Script" false
        quit_option=9
    fi
    echo ""
    print_message "$CYAN" " Exit:" true
    print_message "$YELLOW" "  [$quit_option] Quit Script" false
    echo ""
    print_message "$BLUE" "-----------------------------------------------" true
}

# Function to check for a potential Docker setup and prompt the user to enable it.
check_and_prompt_for_docker_usage() {
    if [ -f "$AZEROTHCORE_DIR/docker-compose.yml" ] && [ -n "$DOCKER_EXEC_PATH" ] && [ "$USE_DOCKER" = false ]; then
        echo ""
        print_message "$BLUE" "--- Docker Setup Detected ---" true
        print_message "$YELLOW" "A 'docker-compose.yml' file and the 'docker' command were found." false
        print_message "$CYAN" "The script is currently in non-Docker mode." false
        print_message "$YELLOW" "Would you like to enable Docker Mode now? (y/n)" true
        read -r docker_choice
        if [[ "$docker_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_message "$GREEN" "Enabling Docker Mode and saving to configuration..." true
            save_config_value "USE_DOCKER" "true"
            load_config
        else
            print_message "$CYAN" "Keeping Docker Mode disabled. You can enable it later in the Configuration menu." false
        fi
        echo ""
    fi
}

# Function to display current configuration
show_current_configuration() {
    echo ""
    print_message "$BLUE" "---------------- ACTIVE CONFIGURATION ---------------" true
    print_message "$CYAN" "Settings loaded from: $CONFIG_FILE" false
    echo ""
    print_message "$GREEN" " AzerothCore Install Dir: $AZEROTHCORE_DIR" false
    print_message "$GREEN" " Cores for Build:         $CORES" false
    echo ""
    print_message "$GREEN" "  Build Directory:        $BUILD_DIR" false
    echo ""
    print_message "$GREEN" "  Backup Directory:       $BACKUP_DIR" false
    print_message "$GREEN" "  DB User for Backups:    $DB_USER" false
    print_message "$GREEN" "  DB Password for Backups: ${DB_PASS:+****** (set)}" false
    echo ""
    print_message "$BLUE" "----------------------------------------------------" true
    echo ""
}

# Function to display configuration management menu
show_config_management_menu() {
    while true; do
        clear
        echo ""
        print_message "$BLUE" "=========== CONFIGURATION MANAGEMENT MENU ============" true
        local docker_status_msg="DISABLED"
        [ "$USE_DOCKER" = true ] && docker_status_msg="ENABLED"
        print_message "$CYAN" "Docker Mode is currently: $docker_status_msg" false
        echo ""
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] View Current Configuration" false
        print_message "$YELLOW" "  [2] Edit Configuration File" false
        print_message "$YELLOW" "  [3] Toggle Docker Mode" false
        print_message "$YELLOW" "  [4] Validate Current Settings" false
        print_message "$YELLOW" "  [5] Reset Configuration to Defaults" false
        print_message "$YELLOW" "  [6] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "----------------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-6]: ${NC}")" config_choice
        case "$config_choice" in
            1) show_current_configuration ;;
            2)
                if [ -n "${EDITOR-}" ] && command -v "$EDITOR" &> /dev/null; then
                    "$EDITOR" "$CONFIG_FILE"
                elif command -v nano &> /dev/null; then nano "$CONFIG_FILE";
                elif command -v vi &> /dev/null; then vi "$CONFIG_FILE";
                else print_message "$RED" "No suitable text editor found." true; fi
                load_config
                ;;
            3)
                print_message "$YELLOW" "Are you sure you want to toggle Docker Mode? (y/n)" true
                read -r confirm_toggle
                if [[ "$confirm_toggle" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    if [ "$USE_DOCKER" = true ]; then
                        save_config_value "USE_DOCKER" "false"
                        [ "$DB_USER" == "$DEFAULT_DB_USER_DOCKER" ] && save_config_value "DB_USER" "$DEFAULT_DB_USER"
                    else
                        save_config_value "USE_DOCKER" "true"
                        [ "$DB_USER" == "$DEFAULT_DB_USER" ] && save_config_value "DB_USER" "$DEFAULT_DB_USER_DOCKER"
                    fi
                    load_config
                else
                    print_message "$GREEN" "Docker Mode toggle cancelled." false
                fi
                ;;
            4) validate_settings ;;
            5)
                print_message "$RED" "${BOLD}WARNING: This will delete your current configuration file.${NC}" true
                print_message "$YELLOW" "Are you sure you want to proceed? (y/n)" true
                read -r confirm_reset
                if [[ "$confirm_reset" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                    rm -f "$CONFIG_FILE"
                    load_config
                else
                    print_message "$GREEN" "Configuration reset aborted." false
                fi
                ;;
            6) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
        read -n 1 -s -r -p "Press any key to return to Configuration Management menu..."
    done
}


# Function to display backup and restore menu
show_backup_restore_menu() {
    while true; do
        clear
        echo ""
        print_message "$BLUE" "============== BACKUP/RESTORE MENU ==============" true
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] Create Backup" false
        print_message "$YELLOW" "  [2] Create Backup (Dry Run)" false
        print_message "$YELLOW" "  [3] Restore from Backup" false
        print_message "$YELLOW" "  [4] Manage Automated Backups" false
        print_message "$YELLOW" "  [5] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "-----------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" backup_choice
        case "$backup_choice" in
            1) create_backup ;;
            2) create_backup_dry_run ;;
            3) restore_backup ;;
            4) show_automated_backup_menu ;;
            5) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
        if [[ "$backup_choice" != "4" && "$backup_choice" != "5" ]]; then
            read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
        fi
    done
}

# Function to display the automated backup management menu
show_automated_backup_menu() {
    if ! command -v crontab &>/dev/null; then
        print_message "$RED" "Error: 'crontab' command not found." true
        read -n 1 -s -r -p "Press any key to return..."
        return 1
    fi

    check_cron_service
    if [ $? -ne 0 ]; then
        print_message "$RED" "Error: The cron service is not running." true
        read -n 1 -s -r -p "Press any key to return..."
        return 1
    fi

    while true; do
        clear
        print_message "$BLUE" "========== AUTOMATED BACKUP MANAGEMENT ==========" true
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] Setup or Change Schedule" false
        print_message "$YELLOW" "  [2] View Current Schedule" false
        print_message "$YELLOW" "  [3] Disable Automated Backups" false
        print_message "$YELLOW" "  [4] Return to Backup/Restore Menu" false
        echo ""
        print_message "$BLUE" "-----------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-4]: ${NC}")" backup_mgmt_choice
        case "$backup_mgmt_choice" in
            1) setup_backup_schedule ;;
            2) view_backup_schedule ;;
            3) disable_automated_backups ;;
            4) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
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
        print_message "$BLUE" "================== LOG VIEWER MENU ==================" true
        print_message "$YELLOW" "Select a log to view:" true
        print_message "$CYAN" "  Server Logs:" true
        print_message "$YELLOW" "    [1] View Auth Server Log" false
        print_message "$YELLOW" "    [2] Live View Auth Server Log" false
        print_message "$YELLOW" "    [3] View World Server Log" false
        print_message "$YELLOW" "    [4] Live View World Server Log" false
        print_message "$YELLOW" "    [5] View SQL Error Log" false
        echo ""
        print_message "$CYAN" "  Script Logs:" true
        print_message "$YELLOW" "    [6] View Automated Backup Log" false
        echo ""
        print_message "$YELLOW" "  [7] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "---------------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-7]: ${NC}")" log_choice
        case "$log_choice" in
            1) view_auth_log "less" ;;
            2) view_auth_log "tail_f" ;;
            3) view_world_log "less" ;;
            4) view_world_log "tail_f" ;;
            5) view_error_log ;;
            6) view_cron_log ;;
            7) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
    done
}


# Function to display module management menu
show_module_management_menu() {
    while true; do
        clear
        print_message "$BLUE" "============= MODULE MANAGEMENT MENU =============" true
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] Install New Module" false
        print_message "$YELLOW" "  [2] Update Server Modules" false
        print_message "$YELLOW" "  [3] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "-----------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-3]: ${NC}")" module_choice
        case "$module_choice" in
            1) install_module ;;
            2) update_modules "${AZEROTHCORE_DIR}/modules" ;;
            3) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
        if [[ "$module_choice" != "3" ]]; then
            read -n 1 -s -r -p "Press any key to return to Module Management menu..."
        fi
    done
}

# Function to display server management menu
show_server_management_menu() {
    while true; do
        clear
        print_message "$BLUE" "============ SERVER MANAGEMENT MENU ============" true
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] Process Management" false
        print_message "$YELLOW" "  [2] Database Console" false
        print_message "$YELLOW" "  [3] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "-----------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-3]: ${NC}")" server_mgmt_choice
        case "$server_mgmt_choice" in
            1) show_process_management_menu ;;
            2) database_console ;;
            3) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
    done
}

# Function to display process management menu
show_process_management_menu() {
    while true; do
        clear
        print_message "$BLUE" "=========== PROCESS MANAGEMENT MENU ============" true
        print_message "$YELLOW" "Select an option:" true
        print_message "$YELLOW" "  [1] Start Servers" false
        print_message "$YELLOW" "  [2] Stop Servers" false
        print_message "$YELLOW" "  [3] Restart Servers" false
        print_message "$YELLOW" "  [4] Check Server Status" false
        print_message "$YELLOW" "  [5] Return to Main Menu" false
        echo ""
        print_message "$BLUE" "-----------------------------------------------" true

        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-5]: ${NC}")" proc_choice
        case "$proc_choice" in
            1) start_servers ;;
            2) stop_servers ;;
            3) restart_servers ;;
            4) check_server_status ;;
            5) break ;;
            *) print_message "$RED" "Invalid choice." false ;;
        esac
        if [[ "$proc_choice" != "5" ]]; then
            read -n 1 -s -r -p "Press any key to return to Process Management menu..."
        fi
    done
}

# Function to handle user input for the main menu.
handle_menu_choice() {
    local max_option=8
    [ "$SCRIPT_IS_GIT_REPO" = true ] && max_option=9

    read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [1-$max_option]: ${NC}")" choice
    case "$choice" in
        1) RUN_SERVER=true; BUILD_ONLY=true ;;
        2) RUN_SERVER=false; BUILD_ONLY=true ;;
        3) show_module_management_menu; return ;;
        4) show_server_management_menu; return ;;
        5) show_log_viewer_menu; return ;;
        6) show_backup_restore_menu; return ;;
        7) show_config_management_menu; return ;;
        8)
            if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
                self_update_script
            else
                print_message "$GREEN" "Exiting." true; exit 0
            fi
            return
            ;;
        9)
            if [ "$SCRIPT_IS_GIT_REPO" = true ]; then
                print_message "$GREEN" "Exiting." true; exit 0
            else
                print_message "$RED" "Invalid choice." false
            fi
            return
            ;;
        *)
            print_message "$RED" "Invalid choice." false
            read -n 1 -s -r -p "Press any key to continue..."
            return
            ;;
    esac
}
