#!/bin/bash

# Function to view a log file
view_log_file() {
    local log_file_path=$1
    local view_mode_prompt=$2 # true if we should prompt for mode, false if using a default (less)

    if [ ! -f "$log_file_path" ]; then
        print_message $RED "Log file not found: $log_file_path" true
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
        return 1
    fi

    local chosen_mode=""
    if [ "$view_mode_prompt" = true ]; then
        echo ""
        print_message $YELLOW "How do you want to view '$log_file_path'?" true
        print_message $CYAN "  [L] Less (scroll/browse)" false
        print_message $CYAN "  [T] Tail -f (live view)" false
        print_message $CYAN "  [C] Cancel" false
        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [L/T/C]: ${NC}")" mode_choice
        echo ""
        case $mode_choice in
            [Ll]) chosen_mode="less" ;;
            [Tt]) chosen_mode="tail_f" ;;
            [Cc]) print_message $GREEN "Log viewing cancelled." false; return ;;
            *) print_message $RED "Invalid mode selected. Defaulting to 'less'." false; chosen_mode="less" ;;
        esac
    else
        chosen_mode="less" # Default mode if not prompting
    fi

    print_message $GREEN "Opening $log_file_path with $chosen_mode..." false
    # Adding a small delay so the user can see the message before less/tail takes over the screen
    sleep 1
    clear

    if [ "$chosen_mode" = "less" ]; then
        less -- "$log_file_path"
    elif [ "$chosen_mode" = "tail_f" ]; then
        tail -f -- "$log_file_path"
    fi
    # After exiting less or tail -f, clear and show a message
    clear
    print_message $GREEN "Exited log view. Press any key to return to the Log Viewer menu..." true
    read -n 1 -s -r
    echo ""
}

view_script_log() {
    print_message $CYAN "Accessing script log..." false
    view_log_file "$SCRIPT_LOG_FILE" false # false means use default mode 'less'
}

view_auth_log() {
    print_message $CYAN "Accessing auth server log..." false
    if is_docker_setup; then
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose logs -f ac-authserver
    else
        local full_auth_log_path="$SERVER_LOG_DIR_PATH/$AUTH_SERVER_LOG_FILENAME"
        view_log_file "$full_auth_log_path" true # true means prompt for view mode
    fi
}

view_world_log() {
    print_message $CYAN "Accessing world server log..." false
    if is_docker_setup; then
        cd "$AZEROTHCORE_DIR" || return 1
        docker compose logs -f ac-worldserver
    else
        local full_world_log_path="$SERVER_LOG_DIR_PATH/$WORLD_SERVER_LOG_FILENAME"
        view_log_file "$full_world_log_path" true # true means prompt for view mode
    fi
}

view_error_log() {
    print_message $CYAN "Accessing server error log..." false
    local full_error_log_path="$SERVER_LOG_DIR_PATH/$ERROR_LOG_FILENAME"
    view_log_file "$full_error_log_path" true # true means prompt for view mode (less/tail)
}
