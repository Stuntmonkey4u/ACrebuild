#!/bin/bash

view_log_file() {
    local log_file_path=$1
    local default_mode=$2 # Can be "less" or "tail_f"

    if [ ! -f "$log_file_path" ]; then
        print_message $RED "Log file not found: $log_file_path" true
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
        return 1
    fi

    local chosen_mode="$default_mode"
    if [ -z "$chosen_mode" ]; then
        print_message $YELLOW "How do you want to view the log?" true
        print_message $CYAN "  [L] Less (scroll/browse)" false
        print_message $CYAN "  [T] Tail -f (live view)" false
        read -r -p "$(echo -e "${YELLOW}${BOLD}Enter choice [L/T]: ${NC}")" mode_choice
        case $mode_choice in
            [Tt]) chosen_mode="tail_f" ;;
            *) chosen_mode="less" ;;
        esac
    fi

    print_message $GREEN "Opening log with $chosen_mode..." false
    sleep 1
    clear

    if [ "$chosen_mode" = "less" ]; then
        less -- "$log_file_path"
    elif [ "$chosen_mode" = "tail_f" ]; then
        tail -f -- "$log_file_path"
    fi
    clear
    print_message $GREEN "Exited log view." true
}

view_auth_log() {
    local mode=$1 # Pass "tail_f" for live view
    print_message $CYAN "Accessing auth server log..." false
    if is_docker_setup; then
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose logs ${mode:+-f} ac-authserver)
    else
        view_log_file "$SERVER_LOG_DIR_PATH/$AUTH_SERVER_LOG_FILENAME" "$mode"
    fi
}

view_world_log() {
    local mode=$1 # Pass "tail_f" for live view
    print_message $CYAN "Accessing world server log..." false
    if is_docker_setup; then
        (cd "$AZEROTHCORE_DIR" && "$DOCKER_EXEC_PATH" compose logs ${mode:+-f} ac-worldserver)
    else
        view_log_file "$SERVER_LOG_DIR_PATH/$WORLD_SERVER_LOG_FILENAME" "$mode"
    fi
}

view_error_log() {
    print_message $CYAN "Accessing server error log..." false
    if is_docker_setup; then
        print_message $YELLOW "In Docker mode, errors are in the main container logs." true
    else
        view_log_file "$SERVER_LOG_DIR_PATH/$ERROR_LOG_FILENAME" "less"
    fi
}

view_cron_log() {
    print_message $CYAN "Accessing automated backup log..." false
    view_log_file "$SCRIPT_LOG_DIR/$DEFAULT_CRON_LOG_FILENAME" "less"
}
