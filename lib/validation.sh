#!/bin/bash

# Function to validate the current settings
validate_settings() {
    print_message $BLUE "--- Validating Current Settings ---" true
    local all_ok=true

    # 1. Validate AzerothCore Directory
    print_message $CYAN "Checking AzerothCore directory..." false
    if [ -d "$AZEROTHCORE_DIR" ]; then
        print_message $GREEN "  [OK] AzerothCore directory found at $AZEROTHCORE_DIR" false
    else
        print_message $RED "  [FAIL] AzerothCore directory not found at $AZEROTHCORE_DIR" false
        all_ok=false
    fi

    # 2. Validate Backup Directory
    print_message $CYAN "Checking Backup directory..." false
    if [ -d "$BACKUP_DIR" ]; then
        print_message $GREEN "  [OK] Backup directory found at $BACKUP_DIR" false
    else
        print_message $YELLOW "  [WARN] Backup directory not found at $BACKUP_DIR. It will be created on first backup." false
    fi

    # 3. Validate Database Connection
    print_message $CYAN "Checking Database connection..." false
    local db_started_by_script=false
    ensure_db_is_running
    local db_check_result=$?

    if [ $db_check_result -eq 1 ]; then
        print_message $RED "  [FAIL] Could not ensure database is running. Aborting validation." false
        all_ok=false
    else
        if [ $db_check_result -eq 2 ]; then
            db_started_by_script=true
        fi

        local effective_db_pass="$DB_PASS"
        if [ -z "$effective_db_pass" ]; then
            print_message $YELLOW "Database password is not saved. Please enter it for validation:" true
            read -s effective_db_pass
            echo ""
        fi

        # Try to connect
        if is_docker_setup; then
            docker compose exec -T -e MYSQL_PWD="$effective_db_pass" ac-database mysql -u"$DB_USER" -e "QUIT" &>/dev/null
        else
            MYSQL_PWD="$effective_db_pass" mysql -u"$DB_USER" -e "QUIT" &>/dev/null
        fi

        if [ $? -eq 0 ]; then
            print_message $GREEN "  [OK] Database connection successful for user '$DB_USER'." false
        else
            print_message $RED "  [FAIL] Database connection failed for user '$DB_USER'. Please check credentials." false
            all_ok=false
        fi
    fi

    if [ "$db_started_by_script" = true ]; then
        print_message $CYAN "Stopping database container that was started for validation..." false
        docker compose stop ac-database &>/dev/null
    fi

    # --- Final Summary ---
    echo ""
    if [ "$all_ok" = true ]; then
        print_message $GREEN "--- Validation Complete: All checks passed! ---" true
    else
        print_message $RED "--- Validation Complete: One or more checks failed. ---" true
        print_message $YELLOW "Please review the messages above and correct your settings in the Configuration menu." true
    fi
}
