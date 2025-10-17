#!/bin/bash

is_docker_setup() {
    [ "$USE_DOCKER" = true ]
}

start_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Start Docker Containers ---" true
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose up -d
        print_message $GREEN "Docker containers started. Use 'Check Server Status' to see their state." true
    else
        print_message $BLUE "--- Attempting to Start AzerothCore Servers (TMUX) ---" true
        # Check if tmux is installed
        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed. Please install it to manage servers." true
            return 1
        fi

        # Paths to executables, ensure they exist
        local auth_exec_path="$AZEROTHCORE_DIR/env/dist/bin/authserver"
        local world_exec_path="$AZEROTHCORE_DIR/env/dist/bin/worldserver"
        local server_bin_dir="$AZEROTHCORE_DIR/env/dist/bin" # Base directory for cd

        if [ ! -f "$auth_exec_path" ]; then
            print_message $RED "Authserver executable not found at $auth_exec_path" true
            return 1
        fi
        if [ ! -f "$world_exec_path" ]; then
            print_message $RED "Worldserver executable not found at $world_exec_path" true
            return 1
        fi

        # Check if the session already exists
        if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' already exists." false

            # Check if window 0 exists and has two panes (our expected layout).
            local pane_count
            pane_count=$(tmux list-panes -t "$TMUX_SESSION_NAME:0" 2>/dev/null | wc -l) # Target window 0 specifically

            if [ "$pane_count" -eq 2 ]; then
                # Further checks could verify titles or processes, but for now, 2 panes is a good sign.
                print_message $GREEN "TMUX session '$TMUX_SESSION_NAME' appears to have a split-pane setup in window 0." false
                print_message $YELLOW "Servers might be running. Use 'Check Server Status' or 'Stop/Restart'." false
                return 2 # Indicate servers might be running / session active
            else
                # Session exists, but not in the expected split-pane state (e.g., wrong number of panes in window 0).
                print_message $RED "Session '$TMUX_SESSION_NAME' exists but is not in the expected 2-pane configuration for window 0." true
                print_message $YELLOW "Please use 'Stop Servers' (which might kill the session) and then 'Start Servers' again for a clean setup." true
                return 1 # Indicate misconfiguration
            fi
        else
            # Create new session if it doesn't exist
            print_message $CYAN "Creating new TMUX session '$TMUX_SESSION_NAME' with split-pane layout..." false
            # Create session detached, it will have one window (0) and one pane (0.0) by default.
            tmux new-session -s "$TMUX_SESSION_NAME" -d
            if [ $? -ne 0 ]; then
                print_message $RED "Failed to create new TMUX session." true
                return 1
            fi
            sleep 1 # Give TMUX a moment to initialize

            # Set title for the first pane (Authserver)
            tmux select-pane -t "$TMUX_SESSION_NAME:0.0" -T "$AUTHSERVER_PANE_TITLE"

            print_message $CYAN "Starting Authserver in the first pane ($TMUX_SESSION_NAME:0.0)..." false
            tmux send-keys -t "$TMUX_SESSION_NAME:0.0" "cd '$server_bin_dir' && '$auth_exec_path'" C-m

            # Wait for Authserver to be ready by checking its port
            print_message $CYAN "Waiting for authserver to be ready on port $AUTH_PORT (max 60 seconds)..." false
            SPINNER=('\' '|' '/' '-')
            for i in {1..60}; do
                echo -ne "${CYAN}Checking port $AUTH_PORT: attempt $i/60 ${SPINNER[$((i % ${#SPINNER[@]}))]} \r${NC}"
                nc -z localhost "$AUTH_PORT" && break
                sleep 1
            done
            echo -ne "\r${NC}                                                                          \r" # Clear spinner line

            if ! nc -z localhost "$AUTH_PORT"; then
                print_message $RED "Authserver did not start or become ready on port $AUTH_PORT within 60 seconds." true
                print_message $RED "Check TMUX session '$TMUX_SESSION_NAME' (pane '$AUTHSERVER_PANE_TITLE') for errors." true
                tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null # Clean up the partially started session
                return 1
            fi
            print_message $GREEN "Authserver appears to be ready." true

            # Split the current window (window 0, pane 0.0) horizontally to create pane 0.1 for Worldserver
            print_message $CYAN "Splitting window and starting Worldserver in the second pane..." false
            tmux split-window -h -t "$TMUX_SESSION_NAME:0.0"
            if [ $? -ne 0 ]; then
                print_message $RED "Failed to split TMUX window." true
                tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null # Clean up
                return 1
            fi
            sleep 1 # Give TMUX a moment

            # Set title for the new pane (Worldserver, now pane 0.1)
            tmux select-pane -t "$TMUX_SESSION_NAME:0.1" -T "$WORLDSERVER_PANE_TITLE"

            print_message $CYAN "Starting Worldserver in the second pane ($TMUX_SESSION_NAME:0.1)..." false
            tmux send-keys -t "$TMUX_SESSION_NAME:0.1" "cd '$server_bin_dir' && '$world_exec_path'" C-m

            # Wait for Worldserver to be ready by checking its port
            print_message $CYAN "Waiting for worldserver to be ready on port $WORLD_PORT (max 60 seconds)..." false
            local world_spinner_chars=('\' '|' '/' '-') # Local spinner for this wait
            local world_ready=false
            for i in {1..60}; do
                # Use echo -ne to keep spinner on the same line
                echo -ne "\r${CYAN}Checking port $WORLD_PORT: attempt $i/60 ${world_spinner_chars[$((i % ${#world_spinner_chars[@]}))]} ${NC} "
                if nc -z localhost "$WORLD_PORT" &>/dev/null; then
                    world_ready=true
                    break
                fi
                sleep 1
            done
            echo -ne "\r${NC}                                                                          \r" # Clear spinner line

            if [ "$world_ready" = false ]; then
                print_message $RED "Worldserver did not start or become ready on port $WORLD_PORT within 60 seconds." true
                print_message $RED "Check TMUX session '$TMUX_SESSION_NAME' (pane '$WORLDSERVER_PANE_TITLE') for errors." true
                return 1 # Indicate failure
            else
                print_message $GREEN "Worldserver appears to be ready." true
            fi

            print_message $GREEN "Servers started in a split-pane layout in TMUX session '$TMUX_SESSION_NAME'." false
        fi

        # Common success messages
        echo ""
        print_message $CYAN "----------------------------------------------------------------------" true
        print_message $WHITE "\n  AzerothCore servers should now be starting/running in TMUX session '$TMUX_SESSION_NAME'." true
        print_message $YELLOW "  Authserver runs in the left pane ($AUTHSERVER_PANE_TITLE), Worldserver in the right pane ($WORLDSERVER_PANE_TITLE) of the first window." false
        echo ""
        print_message $CYAN "  To manage your server and view console output:" true
        print_message $WHITE "    ${BOLD}tmux attach -t $TMUX_SESSION_NAME${NC}" true
        echo ""
        print_message $CYAN "  Inside TMUX: Ctrl+B, then D to detach. Ctrl+B, <arrow_key> to switch panes." true
        print_message $CYAN "----------------------------------------------------------------------" true
        echo ""
    fi
    return 0 # Success
}

stop_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Stop Docker Containers ---" true
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose down
        print_message $GREEN "Docker containers stopped." true
    else
        print_message $BLUE "--- Attempting to Stop AzerothCore Servers (TMUX) ---" true

        # Check if TMUX is installed
        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed. Cannot manage servers." true
            return 1
        fi

        # Check if the TMUX session exists
        if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' not found. Servers are likely not running." false
            return 0 # Not an error, just nothing to do
        fi

        print_message $CYAN "TMUX session '$TMUX_SESSION_NAME' found." false

        # Define pane targets based on the split-pane layout (window 0, panes 0.0 and 0.1)
        local auth_target_pane="$TMUX_SESSION_NAME:0.0" # Authserver in left/top pane
        local world_target_pane="$TMUX_SESSION_NAME:0.1" # Worldserver in right/bottom pane
        local world_pane_exists=false
        local auth_pane_exists=false

        # Check if worldserver pane (0.1) exists.
        if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then # Check if pane 0.1 exists
            world_pane_exists=true
        fi

        if $world_pane_exists; then
            print_message $YELLOW "Sending graceful shutdown command ('$WORLDSERVER_CONSOLE_COMMAND_STOP') to Worldserver pane ($world_target_pane)..." false
            tmux send-keys -t "$world_target_pane" "$WORLDSERVER_CONSOLE_COMMAND_STOP" C-m

            # Wait for Worldserver to shut down by checking its port
            local shutdown_timer=0
            local max_shutdown_wait=300 # 300 seconds = 5 minutes
            print_message $CYAN "Waiting for Worldserver (port $WORLD_PORT) to shut down (up to $max_shutdown_wait seconds)..." false
            local spinner_chars="/-\\|"

            while nc -z localhost "$WORLD_PORT" &>/dev/null; do
                shutdown_timer=$((shutdown_timer + 1))
                if [ "$shutdown_timer" -gt "$max_shutdown_wait" ]; then
                    print_message $RED "Worldserver did not shut down within $max_shutdown_wait seconds. Proceeding with pane kill." true
                    break
                fi
                local char_index=$((shutdown_timer % ${#spinner_chars}))
                echo -ne "\r${CYAN}Waiting... ${spinner_chars:$char_index:1} (Attempt: $shutdown_timer/$max_shutdown_wait)${NC}  "
                sleep 1
            done
            echo -ne "\r${NC}                                                                          \r" # Clear spinner line

            if ! nc -z localhost "$WORLD_PORT" &>/dev/null; then
                print_message $GREEN "Worldserver on port $WORLD_PORT has shut down." false
            fi

            if [ -n "$POST_SHUTDOWN_DELAY_SECONDS" ] && [ "$POST_SHUTDOWN_DELAY_SECONDS" -gt 0 ]; then
                print_message $CYAN "Waiting an additional ${POST_SHUTDOWN_DELAY_SECONDS}s for any final server processes to complete..." false
                sleep "$POST_SHUTDOWN_DELAY_SECONDS"
            fi

            if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^1$"; then
                 print_message $YELLOW "Worldserver pane ($world_target_pane) still exists. Forcing closure." false
                 tmux kill-pane -t "$world_target_pane" 2>/dev/null || print_message $RED "Failed to kill Worldserver pane $world_target_pane." false
            else
                print_message $GREEN "Worldserver pane ($world_target_pane) closed (likely from graceful shutdown or port closure)." false
            fi
        else
            print_message $YELLOW "Worldserver pane ($world_target_pane) not found." false
        fi

        # Check if authserver pane (0.0) exists
        if tmux list-panes -t "$TMUX_SESSION_NAME:0" -F "#{pane_index}" | grep -q "^0$"; then # Check if pane 0.0 exists
            auth_pane_exists=true
        fi

        if $auth_pane_exists; then
            print_message $YELLOW "Stopping Authserver pane ($auth_target_pane) by sending C-c and killing pane..." false
            tmux send-keys -t "$auth_target_pane" C-c # Send Ctrl+C
            sleep 2 # Brief pause for C-c to take effect
            tmux kill-pane -t "$auth_target_pane" 2>/dev/null || print_message $RED "Failed to kill Authserver pane $auth_target_pane." false
            print_message $GREEN "Authserver pane ($auth_target_pane) stop command issued and pane killed." false
        else
            print_message $YELLOW "Authserver pane ($auth_target_pane) not found." false
        fi

        if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            if ! tmux list-panes -t "$TMUX_SESSION_NAME:0" &> /dev/null; then
                 print_message $CYAN "No more panes in window 0 of session '$TMUX_SESSION_NAME'. Killing session..." false
                 tmux kill-session -t "$TMUX_SESSION_NAME" &>/dev/null
                 print_message $GREEN "TMUX Session '$TMUX_SESSION_NAME' killed." false
            else
                 print_message $YELLOW "Session '$TMUX_SESSION_NAME' still active. Panes might still exist." false
                 print_message $YELLOW "Consider manual check: tmux attach -t $TMUX_SESSION_NAME" false
            fi
        fi
        print_message $GREEN "Server stop process completed." true
    fi
    return 0
}

restart_servers() {
    if is_docker_setup; then
        print_message $BLUE "--- Attempting to Restart Docker Containers ---" true
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose restart
        print_message $GREEN "Docker containers restarted." true
    else
        print_message $BLUE "--- Attempting to Restart AzerothCore Servers (TMUX) ---" true
        stop_servers
        local stop_status=$?
        if [ "$stop_status" -ne 0 ]; then
            print_message $RED "Server stop phase failed. Aborting restart." true
            return 1
        fi

        print_message $CYAN "Waiting for 10 seconds before starting servers again..." true
        sleep 10

        start_servers
        local start_status=$?
        if [ "$start_status" -ne 0 ] && [ "$start_status" -ne 2 ]; then # 2 means already running, which is odd here but not a failure to start
            print_message $RED "Server start phase failed. Please check messages." true
            return 1
        elif [ "$start_status" -eq 2 ]; then
             print_message $YELLOW "Servers reported as already running during start phase. This is unexpected after a stop. Please check status." true
        fi

        print_message $GREEN "Server restart process initiated." true
    fi
    return 0
}

check_server_status() {
    if is_docker_setup; then
        print_message $BLUE "--- Checking Docker Container Status ---" true
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose ps
    else
        print_message $BLUE "--- Checking AzerothCore Server Status (TMUX) ---" true

        if ! command -v tmux &> /dev/null; then
            print_message $RED "TMUX is not installed. Cannot determine server status." true
            return 1
        fi

        if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
            print_message $YELLOW "TMUX session '$TMUX_SESSION_NAME' is not running." false
            print_message $GREEN "Authserver: Stopped (TMUX session not found)" false
            print_message $GREEN "Worldserver: Stopped (TMUX session not found)" false
            return 0
        fi

        print_message $GREEN "TMUX Session '$TMUX_SESSION_NAME': Running" false
        local auth_server_pane="$TMUX_SESSION_NAME:0.0"
        local world_server_pane="$TMUX_SESSION_NAME:0.1"
        local auth_pid=""
        local auth_process_likely_running=false
        local auth_port_listening=false
        local auth_status_msg=""
        local auth_status_color=$YELLOW
        local world_pid=""
        local world_process_likely_running=false
        local world_port_listening=false
        local world_status_msg=""
        local world_status_color=$YELLOW

        auth_pid=$(tmux list-panes -t "$auth_server_pane" -F "#{pane_pid}" 2>/dev/null | head -n 1)
        if [ -n "$auth_pid" ]; then
            if ps -p "$auth_pid" -o args= | grep -Eq "(^|/)authserver(\s|$|--)"; then
                auth_process_likely_running=true
            elif ps -o args= -H --ppid "$auth_pid" | grep -Eq "(^|/)authserver(\s|$|--)"; then
                auth_process_likely_running=true
            fi
        fi

        if nc -z localhost "$AUTH_PORT" &>/dev/null; then
            auth_port_listening=true
        fi

        if $auth_port_listening && $auth_process_likely_running; then
            auth_status_msg="Authserver: Running (PID: $auth_pid, Process Name OK), Port $AUTH_PORT: Listening"
            auth_status_color=$GREEN
        elif $auth_port_listening && ! $auth_process_likely_running; then
            auth_status_msg="Authserver: Port $AUTH_PORT Listening (Process name check inconclusive for pane PID $auth_pid)"
        elif ! $auth_port_listening && $auth_process_likely_running; then
            auth_status_msg="Authserver: Process Found (PID: $auth_pid, Name OK), Port $AUTH_PORT: Not Listening"
        elif [ -n "$auth_pid" ]; then
            auth_status_msg="Authserver: Pane $auth_server_pane active (PID: $auth_pid), but process/port non-responsive."
            auth_status_color=$RED
        else
            auth_status_msg="Authserver: Stopped (Pane $auth_server_pane not found or no PID)"
        fi
        print_message "$auth_status_color" "$auth_status_msg" false

        world_pid=$(tmux list-panes -t "$world_server_pane" -F "#{pane_pid}" 2>/dev/null | head -n 1)
        if [ -n "$world_pid" ] && [ "$world_pid" != "$auth_pid" ]; then
            if ps -p "$world_pid" -o args= | grep -Eq "(^|/)worldserver(\s|$|--)"; then
                world_process_likely_running=true
            elif ps -o args= -H --ppid "$world_pid" | grep -Eq "(^|/)worldserver(\s|$|--)"; then
                world_process_likely_running=true
            fi
        fi

        if nc -z localhost "$WORLD_PORT" &>/dev/null; then
            world_port_listening=true
        fi

        if $world_port_listening; then
            if $world_process_likely_running; then
                world_status_msg="Worldserver: Running (PID: $world_pid, Process Name OK), Port $WORLD_PORT: Listening"
                world_status_color=$GREEN
            elif [ "$world_pid" == "$auth_pid" ]; then
                 world_status_msg="Worldserver: Port $WORLD_PORT Listening (Process name check complex due to shared pane PID with Authserver: $world_pid)"
                 world_status_color=$GREEN
            else
                world_status_msg="Worldserver: Port $WORLD_PORT Listening (Process name check inconclusive for pane PID $world_pid)"
            fi
        else
            if $world_process_likely_running; then
                world_status_msg="Worldserver: Process Found (PID: $world_pid, Name OK), Port $WORLD_PORT: Not Listening"
            elif [ -n "$world_pid" ]; then
                if [ "$world_pid" == "$auth_pid" ]; then
                     world_status_msg="Worldserver: Pane $world_server_pane active (PID: $world_pid, shared with Authserver), Port $WORLD_PORT: Not Listening."
                else
                     world_status_msg="Worldserver: Pane $world_server_pane active (PID: $world_pid), but Worldserver process/port non-responsive."
                fi
                world_status_color=$RED
            else
                world_status_msg="Worldserver: Stopped (Pane $world_server_pane not found or no PID)"
            fi
        fi
        print_message "$world_status_color" "$world_status_msg" false

        echo ""
        print_message $CYAN "Note: Status is based on TMUX pane PIDs, process arguments (direct & child), and port checks." false
        print_message $CYAN "For definitive status, attach to TMUX: tmux attach -t $TMUX_SESSION_NAME" false
    fi
    return 0
}

# Function to run worldserver and authserver in tmux session
# This is the original entry point from Main Menu option [3]
run_tmux_session() {
    # This function will now primarily be a wrapper around start_servers
    # and then handle the script exit as it did before.
    clear
    echo ""

    start_servers
    local start_status=$?

    if [ $start_status -eq 0 ]; then
        # Success message is already printed by start_servers
        # This function, when called from main menu option 3, should exit the script.
        exit 0
    elif [ $start_status -eq 2 ]; then
        # Servers might be running or session active, message already printed by start_servers
        # In this context (direct "Run Server Only"), we still inform and exit.
        print_message $YELLOW "To attach to the existing session: tmux attach -t $TMUX_SESSION_NAME" true
        exit 0 # Exit script as this option implies "I just want to run it (or ensure it's running)"
    else
        print_message $RED "Server startup failed. Please check messages above." true
        # Original script might have exited via handle_error. For this path, exiting with error is reasonable.
        exit 1
    fi
    # Fallback, though should be covered by exits above.
    RUN_SERVER=false
    BUILD_ONLY=false
}

# Function to ask for confirmation before updating or building.
# This function performs several pre-build checks:
# 1. Checks if Authserver (port $AUTH_PORT) or Worldserver (port $WORLD_PORT) seem to be running using 'nc'.
# 2. If servers appear active, it prompts the user to stop them.
# 3. If user agrees to stop:
#    a. Calls `stop_servers()`.
#    b. Re-checks ports to confirm successful shutdown. If still active, aborts build.
# 4. If user declines to stop active servers, aborts build.
# 5. If servers are stopped (or were not running), proceeds to ask about updating source code.
# 6. Finally, calls `ask_for_cores()`.
# Returns 0 if all checks pass and user confirms, allowing the build to proceed.
# Returns 1 if any check fails or user aborts, signaling to cancel the build.
ask_for_update_confirmation() {
    print_message $BLUE "--- Build Preparation ---" true

    # Step 1: Check if servers are running using port checks
    local auth_port_active=false
    local world_port_active=false
    if nc -z localhost "$AUTH_PORT" &>/dev/null; then auth_port_active=true; fi
    if nc -z localhost "$WORLD_PORT" &>/dev/null; then world_port_active=true; fi

    # Step 2 & 3: If servers active, prompt to stop
    if [ "$auth_port_active" = true ] || [ "$world_port_active" = true ]; then
        print_message $YELLOW "Servers appear to be running (ports $AUTH_PORT and/or $WORLD_PORT are active)." true
        print_message $YELLOW "It is strongly recommended to stop them before rebuilding." true
        print_message $YELLOW "Would you like to attempt to stop the servers now? (y/n)" true
        read -r stop_choice
        if [[ "$stop_choice" =~ ^[Yy]$ ]]; then
            # Step 3a: Call stop_servers()
            stop_servers
            local stop_result=$? # Capture return status of stop_servers (though currently it always returns 0)

            # Step 3b: Re-check ports to confirm successful shutdown
            if nc -z localhost "$AUTH_PORT" &>/dev/null || nc -z localhost "$WORLD_PORT" &>/dev/null; then
                # This condition means either stop_servers() didn't effectively stop them, or they restarted quickly.
                print_message $RED "Failed to stop servers (ports still active after stop attempt; stop_servers status: \"$stop_result\")." true
                print_message $RED "Rebuild aborted to prevent issues. Please stop servers manually via Process Management." true
                return 1 # Abort build
            else
                print_message $GREEN "Servers stopped successfully." true
            fi
        else
            # Step 4: User chose not to stop servers
            print_message $RED "User chose not to stop servers. Rebuild aborted." true
            return 1 # Abort build
        fi
    else
        # Servers were not detected as running by port check
        print_message $GREEN "Servers appear to be stopped (ports $AUTH_PORT and $WORLD_PORT are not active)." false
    fi

    # Step 5: Ask about updating source code
    echo "" # Add a space before the next question
    while true; do
        print_message $YELLOW "Would you like to update the AzerothCore source code before rebuilding? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]$ ]]; then
            echo ""
            print_message $GREEN "Skipping source code update. Proceeding with build preparation...\n" true
            break
        else
            echo ""
            print_message $RED "Invalid input. Please enter 'y' for yes or 'n' for no." false
        fi
    done

    # Ask the user how many cores to use for building, after update or skipping
    ask_for_cores
    return 0 # Proceed with build
}

# Function to ask the user how many cores they want to use for the build
ask_for_cores() {
    # This function is not relevant for Docker builds, so we skip it.
    if is_docker_setup; then
        return
    fi

    local current_cores_for_build="$CORES" # CORES is the runtime var, loaded from CORES_FOR_BUILD
    local available_cores_system=$(nproc)

    echo ""
    print_message $YELLOW "CPU Core Selection for Building" true
    if [ -n "$current_cores_for_build" ]; then
        print_message $CYAN "Currently configured cores for build: $current_cores_for_build" false
    else
        print_message $CYAN "Cores for build not set in config. Will use system default or prompt." false
    fi
    print_message $YELLOW "Available CPU cores on this system: $available_cores_system" false
    print_message $YELLOW "Press ENTER to use default (all available: $available_cores_system), or enter number of cores:" false
    read -r user_cores_input

    local new_cores_value=""

    if [ -z "$user_cores_input" ]; then
        new_cores_value=$available_cores_system
        print_message $GREEN "Defaulting to $new_cores_value (all available) cores for this session." true
    elif ! [[ "$user_cores_input" =~ ^[0-9]+$ ]]; then
        print_message $RED "Invalid input: '$user_cores_input' is not a number. Using $available_cores_system cores for this session." true
        new_cores_value=$available_cores_system
    elif [ "$user_cores_input" -eq 0 ]; then
        print_message $RED "Cannot use 0 cores. Using 1 core for this session." true
        new_cores_value=1
    elif [ "$user_cores_input" -gt "$available_cores_system" ]; then
        print_message $RED "Cannot use more cores than available ($available_cores_system). Using $available_cores_system for this session." true
        new_cores_value=$available_cores_system
    else
        new_cores_value="$user_cores_input"
        print_message $GREEN "Using $new_cores_value core(s) for this session." true
    fi

    # Update runtime CORES variable for current session
    CORES="$new_cores_value"

    # Offer to save if the new value is different from what was loaded (or if loaded was empty and now we have a value)
    if [ "$new_cores_value" != "$current_cores_for_build" ] || ([ -z "$current_cores_for_build" ] && [ -n "$new_cores_value" ]); then
        print_message $YELLOW "Save $new_cores_value cores to configuration for future builds? (y/n)" true
        read -r save_choice
        if [[ "$save_choice" =~ ^[Yy]$ ]]; then
            save_config_value "CORES_FOR_BUILD" "$new_cores_value"
            if [ $? -eq 0 ]; then
                print_message $GREEN "Cores for build ($new_cores_value) saved to configuration." true
            else
                print_message $RED "Failed to save cores for build." true
            fi
        else
            print_message $CYAN "Cores for build setting ($new_cores_value) will be used for this session only." false
        fi
    fi
    echo ""
}

# Function to build and install AzerothCore with spinner
build_and_install_with_spinner() {
    echo ""
    print_message $BLUE "--- Starting AzerothCore Build and Installation ---" true
    print_message $YELLOW "Building and installing AzerothCore... This may take a while." true

    if is_docker_setup; then
        print_message $CYAN "Running Docker build..." true
        cd "$AZEROTHCORE_DIR" || handle_error "Failed to change directory to $AZEROTHCORE_DIR"
        docker compose build || handle_error "Docker build failed. Check the output above for details."
        print_message $GREEN "--- Docker Build Process Completed Successfully ---" true
    else
        # Ensure BUILD_DIR is correctly updated
        if [ ! -d "$BUILD_DIR" ]; then
            handle_error "Build directory $BUILD_DIR does not exist. Please check your AzerothCore path."
        fi

        # Run cmake with the provided options
        cd "$BUILD_DIR" || handle_error "Failed to change directory to $BUILD_DIR. Ensure the path is correct."

        echo ""
        print_message $CYAN "Running CMake configuration..." true
        cmake ../ -DCMAKE_INSTALL_PREFIX="$AZEROTHCORE_DIR/env/dist/" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static || handle_error "CMake configuration failed. Check CMake logs in $BUILD_DIR for details."

        echo ""
        print_message $CYAN "Running make install with $CORES core(s)..." true
        make -j "$CORES" install || handle_error "Build process ('make install') failed. Check the output above and logs in $BUILD_DIR for details."
        echo ""
        print_message $GREEN "--- AzerothCore Build and Installation Completed Successfully ---" true
    fi
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    print_message "$YELLOW" "Starting authserver for a quick test and waiting for it to be ready..." true

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Wait for the authserver to be ready by checking if the server is listening on the specified port
    printf "%b" "${GREEN}Waiting for authserver to be ready on port $AUTH_PORT... "

    # Wait for authserver to start accepting connections (max wait 60 seconds)
    for i in {1..60}; do
        nc -z localhost "$AUTH_PORT" &>/dev/null && break # Fixed: Silencing nc output
        sleep 1
        printf "%b" "." # Simple visual feedback during wait
    done

    # If we didn't break out of the loop, the server isn't ready
    if ! nc -z localhost "$AUTH_PORT" &>/dev/null; then # Fixed: Silencing nc output in check as well
        printf "\n" # Newline after dots
        handle_error "Authserver did not start within the expected time frame."
    fi

    printf "%b%s%b\n" "\n${GREEN}Authserver is ready! Waiting 5 seconds before closing..."
    sleep 5

    # Kill the authserver process
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null  # Wait for the authserver process to properly exit

    print_message "$GREEN" "Authserver test shutdown complete." true
}
