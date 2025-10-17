#!/bin/bash

# Function to provide direct access to the database console
database_console() {
    print_message $BLUE "--- Database Console Access ---" true
    local db_started_by_script=false

    if is_docker_setup; then
        cd "$AZEROTHCORE_DIR" || { print_message $RED "Cannot find AzerothCore directory. Aborting." true; return 1; }
        local db_status
        db_status=$(docker inspect --format="{{.State.Status}}" ac-database 2>/dev/null)

        if [ "$db_status" != "running" ]; then
            print_message $YELLOW "The 'ac-database' container is not running." true
            print_message $YELLOW "Would you like to start it temporarily to access the console? (y/n)" true
            read -r start_db_choice
            if [[ "$start_db_choice" =~ ^[Yy]$ ]]; then
                print_message $CYAN "Starting 'ac-database' container..." false
                docker compose up -d ac-database || { print_message $RED "Failed to start ac-database container. Aborting." true; return 1; }
                db_started_by_script=true

                print_message $CYAN "Waiting for database to become healthy (max 120 seconds)..." false
                local health_timer=0
                local max_health_wait=120
                while true; do
                    local health_status=$(docker inspect --format="{{.State.Health.Status}}" ac-database 2>/dev/null)
                    if [ "$health_status" = "healthy" ]; then
                        print_message $GREEN "Database is healthy." false
                        break
                    fi
                    health_timer=$((health_timer + 1))
                    if [ "$health_timer" -gt "$max_health_wait" ]; then
                        print_message $RED "Database did not become healthy within $max_health_wait seconds. Aborting." true
                        if [ "$db_started_by_script" = true ]; then docker compose stop ac-database &>/dev/null; fi
                        return 1
                    fi
                    sleep 1
                    echo -ne "${CYAN}Waiting... (Status: ${health_status:-'unknown'}, Time: ${health_timer}s)${NC}  "
                done
                echo ""
            else
                print_message $RED "Cannot open console: database container is not running." true
                return 1
            fi
        fi

        print_message $CYAN "Attempting to open a shell to the 'ac-database' container..." false
        print_message $YELLOW "You will be connected to the MySQL shell. Type 'exit' to return." true
        sleep 1
        docker compose exec ac-database mysql -u"$DB_USER" -p

    else
        print_message $CYAN "Attempting to open a local MySQL shell..." false
        if ! command -v mysql &>/dev/null; then
            print_message $RED "The 'mysql' command is not available on your system. Please install it." true
            return 1
        fi
        print_message $YELLOW "You will be prompted for the password for user '$DB_USER'." true
        print_message $YELLOW "Type 'exit' to return to the script." true
        sleep 1
        mysql -u"$DB_USER" -p
    fi

    if [ "$db_started_by_script" = true ]; then
        print_message $CYAN "Stopping 'ac-database' container as it was started for the console session..." false
        docker compose stop ac-database || print_message $RED "Warning: Failed to stop ac-database container." false
        print_message $GREEN "Container 'ac-database' stopped." false
    fi

    print_message $GREEN "Exited database console." true
}
