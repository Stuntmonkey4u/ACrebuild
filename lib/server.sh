#!/bin/bash

start_servers() {
    if is_docker_setup; then
        print_message "$BLUE" "--- Attempting to Start Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose up -d)
        print_message "$GREEN" "Docker containers started. Use 'Check Server Status' to see their state." true
    else
        print_message "$BLUE" "--- Attempting to Start AzerothCore Servers (TMUX) ---" true
        if ! command -v tmux &> /dev/null; then
            print_message "$RED" "TMUX is not installed. Please install it to manage servers." true
            return 1
        fi

        local auth_exec_path="$AZEROTHCORE_DIR/env/dist/bin/authserver"
        local world_exec_path="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
        local server_bin_dir="$AZEROTHCORE_DIR/env/dist/bin"

        if [ ! -f "$auth_exec_path" ]; then
            print_message "$RED" "Authserver executable not found at $auth_exec_path" true
            return 1
        fi
        if [ ! -f "$world_exec_path" ]; then
            print_message "$RED" "Worldserver executable not found at $world_exec_path" true
            return 1
        fi

        if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message "$YELLOW" "TMUX session '$TMUX_SESSION_NAME' already exists." false
            local pane_count
            pane_count=$(tmux list-panes -t "$TMUX_SESSION_NAME:0" 2>/dev/null | wc -l)
            if [ "$pane_count" -eq 2 ]; then
                print_message "$GREEN" "TMUX session appears to have a valid 2-pane layout." false
                return 2
            else
                print_message "$RED" "Session '$TMUX_SESSION_NAME' exists but is not in the expected 2-pane configuration." true
                return 1
            fi
        else
            print_message "$CYAN" "Creating new TMUX session '$TMUX_SESSION_NAME'..." false
            tmux new-session -s "$TMUX_SESSION_NAME" -d
            sleep 1
            tmux select-pane -t "$TMUX_SESSION_NAME:0.0" -T "$AUTHSERVER_PANE_TITLE"
            tmux send-keys -t "$TMUX_SESSION_NAME:0.0" "cd '$server_bin_dir' && PROMPT_COMMAND='' '$auth_exec_path'" C-m

            print_message "$CYAN" "Waiting for authserver to be ready on port $AUTH_PORT..." false
            local spinner=('\' '|' '/' '-')
            for i in {1..60}; do
                echo -ne "${CYAN}Checking port... ${spinner[$((i % ${#spinner[@]}))]} \r${NC}"
                nc -z localhost "$AUTH_PORT" && break
                sleep 1
            done
            echo ""

            if ! nc -z localhost "$AUTH_PORT"; then
                print_message "$RED" "Authserver did not become ready on port $AUTH_PORT." true
                tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
                return 1
            fi
            print_message "$GREEN" "Authserver is ready." true

            tmux split-window -h -t "$TMUX_SESSION_NAME:0.0"
            sleep 1
            tmux select-pane -t "$TMUX_SESSION_NAME:0.1" -T "$WORLDSERVER_PANE_TITLE"
            tmux send-keys -t "$TMUX_SESSION_NAME:0.1" "cd '$server_bin_dir' && PROMPT_COMMAND='' '$world_exec_path'" C-m

            print_message "$CYAN" "Waiting for worldserver to be ready on port $WORLD_PORT..." false
            for i in {1..60}; do
                echo -ne "${CYAN}Checking port... ${spinner[$((i % ${#spinner[@]}))]} \r${NC}"
                if nc -z localhost "$WORLD_PORT" &>/dev/null; then
                    break
                fi
                sleep 1
            done
            echo ""

            if ! nc -z localhost "$WORLD_PORT" &>/dev/null; then
                print_message "$RED" "Worldserver did not become ready on port $WORLD_PORT." true
                return 1
            fi
            print_message "$GREEN" "Worldserver is ready." true
        fi

        echo ""
        print_message "$CYAN" "----------------------------------------------------------" true
        print_message "$WHITE" "  Servers are running in TMUX session '$TMUX_SESSION_NAME'." true
        print_message "$YELLOW" "  To attach: tmux attach -t $TMUX_SESSION_NAME" false
        print_message "$CYAN" "----------------------------------------------------------" true
        echo ""
    fi
    return 0
}

stop_servers() {
    if is_docker_setup; then
        print_message "$BLUE" "--- Attempting to Stop Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose down)
        print_message "$GREEN" "Docker containers stopped." true
    else
        print_message "$BLUE" "--- Attempting to Stop AzerothCore Servers (TMUX) ---" true
        if ! command -v tmux &> /dev/null; then
            print_message "$RED" "TMUX is not installed. Cannot manage servers." true
            return 1
        fi

        if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message "$YELLOW" "TMUX session '$TMUX_SESSION_NAME' not found. Servers are likely not running." false
            return 0
        fi

        print_message "$CYAN" "TMUX session '$TMUX_SESSION_NAME' found." false
        local world_target_pane="$TMUX_SESSION_NAME:0.1"
        if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then
            print_message "$YELLOW" "Sending graceful shutdown to Worldserver pane..." false
            tmux send-keys -t "$world_target_pane" "$WORLDSERVER_CONSOLE_COMMAND_STOP" C-m

            print_message "$CYAN" "Waiting for Worldserver to shut down..." false
            local shutdown_timer=0
            while nc -z localhost "$WORLD_PORT" &>/dev/null; do
                shutdown_timer=$((shutdown_timer + 1))
                if [ "$shutdown_timer" -gt 300 ]; then
                    print_message "$RED" "Worldserver did not shut down within 5 minutes." true
                    break
                fi
                sleep 1
            done
            if ! nc -z localhost "$WORLD_PORT" &>/dev/null; then
                print_message "$GREEN" "Worldserver has shut down." false
            fi
            sleep "$POST_SHUTDOWN_DELAY_SECONDS"
        fi

        print_message "$YELLOW" "Killing TMUX session '$TMUX_SESSION_NAME'..." false
        tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
        print_message "$GREEN" "Server stop process completed." true
    fi
    return 0
}

restart_servers() {
    if is_docker_setup; then
        print_message "$BLUE" "--- Attempting to Restart/Start Docker Containers ---" true
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose restart)
        print_message "$GREEN" "Docker containers restart command issued." true
    else
        print_message "$BLUE" "--- Attempting to Restart AzerothCore Servers (TMUX) ---" true
        stop_servers
        if [ $? -ne 0 ]; then
            print_message "$RED" "Server stop phase failed. Aborting restart." true
            return 1
        fi
        print_message "$CYAN" "Waiting for 10 seconds before starting servers again..." true
        sleep 10
        start_servers
        if [ $? -ne 0 ]; then
            print_message "$RED" "Server start phase failed. Please check messages." true
            return 1
        fi
        print_message "$GREEN" "Server restart process initiated." true
    fi
    return 0
}

check_server_status() {
    clear
    print_message "$BLUE" "==========================================================" true
    print_message "$BLUE" "               SERVER STATUS DASHBOARD                    " true
    print_message "$BLUE" "==========================================================" true
    echo ""

    # 1. Environment Type
    if is_docker_setup; then
        print_message "$CYAN" "Environment Type : " false; echo -e "${GREEN}Docker${NC}"
    else
        print_message "$CYAN" "Environment Type : " false; echo -e "${YELLOW}Standard (TMUX)${NC}"
    fi

    # 2. Database Connection
    local db_status="${RED}Disconnected${NC}"
    if is_docker_setup; then
        if (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose exec -T -e MYSQL_PWD="$(get_secure_db_pass)" ac-database mysql -u"$DB_USER" -e "QUIT" &>/dev/null); then
            db_status="${GREEN}Connected${NC}"
        fi
    else
        if MYSQL_PWD="$(get_secure_db_pass)" mysql -u"$DB_USER" -e "QUIT" &>/dev/null; then
            db_status="${GREEN}Connected${NC}"
        fi
    fi
    print_message "$CYAN" "Database Status  : " false; echo -e "$db_status"

    # 3. Last Backup Time
    local last_backup="${YELLOW}None Found${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        local latest_backup_file=$(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)
        if [ -n "$latest_backup_file" ]; then
            last_backup=$(date -r "$latest_backup_file" +"%Y-%m-%d %H:%M:%S")
            last_backup="${GREEN}${last_backup}${NC}"
        fi
    fi
    print_message "$CYAN" "Last Backup      : " false; echo -e "$last_backup"
    echo ""

    # 4. Process & Port Status
    print_message "$BLUE" "--- Container / Process Status ---" true
    if is_docker_setup; then
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose ps)
    else
        if ! command -v tmux &> /dev/null; then
            print_message "$RED" "TMUX is not installed." true
        else
            if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
                print_message "$GREEN" "TMUX Session '$TMUX_SESSION_NAME' is running." false
            else
                print_message "$YELLOW" "TMUX session '$TMUX_SESSION_NAME' is not running." false
            fi
        fi

        local auth_port_listening=false
        if nc -z localhost "$AUTH_PORT" &>/dev/null; then auth_port_listening=true; fi

        local world_port_listening=false
        if nc -z localhost "$WORLD_PORT" &>/dev/null; then world_port_listening=true; fi

        if $auth_port_listening; then
            print_message "$GREEN" "Authserver (Port $AUTH_PORT) : Listening" false
        else
            print_message "$RED" "Authserver (Port $AUTH_PORT) : Offline" false
        fi

        if $world_port_listening; then
            print_message "$GREEN" "Worldserver (Port $WORLD_PORT): Listening" false
        else
            print_message "$RED" "Worldserver (Port $WORLD_PORT): Offline" false
        fi
    fi

    echo ""
    print_message "$BLUE" "==========================================================" true
    print_message "$YELLOW" "Press ENTER to return to the menu..." false
    read -r
    return 0
}

run_tmux_session() {
    clear
    echo ""
    start_servers
    if [ $? -ne 0 ]; then
        print_message "$RED" "Server startup failed." true
        exit 1
    fi
    exit 0
}

ask_for_update_confirmation() {
    print_message "$BLUE" "--- Build Preparation ---" true

    local servers_running=false
    if is_docker_setup; then
        # For Docker setups, we check if core containers are running.
        if is_container_running "ac-database" || is_container_running "ac-worldserver" || is_container_running "ac-authserver"; then
            servers_running=true
        fi
    else
        # For standard setups, we check for an active TMUX session.
        if command -v tmux &> /dev/null && tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            servers_running=true
        fi
    fi

    if [ "$servers_running" = true ]; then
        print_message "$YELLOW" "Servers appear to be running." true
        print_message "$YELLOW" "It is strongly recommended to stop them before rebuilding." true
        print_message "$YELLOW" "Would you like to attempt to stop the servers now? (y/n)" true
        read -r stop_choice
        if [[ "$stop_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            if stop_servers; then
                print_message "$GREEN" "Servers stopped successfully." true
            else
                # stop_servers returns a non-zero exit code if it fails
                print_message "$RED" "Failed to stop servers. Rebuild aborted." true
                return 1
            fi
        else
            print_message "$RED" "User chose not to stop servers. Rebuild aborted." true
            return 1
        fi
    else
        print_message "$GREEN" "Servers appear to be stopped." false
    fi

    echo ""
    while true; do
        print_message "$YELLOW" "Would you like to update the AzerothCore source code before rebuilding? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]([Oo])?$ ]]; then
            print_message "$GREEN" "Skipping source code update." true
            break
        else
            print_message "$RED" "Invalid input. Please enter 'y' or 'n'." false
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
    print_message "$YELLOW" "CPU Core Selection for Building" true
    print_message "$CYAN" "Currently configured cores for build: ${current_cores_for_build:-Not Set}" false
    print_message "$YELLOW" "Available CPU cores on this system: $available_cores_system" false
    print_message "$YELLOW" "Press ENTER to use default ($available_cores_system), or enter a number:" false
    read -r user_cores_input

    local new_cores_value=""
    if [ -z "$user_cores_input" ]; then
        new_cores_value=$available_cores_system
    elif ! [[ "$user_cores_input" =~ ^[0-9]+$ ]] || [ "$user_cores_input" -eq 0 ] || [ "$user_cores_input" -gt "$available_cores_system" ]; then
        print_message "$RED" "Invalid input. Using $available_cores_system cores." true
        new_cores_value=$available_cores_system
    else
        new_cores_value="$user_cores_input"
    fi

    CORES="$new_cores_value"
    print_message "$GREEN" "Using $CORES core(s) for this session." true

    if [ "$new_cores_value" -gt 1 ]; then
        local total_ram_gb
        total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$total_ram_gb" -lt 4 ]; then
            print_message "$YELLOW" "WARNING: Compiling with multiple cores ($new_cores_value) on a system with less than 4GB RAM may cause Out-Of-Memory (OOM) crashes." true
        fi
    fi


    if [ "$new_cores_value" != "$current_cores_for_build" ]; then
        print_message "$YELLOW" "Save $new_cores_value cores to configuration? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            save_config_value "CORES_FOR_BUILD" "$new_cores_value"
        fi
    fi
    echo ""
}


patch_apt_sources_to_https() {
    print_message "$CYAN" "Patching Dockerfiles to use HTTPS for APT repositories to prevent build failures..." false

    if [ -d "$AZEROTHCORE_DIR/apps/docker" ]; then
        # Replace hardcoded http strings directly in the Dockerfile text
        find "$AZEROTHCORE_DIR/apps/docker" -type f -name "Dockerfile*" -exec sed -i 's|http://archive.ubuntu.com|https://archive.ubuntu.com|g' {} +
        find "$AZEROTHCORE_DIR/apps/docker" -type f -name "Dockerfile*" -exec sed -i 's|http://security.ubuntu.com|https://security.ubuntu.com|g' {} +
        find "$AZEROTHCORE_DIR/apps/docker" -type f -name "Dockerfile*" -exec sed -i 's|http://ports.ubuntu.com|https://ports.ubuntu.com|g' {} +

        # Inject a RUN command immediately after FROM to catch base image DEB822 and legacy sources
        # We also need to target ubuntu.sources specifically.
        local sed_cmd="RUN sed -i 's/http:/https:/g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null || true"

        find "$AZEROTHCORE_DIR/apps/docker" -type f -name "Dockerfile*" | while read -r df; do
            if ! grep -q "ubuntu.sources" "$df"; then
                awk -v cmd="$sed_cmd" '/^FROM/ && !inserted {print; print cmd; inserted=1; next} {print}' "$df" > "$df.tmp" && mv "$df.tmp" "$df"
            fi
        done
    fi
}

build_and_install_with_spinner() {

    local max_retries=1
    local retries=0
    local no_cache=false
    if [ "${1-}" == "--no-cache" ]; then
        no_cache=true
    fi


    while [ $retries -le $max_retries ]; do
        echo ""
        print_message "$BLUE" "--- Starting AzerothCore Build and Installation ---" true
        print_message "$YELLOW" "This may take a while..." true

        patch_apt_sources_to_https

        local build_success=true


        if is_docker_setup; then
            print_message "$CYAN" "Running Docker build..." true
            if [ "$no_cache" = true ]; then
                (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose build --no-cache) || build_success=false
            else
                (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose build) || build_success=false
            fi
        else
            if [ ! -d "$BUILD_DIR" ]; then
                handle_error "Build directory $BUILD_DIR does not exist."
            fi

            (
                cd "$BUILD_DIR" || return 1
                echo ""
                print_message "$CYAN" "Running CMake configuration..." true
                cmake ../ -DCMAKE_INSTALL_PREFIX="$AZEROTHCORE_DIR/env/dist/" -DCMAKE_C_COMPILER="$CMAKE_C_COMPILER" -DCMAKE_CXX_COMPILER="$CMAKE_CXX_COMPILER" $CMAKE_BUILD_FLAGS || return 1

                echo ""
                print_message "$CYAN" "Running make install with $CORES core(s)..." true
                make -j "$CORES" install || return 1
            )
            if [ $? -ne 0 ]; then
                build_success=false
            fi
        fi

        if [ "$build_success" = true ]; then
            print_message "$GREEN" "--- AzerothCore Build and Installation Completed Successfully ---" true
            return 0
        fi

        if [ $retries -eq $max_retries ]; then
            handle_error "Build process failed repeatedly."
        fi

        print_message "$RED" "ERROR: Build process failed." true
        if [ -n "$PREVIOUS_COMMIT_HASH" ]; then
            print_message "$YELLOW" "Would you like to rollback to the previous commit ($PREVIOUS_COMMIT_HASH) before the update?" true
            run_countdown_timer 120
            if [ $? -eq 0 ]; then
                print_message "$CYAN" "Rolling back..." true
                git -C "$AZEROTHCORE_DIR" reset --hard "$PREVIOUS_COMMIT_HASH"
                print_message "$GREEN" "Rollback complete." true
                return 1
            fi
        fi

        if is_docker_setup; then
            print_message "$YELLOW" "A Docker build failure occurred. Would you like to try rebuilding with the '--no-cache' option?" true
        else
            print_message "$YELLOW" "A build failure occurred. Would you like to run 'make clean' to try and fix it?" true
        fi

        run_countdown_timer 900 # 15 minutes
        local countdown_result=$?

        if [ "$countdown_result" -eq 0 ]; then # User chose 'yes' or timed out
            retries=$((retries + 1))
            if is_docker_setup; then
                print_message "$GREEN" "Attempting to rebuild with '--no-cache'..." true
                no_cache=true
            else
                print_message "$GREEN" "Running 'make clean'..." true
                if [ -d "$BUILD_DIR" ]; then
                    (cd "$BUILD_DIR" && make clean) || print_message "$RED" "Warning: 'make clean' encountered an error." false
                fi
            fi
        else
            handle_error "Build process failed. User skipped retry."
        fi
    done
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