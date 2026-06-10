#!/bin/bash

# Define colors for better readability in the terminal
CYAN='\033[0;36m'        # Cyan for spinner and interactive text
GREEN='\033[38;5;82m'       # Green for success messages
YELLOW='\033[1;33m'      # Yellow for warnings and prompts
RED='\033[38;5;196m'         # Red for errors and important alerts
BLUE='\033[38;5;117m'        # Blue for headers and important sections
WHITE='\033[1;37m'       # White for general text
BOLD='\033[1m'           # Bold for emphasis
NC='\033[0m'             # No Color (reset)

# Function to print the message with a specific color and optional bold text
print_message() {
    local color=$1
    local message=$2
    local bold=$3

    # Print to console with color
    if [ "$bold" = true ]; then
        echo -e "${color}${BOLD}${message}${NC}"
    else
        echo -e "${color}${message}${NC}"
    fi
}

# Function to get the package manager
get_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unsupported"
    fi
}

# Function to run a command and capture its output
# Takes an arbitrary number of arguments where the first is the command.
# If the first argument is "CWD:", the second argument is the directory to run the command in.
run_command() {
    local cwd=""

    if [ "$1" = "CWD:" ]; then
        cwd="$2"
        shift 2
    fi

    if [ -z "$cwd" ]; then
        "$@"
    else
        (cd "$cwd" && "$@")
    fi
}

# Function to run a countdown timer and wait for user input
run_countdown_timer() {
    local DURATION=$1
    local USER_INPUT=""
    local TIMEOUT=$DURATION

    while [[ $TIMEOUT -gt 0 ]]; do
        MINUTES=$((TIMEOUT / 60))
        SECONDS=$((TIMEOUT % 60))
        # Use \r to return cursor to the beginning of the line for continuous update
        printf "\r${YELLOW}${BOLD}Enter your choice (y/n): Defaulting to 'yes' in %02d:%02d... ${NC}" "$MINUTES" "$SECONDS"

        read -r -t 1 USER_INPUT

        if [[ -n "$USER_INPUT" ]]; then
            echo "" # Newline after user input
            if [[ "$USER_INPUT" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                return 0 # Yes
            elif [[ "$USER_INPUT" =~ ^[Nn]([Oo])?$ ]]; then
                return 1 # No
            else
                # Optional: Handle invalid input during countdown differently, or let it be handled by the caller
                print_message "$RED" "\nInvalid input: '$USER_INPUT'. Please enter 'y' or 'n'." false
                # For now, let's treat invalid input as 'no' to avoid accidental 'yes' on typo, or simply re-prompt.
                # Re-prompting by continuing the loop. Let's clear the invalid input message.
                printf "\r%80s\r" " " # Clear the line
                USER_INPUT="" # Reset user input to continue loop or timeout
                # Or, to be strict, uncomment below and exit/return specific code for invalid input
                # return 2 # Invalid input code
            fi
        fi

        TIMEOUT=$((TIMEOUT - 1))
    done

    echo "" # Newline after timeout
    return 0 # Timeout (default to Yes)
}


# Function to handle errors
handle_error() {
    local error_message="$1"
    echo "" # Add whitespace before error
    print_message "$RED" "--------------------------------------------------------------------" true
    print_message "$RED" "ERROR: $error_message" true

    if [[ "$error_message" == *"authserver executable not found"* ]]; then
        print_message "$RED" "Suggestion: Ensure AzerothCore was built successfully and the path is correct." true
    elif [[ "$error_message" == *"TMUX session"* ]]; then
        print_message "$RED" "Suggestion: Ensure TMUX is installed ('sudo apt install tmux') and functioning correctly." true
    fi
    print_message "$RED" "--------------------------------------------------------------------" true
    exit 1
}

# Function to check if the script is running in a Docker setup
# This is the single source of truth for Docker mode detection.
is_docker_setup() {
    [ "$USE_DOCKER" = true ]
}

# Function to check if a Docker container is running
is_container_running() {
    local container_name=$1
    if [ -z "$DOCKER_EXEC_PATH" ]; then
        return 1
    fi
    local status
    status=$("$DOCKER_EXEC_PATH" inspect --format="{{.State.Status}}" "$container_name" 2>/dev/null)
    if [ "$status" = "running" ]; then
        return 0
    else
        return 1
    fi
}

# Function to expand tilde (~) in paths
expand_path() {
    local path=$1
    if [[ "$path" == "~/"* ]]; then
        echo "${HOME}${path:1}"
    else
        echo "$path"
    fi
}


get_secure_db_pass() {
    if [ -f "$CONFIG_DIR/.my.cnf" ]; then
        grep '^password=' "$CONFIG_DIR/.my.cnf" | sed 's/^password=//' | tr -d '"' | tr -d "'"
    else
        echo ""
    fi
}
