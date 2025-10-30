#!/bin/bash

# Helper function to ensure the database container is running for an operation
# Returns 0 if the DB is ready.
# Returns 1 if the user aborts or an error occurs.
# Returns 2 if the DB was started by this function, to signal cleanup is needed.
ensure_db_is_running() {
    local non_interactive=false
    if [ "${1-}" == "--non-interactive" ]; then
        non_interactive=true
    fi

    if ! is_docker_setup; then
        return 0
    fi

    local db_status
    db_status=$("$DOCKER_EXEC_PATH" inspect --format="{{.State.Status}}" ac-database 2>/dev/null)

    if [ "$db_status" = "running" ]; then
        return 0
    fi

    if [ "$non_interactive" = true ]; then
        print_message $CYAN "Database container is not running. Starting it for non-interactive task..." true
    else
        print_message $YELLOW "The 'ac-database' container is not running." true
        print_message $YELLOW "It must be running for this operation. Would you like to start it temporarily? (y/n)" true
        read -r start_db_choice
        if [[ ! "$start_db_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_message $RED "Operation aborted by user because database container is not running." true
            return 1
        fi
    fi

    print_message $CYAN "Starting 'ac-database' container..." false
    (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose up -d ac-database) || { print_message $RED "Failed to start ac-database container. Aborting." true; return 1; }

    print_message $CYAN "Waiting for database to become healthy (max 120 seconds)..." false
    local health_timer=0
    local max_health_wait=120
    while true; do
        local health_status
        health_status=$("$DOCKER_EXEC_PATH" inspect --format="{{.State.Health.Status}}" ac-database 2>/dev/null)
        if [ "$health_status" = "healthy" ]; then
            print_message $GREEN "Database is healthy." false
            return 2
        fi

        health_timer=$((health_timer + 1))
        if [ "$health_timer" -gt "$max_health_wait" ]; then
            print_message $RED "Database did not become healthy within $max_health_wait seconds. Aborting." true
            (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose stop ac-database &>/dev/null)
            return 1
        fi
        sleep 1
        echo -ne "${CYAN}Waiting... (Status: ${health_status:-'unknown'}, Time: ${health_timer}s)${NC}  \r"
    done
    echo ""
}

# Function to provide direct access to the database console
database_console() {
    print_message $BLUE "--- Database Console Access ---" true
    local db_started_by_script=false

    ensure_db_is_running
    local db_check_result=$?

    if [ $db_check_result -eq 1 ]; then
        return 1
    elif [ $db_check_result -eq 2 ]; then
        db_started_by_script=true
    fi

    if is_docker_setup; then
        print_message $CYAN "Attempting to open a shell to the 'ac-database' container..." false
        print_message $YELLOW "You will be connected to the MySQL shell. Type 'exit' to return." true
        sleep 1
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose exec ac-database mysql -u"$DB_USER" -p)
    else
        print_message $CYAN "Attempting to open a local MySQL shell..." false
        if ! command -v mysql &>/dev/null; then
            print_message $RED "The 'mysql' command is not available on your system. Please install it." true
            return 1
        fi
        print_message $YELLOW "You will be prompted for the password for user '$DB_USER'." true
        sleep 1
        mysql -u"$DB_USER" -p
    fi

    if [ "$db_started_by_script" = true ]; then
        print_message $CYAN "Stopping 'ac-database' container as it was started for the console session..." false
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose stop ac-database) || print_message $RED "Warning: Failed to stop ac-database container." false
        print_message $GREEN "Container 'ac-database' stopped." false
    fi

    print_message $GREEN "Exited database console." true
}
