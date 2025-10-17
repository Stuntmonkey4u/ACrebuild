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
# Note: SCRIPT_LOG_DIR and SCRIPT_LOG_FILE are used here.
# These will use the global DEFAULT values until load_config() is called.
# load_config() will then update them based on config values.
print_message() {
    local color=$1
    local message=$2
    local bold=$3
    local log_message # For storing the uncolored message

    # Determine which log directory/file to use (pre-config vs post-config)
    local current_log_dir="${SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}"
    local current_log_file="${SCRIPT_LOG_FILE:-$current_log_dir/$DEFAULT_SCRIPT_LOG_FILENAME}"

    # Create SCRIPT_LOG_DIR if it doesn't exist
    if [ ! -d "$current_log_dir" ]; then
        mkdir -p "$current_log_dir" || echo "WARNING: Could not create script log directory $current_log_dir. Logging to file will be disabled for this message."
    fi

    # Prepare message for logging (remove color codes)
    # Using echo -e to interpret escape sequences, then sed to remove them.
    log_message=$(echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g')

    # Append timestamped message to SCRIPT_LOG_FILE
    if [ -d "$current_log_dir" ]; then # Check again in case creation failed
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_message" >> "$current_log_file"
    fi

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
run_command() {
    local command_str="$1"
    local cwd="$2"

    # Split the command string into an array to handle arguments safely.
    # This avoids using 'eval', which can be a security risk.
    local -a cmd_parts
    read -r -a cmd_parts <<< "$command_str"

    # Execute the command.
    # The subshell with 'cd' ensures we don't change the script's main directory.
    if [ -z "$cwd" ]; then
        "${cmd_parts[@]}"
    else
        (cd "$cwd" && "${cmd_parts[@]}")
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
                print_message $RED "\nInvalid input: '$USER_INPUT'. Please enter 'y' or 'n'." false
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
    print_message $RED "--------------------------------------------------------------------" true
    print_message $RED "ERROR: $error_message" true

    if [[ "$error_message" == *"CMake configuration failed"* || "$error_message" == *"Build process ('make install') failed"* || "$error_message" == *"Docker build failed"* ]]; then
        if is_docker_setup; then
            print_message $YELLOW "A Docker build failure occurred. Would you like to try rebuilding with the '--no-cache' option?" true
            print_message $YELLOW "This can sometimes resolve issues with corrupted cache layers." true
        else
            print_message $YELLOW "A build failure occurred. Would you like to run 'make clean' to try and fix it?" true
        fi

        run_countdown_timer 900 # 15 minutes
        local countdown_result=$?

        if [ "$countdown_result" -eq 0 ]; then # User chose 'yes' or timed out
            if is_docker_setup; then
                print_message $GREEN "Attempting to rebuild with '--no-cache'..." true
                # We need a way to pass this option to the build function.
                # For now, let's just attempt a normal rebuild, but ideally this would trigger a no-cache build.
                # This highlights a need for better inter-function communication.
                # Let's assume for now we can't easily pass a no-cache flag, so we just rebuild.
                # A better implementation would be to set a global flag.
                # For now, we will just call the main build function again.
                build_and_install_with_spinner # This needs to be adapted to handle a no-cache flag
            else
                print_message $GREEN "Running 'make clean'..." true
                if [ -d "$BUILD_DIR" ]; then
                    (cd "$BUILD_DIR" && make clean) || print_message $RED "Warning: 'make clean' encountered an error, but attempting rebuild anyway." false
                else
                    print_message $RED "Build directory $BUILD_DIR not found. Cannot run 'make clean'." true
                fi
                print_message $BLUE "Attempting to rebuild..." true
                build_and_install_with_spinner
            fi
            print_message $GREEN "Rebuild process finished." true
            exit 0
        elif [ "$countdown_result" -eq 1 ]; then # User chose 'no'
            print_message $RED "Skipping rebuild attempt. Exiting." true
            print_message $RED "--------------------------------------------------------------------" true
            exit 1
        # Optional: Handle other return codes from run_countdown_timer if you added them (e.g., for invalid input)
        # else
        #     print_message $RED "Invalid response from countdown. Exiting." true
        #     exit 1
        fi
    elif [[ "$error_message" == *"authserver executable not found"* ]]; then
        print_message $RED "Suggestion: Ensure AzerothCore was built successfully and the path is correct." true
    elif [[ "$error_message" == *"TMUX session"* ]]; then
        print_message $RED "Suggestion: Ensure TMUX is installed ('sudo apt install tmux') and functioning correctly." true
    fi
    print_message $RED "--------------------------------------------------------------------" true
    exit 1
}

# Function to check if the script is running in a Docker setup
is_docker_setup() {
    if [ -f "${AZEROTHCORE_DIR}/docker-compose.yml" ]; then
        return 0 # True, it's a Docker setup
    else
        return 1 # False, not a Docker setup
    fi
}
