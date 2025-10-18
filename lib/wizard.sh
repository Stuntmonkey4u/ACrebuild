#!/bin/bash

# Function to run the first-time setup wizard
run_setup_wizard() {
    clear
    print_message $BLUE "--- Welcome to the ACrebuild Setup Wizard ---" true
    print_message $CYAN "It looks like this is your first time running the script." false
    print_message $CYAN "Let's configure some basic settings." false
    echo ""

    # 1. Ask for Installation Path
    local ac_dir
    while true; do
        print_message $YELLOW "Where is your AzerothCore source code located?" true
        print_message $CYAN "Default: $DEFAULT_AZEROTHCORE_DIR" false
        read -p "Enter path or press ENTER for default: " ac_dir
        ac_dir=${ac_dir:-$DEFAULT_AZEROTHCORE_DIR}
        if [ -d "$ac_dir" ]; then
            print_message $GREEN "Directory found." false
            break
        else
            print_message $YELLOW "Directory not found. Do you want to use this path anyway?" true
            read -p "It might be a new clone location. (y/n): " confirm_path
            if [[ "$confirm_path" =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    done
    AZEROTHCORE_DIR="$ac_dir" # Set runtime variable
    echo ""

    # 2. Ask about Docker Mode
    if [ -f "$AZEROTHCORE_DIR/docker-compose.yml" ]; then
        print_message $YELLOW "We detected a 'docker-compose.yml' file." true
        print_message $YELLOW "Do you want to run in Docker Mode? (y/n)" true
        read -p "Enter choice [y]: " docker_choice
        if [[ "$docker_choice" =~ ^[Yy]?$ ]]; then # Default to yes
            USE_DOCKER=true
        else
            USE_DOCKER=false
        fi
    else
         USE_DOCKER=false
    fi
    echo ""

    # 3. Ask for Database User
    if [ "$USE_DOCKER" = true ]; then
        print_message $YELLOW "What is the database user for your Docker setup?" true
        print_message $CYAN "Default: $DEFAULT_DB_USER_DOCKER" false
        read -p "Enter user or press ENTER for default: " db_user_input
        DB_USER=${db_user_input:-$DEFAULT_DB_USER_DOCKER}
    else
        print_message $YELLOW "What is your local database user?" true
        print_message $CYAN "Default: $DEFAULT_DB_USER" false
        read -p "Enter user or press ENTER for default: " db_user_input
        DB_USER=${db_user_input:-$DEFAULT_DB_USER}
    fi
    echo ""

    # 4. Ask for Backup Directory
    print_message $YELLOW "Where should backups be stored?" true
    print_message $CYAN "Default: $DEFAULT_BACKUP_DIR" false
    read -p "Enter path or press ENTER for default: " backup_dir_input
    BACKUP_DIR=${backup_dir_input:-$DEFAULT_BACKUP_DIR}

    # 5. Set remaining variables to defaults before saving
    DB_PASS="$DEFAULT_DB_PASS"
    AUTH_DB_NAME="$DEFAULT_AUTH_DB_NAME"
    CHAR_DB_NAME="$DEFAULT_CHAR_DB_NAME"
    WORLD_DB_NAME="$DEFAULT_WORLD_DB_NAME"
    SCRIPT_LOG_DIR="$DEFAULT_SCRIPT_LOG_DIR"
    SCRIPT_LOG_FILENAME="$DEFAULT_SCRIPT_LOG_FILENAME"
    AUTH_SERVER_LOG_FILENAME="$DEFAULT_AUTH_SERVER_LOG_FILENAME"
    WORLD_SERVER_LOG_FILENAME="$DEFAULT_WORLD_SERVER_LOG_FILENAME"
    ERROR_LOG_FILENAME="$DEFAULT_ERROR_LOG_FILENAME"
    POST_SHUTDOWN_DELAY_SECONDS="$DEFAULT_POST_SHUTDOWN_DELAY_SECONDS"
    CORES="$DEFAULT_CORES_FOR_BUILD"

    # 6. Save all collected settings
    save_config

    echo ""
    print_message $GREEN "--- Initial Setup Complete! ---" true
    print_message $CYAN "Your settings have been saved to $CONFIG_FILE" false
    print_message $CYAN "You can change these settings later from the Configuration menu." false
    sleep 2
}
