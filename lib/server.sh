#!/bin/bash

start_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Start Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose up -d)
        print_message $GREEN "Docker containers started. Use 'Check Server Status' to see their state." true
    else
        print_message $BLUE "--- Attempting to Start AzerothCore Servers (TMUX) ---" true
        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed. Please install it to manage servers." true
            return 1
        fi

        local auth_exec_path="$AZEROTHCORE_DIR/env/dist/bin/authserver"
        local world_exec_path="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
        local server_bin_dir="$AZEROTHCORE_DIR/env/dist/bin"

        if [ ! -f "$auth_exec_path" ]; then
            print_message $RED "Authserver executable not found at $auth_exec_path" true
            return 1
        fi
        if [ ! -f "$world_exec_path" ]; then
            print_message $RED "Worldserver executable not found at $world_exec_path" true
            return 1
        fi

        if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' already exists." false
            local pane_count
            pane_count=$(tmux list-panes -t "$TMUX_SESSION_NAME:0" 2>/dev/null | wc -l)
            if [ "$pane_count" -eq 2 ]; then
                print_message $GREEN "TMUX session appears to have a valid 2-pane layout." false
                return 2
            else
                print_message $RED "Session '$TMUX_SESSION_NAME' exists but is not in the expected 2-pane configuration." true
                return 1
            fi
        else
            print_message $CYAN "Creating new TMUX session '$TMUX_SESSION_NAME'..." false
            tmux new-session -s "$TMUX_SESSION_NAME" -d
            sleep 1
            tmux select-pane -t "$TMUX_SESSION_NAME:0.0" -T "$AUTHSERVER_PANE_TITLE"
            tmux send-keys -t "$TMUX_SESSION_NAME:0.0" "cd '$server_bin_dir' && PROMPT_COMMAND='' '$auth_exec_path'" C-m

            print_message $CYAN "Waiting for authserver to be ready on port $AUTH_PORT..." false
            local spinner=('\' '|' '/' '-')
            for i in {1..60}; do
                echo -ne "${CYAN}Checking port... ${spinner[$((i % ${#spinner[@]}))]} \r${NC}"
                nc -z localhost "$AUTH_PORT" && break
                sleep 1
            done
            echo ""

            if ! nc -z localhost "$AUTH_PORT"; then
                print_message $RED "Authserver did not become ready on port $AUTH_PORT." true
                tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
                return 1
            fi
            print_message $GREEN "Authserver is ready." true

            tmux split-window -h -t "$TMUX_SESSION_NAME:0.0"
            sleep 1
            tmux select-pane -t "$TMUX_SESSION_NAME:0.1" -T "$WORLDSERVER_PANE_TITLE"
            tmux send-keys -t "$TMUX_SESSION_NAME:0.1" "cd '$server_bin_dir' && PROMPT_COMMAND='' '$world_exec_path'" C-m

            print_message $CYAN "Waiting for worldserver to be ready on port $WORLD_PORT..." false
            for i in {1..60}; do
                echo -ne "${CYAN}Checking port... ${spinner[$((i % ${#spinner[@]}))]} \r${NC}"
                if nc -z localhost "$WORLD_PORT" &>/dev/null; then
                    break
                fi
                sleep 1
            done
            echo ""

            if ! nc -z localhost "$WORLD_PORT" &>/dev/null; then
                print_message $RED "Worldserver did not become ready on port $WORLD_PORT." true
                return 1
            fi
            print_message $GREEN "Worldserver is ready." true
        fi

        echo ""
        print_message $CYAN "----------------------------------------------------------" true
        print_message $WHITE "  Servers are running in TMUX session '$TMUX_SESSION_NAME'." true
        print_message $YELLOW "  To attach: tmux attach -t $TMUX_SESSION_NAME" false
        print_message $CYAN "----------------------------------------------------------" true
        echo ""
    fi
    return 0
}

stop_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Stop Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose down)
        print_message $GREEN "Docker containers stopped." true
    else
        print_message $BLUE "--- Attempting to Stop AzerothCore Servers (TMUX) ---" true
        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed. Cannot manage servers." true
            return 1
        fi

        if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' not found. Servers are likely not running." false
            return 0
        fi

        print_message $CYAN "TMUX session '$TMUX_SESSION_NAME' found." false
        local world_target_pane="$TMUX_SESSION_NAME:0.1"
        if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then
            print_message $YELLOW "Sending graceful shutdown to Worldserver pane..." false
            tmux send-keys -t "$world_target_pane" "$WORLDSERVER_CONSOLE_COMMAND_STOP" C-m

            print_message $CYAN "Waiting for Worldserver to shut down..." false
            local shutdown_timer=0
            while nc -z localhost "$WORLD_PORT" &>/dev/null; do
                shutdown_timer=$((shutdown_timer + 1))
                if [ "$shutdown_timer" -gt 300 ]; then
                    print_message $RED "Worldserver did not shut down within 5 minutes." true
                    break
                fi
                sleep 1
            done
            if ! nc -z localhost "$WORLD_PORT" &>/dev/null; then
                print_message $GREEN "Worldserver has shut down." false
            fi
            sleep "$POST_SHUTDOWN_DELAY_SECONDS"
        fi

        print_message $YELLOW "Killing TMUX session '$TMUX_SESSION_NAME'..." false
        tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
        print_message $GREEN "Server stop process completed." true
    fi
    return 0
}

restart_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Restart/Start Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose restart)
        print_message $GREEN "Docker containers restart command issued." true
    else
        print_message $BLUE "--- Attempting to Restart AzerothCore Servers (TMUX) ---" true
        stop_servers
        if [ $? -ne 0 ]; then
            print_message $RED "Server stop phase failed. Aborting restart." true
            return 1
        fi
        print_message $CYAN "Waiting for 10 seconds before starting servers again..." true
        sleep 10
        start_servers
        if [ $? -ne 0 ]; then
            print_message $RED "Server start phase failed. Please check messages." true
            return 1
        fi
        print_message $GREEN "Server restart process initiated." true
    fi
    return 0
}

check_server_status() {
    if is_docker_setup; then
        print_message $BLUE "--- Checking Docker Container Status ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose ps)
    else
        print_message $BLUE "--- Checking AzerothCore Server Status (TMUX) ---" true
        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed." true
            return 1
        fi

        if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' is not running." false
            return 0
        fi

        print_message $GREEN "TMUX Session '$TMUX_SESSION_NAME' is running." false

        local auth_port_listening=false
        if nc -z localhost "$AUTH_PORT" &>/dev/null; then
            auth_port_listening=true
        fi

        local world_port_listening=false
        if nc -z localhost "$WORLD_PORT" &>/dev/null; then
            world_port_listening=true
        fi

        if $auth_port_listening; then
            print_message $GREEN "Authserver: Port $AUTH_PORT is listening." false
        else
            print_message $RED "Authserver: Port $AUTH_PORT is not listening." false
        fi

        if $world_port_listening; then
            print_message $GREEN "Worldserver: Port $WORLD_PORT is listening." false
        else
            print_message $RED "Worldserver: Port $WORLD_PORT is not listening." false
        fi
    fi
    return 0
}

run_tmux_session() {
    clear
    echo ""
    start_servers
    if [ $? -ne 0 ]; then
        print_message $RED "Server startup failed." true
        exit 1
    fi
    exit 0
}

ask_for_update_confirmation() {
    print_message $BLUE "--- Build Preparation ---" true

    local servers_running=false
    if is_docker_setup; then
        # For Docker setups, we check if the ac-database container is running.
        if is_container_running "ac-database"; then
            servers_running=true
        fi
    else
        # For standard setups, we check for an active TMUX session.
        if command -v tmux &> /dev/null && tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            servers_running=true
        fi
    fi

    if [ "$servers_running" = true ]; then
        print_message $YELLOW "Servers appear to be running." true
        print_message $YELLOW "It is strongly recommended to stop them before rebuilding." true
        print_message $YELLOW "Would you like to attempt to stop the servers now? (y/n)" true
        read -r stop_choice
        if [[ "$stop_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            if stop_servers; then
                print_message $GREEN "Servers stopped successfully." true
            else
                # stop_servers returns a non-zero exit code if it fails
                print_message $RED "Failed to stop servers. Rebuild aborted." true
                return 1
            fi
        else
            print_message $RED "User chose not to stop servers. Rebuild aborted." true
            return 1
        fi
    else
        print_message $GREEN "Servers appear to be stopped." false
    fi

    echo ""
    while true; do
        print_message $YELLOW "Would you like to update the AzerothCore source code before rebuilding? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]([Oo])?$ ]]; then
            print_message $GREEN "Skipping source code update." true
            break
        else
            print_message $RED "Invalid input. Please enter 'y' or 'n'." false
        fi
    done

    ask_for_cores
    return 0
}

ask_for_cores() {
    if is_docker_setup; then
        return
    fi

    local current_cores_for_build="$CORES"
    local available_cores_system=$(nproc)

    echo ""
    print_message $YELLOW "CPU Core Selection for Building" true
    print_message $CYAN "Currently configured cores for build: ${current_cores_for_build:-Not Set}" false
    print_message $YELLOW "Available CPU cores on this system: $available_cores_system" false
    print_message $YELLOW "Press ENTER to use default ($available_cores_system), or enter a number:" false
    read -r user_cores_input

    local new_cores_value=""
    if [ -z "$user_cores_input" ]; then
        new_cores_value=$available_cores_system
    elif ! [[ "$user_cores_input" =~ ^[0-9]+$ ]] || [ "$user_cores_input" -eq 0 ] || [ "$user_cores_input" -gt "$available_cores_system" ]; then
        print_message $RED "Invalid input. Using $available_cores_system cores." true
        new_cores_value=$available_cores_system
    else
        new_cores_value="$user_cores_input"
    fi

    CORES="$new_cores_value"
    print_message $GREEN "Using $CORES core(s) for this session." true

    if [ "$new_cores_value" != "$current_cores_for_build" ]; then
        print_message $YELLOW "Save $new_cores_value cores to configuration? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            save_config_value "CORES_FOR_BUILD" "$new_cores_value"
        fi
    fi
    echo ""
}

build_and_install_with_spinner() {
    echo ""
    print_message $BLUE "--- Starting AzerothCore Build and Installation ---" true
    print_message $YELLOW "This may take a while..." true

    if is_docker_setup; then
        print_message $CYAN "Running Docker build..." true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose build) || handle_error "Docker build failed."
        print_message $GREEN "--- Docker Build Process Completed Successfully ---" true
    else
        if [ ! -d "$BUILD_DIR" ]; then
            handle_error "Build directory $BUILD_DIR does not exist."
        fi

        cd "$BUILD_DIR" || handle_error "Failed to change directory to $BUILD_DIR."

        echo ""
        print_message $CYAN "Running CMake configuration..." true
        cmake ../ -DCMAKE_INSTALL_PREFIX="$AZEROTHCORE_DIR/env/dist/" -DCMAKE_C_COMPILER="$CMAKE_C_COMPILER" -DCMAKE_CXX_COMPILER="$CMAKE_CXX_COMPILER" $CMAKE_BUILD_FLAGS || handle_error "CMake configuration failed."

        echo ""
        print_message $CYAN "Running make install with $CORES core(s)..." true
        make -j "$CORES" install || handle_error "Build process ('make install') failed."
        echo ""
        print_message $GREEN "--- AzerothCore Build and Installation Completed Successfully ---" true
    fi
}

run_authserver() {
    print_message "$YELLOW" "Starting authserver for a quick test..." true

    # Ensure no old authserver process is running
    pkill authserver &>/dev/null
    sleep 2 # Give time for the process to die

    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    "$AUTH_SERVER_EXEC" &
    local auth_server_pid=$!

    print_message "$GREEN" "Waiting for authserver on port $AUTH_PORT..." false
    local server_ready=false
    for i in {1..60}; do
        if nc -z localhost "$AUTH_PORT" &>/dev/null; then
            server_ready=true
            break
        fi
        sleep 1
    done

    if [ "$server_ready" = false ]; then
        # If the server never became ready, the PID might be for a failed process.
        # Try to kill it, but don't error if it's already gone.
        if ps -p $auth_server_pid > /dev/null; then
            kill "$auth_server_pid" &>/dev/null
        fi
        handle_error "Authserver did not start within the expected time frame."
    fi

    print_message "$GREEN" "Authserver is ready! Waiting 5 seconds before closing..." false
    sleep 5

    # Only attempt to kill the process if it's still running
    if ps -p $auth_server_pid > /dev/null; then
        kill "$auth_server_pid"
        wait "$auth_server_pid" 2>/dev/null
    fi

    print_message "$GREEN" "Authserver test shutdown complete." true
}