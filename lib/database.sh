#!/bin/bash

# Function to provide direct access to the database console
database_console() {
    print_message $BLUE "--- Database Console Access ---" true

    if is_docker_setup; then
        print_message $CYAN "Attempting to open a shell to the 'ac-database' container..." false
        cd "$AZEROTHCORE_DIR" || { print_message $RED "Cannot find AzerothCore directory. Aborting." true; return 1; }

        # Check if the database container is running
        local db_status
        db_status=$(docker inspect --format="{{.State.Status}}" ac-database 2>/dev/null)
        if [ "$db_status" != "running" ]; then
            print_message $RED "The 'ac-database' container is not running. Cannot open console." true
            return 1
        fi

        print_message $YELLOW "You will be connected to the MySQL shell in the Docker container." true
        print_message $YELLOW "Type 'exit' to return to the script." true
        sleep 2
        docker compose exec ac-database mysql -u"$DB_USER" -p
    else
        print_message $CYAN "Attempting to open a local MySQL shell..." false
        if ! command -v mysql &>/dev/null; then
            print_message $RED "The 'mysql' command is not available on your system. Please install it." true
            return 1
        fi

        print_message $YELLOW "You will be connected to the local MySQL shell." true
        print_message $YELLOW "You will be prompted for the password for user '$DB_USER'." true
        print_message $YELLOW "Type 'exit' to return to the script." true
        sleep 2
        mysql -u"$DB_USER" -p
    fi

    print_message $GREEN "Exited database console." true
}
