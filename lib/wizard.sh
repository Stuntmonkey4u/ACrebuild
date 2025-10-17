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
    save_config_value "AZEROTHCORE_DIR" "$ac_dir"
    echo ""

    # 2. Ask about Docker Mode
    local use_docker
    if [ -f "$ac_dir/docker-compose.yml" ]; then
        print_message $YELLOW "We detected a 'docker-compose.yml' file." true
        print_message $YELLOW "Do you want to run in Docker Mode? (y/n)" true
        read -p "Enter choice: " docker_choice
        if [[ "$docker_choice" =~ ^[Yy]$ ]]; then
            use_docker=true
        else
            use_docker=false
        fi
    else
         use_docker=false
    fi
    save_config_value "USE_DOCKER" "$use_docker"
    echo ""

    # 3. Ask for Database User
    local db_user
    if [ "$use_docker" = true ]; then
        print_message $YELLOW "What is the database user for your Docker setup?" true
        print_message $CYAN "Default: $DEFAULT_DB_USER_DOCKER" false
        read -p "Enter user or press ENTER for default: " db_user
        db_user=${db_user:-$DEFAULT_DB_USER_DOCKER}
    else
        print_message $YELLOW "What is your local database user?" true
        print_message $CYAN "Default: $DEFAULT_DB_USER" false
        read -p "Enter user or press ENTER for default: " db_user
        db_user=${db_user:-$DEFAULT_DB_USER}
    fi
    save_config_value "DB_USER" "$db_user"
    echo ""

    # 4. Ask for Backup Directory
    local backup_dir
    print_message $YELLOW "Where should backups be stored?" true
    print_message $CYAN "Default: $DEFAULT_BACKUP_DIR" false
    read -p "Enter path or press ENTER for default: " backup_dir
    backup_dir=${backup_dir:-$DEFAULT_BACKUP_DIR}
    save_config_value "BACKUP_DIR" "$backup_dir"

    # 5. Silently save the current PATH for cron jobs
    save_config_value "CRON_PATH" "$PATH"

    echo ""
    print_message $GREEN "--- Initial Setup Complete! ---" true
    print_message $CYAN "Your settings have been saved to $CONFIG_FILE" false
    print_message $CYAN "You can change these settings later from the Configuration menu." false
    sleep 2
}
