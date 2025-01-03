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

# Define the path to your AzerothCore directory
AZEROTHCORE_DIR="$HOME/azerothcore"
BUILD_DIR="$AZEROTHCORE_DIR/build"
AUTH_SERVER_EXEC="$HOME/azerothcore/env/dist/bin/authserver"
WORLD_SERVER_EXEC="$HOME/azerothcore/env/dist/bin/worldserver"

# Function to print the message with a specific color and optional bold text
print_message() {
    local color=$1
    local message=$2
    local bold=$3

    # Check if bold is true and apply bold formatting
    if [ "$bold" = true ]; then
        echo -e "${color}${BOLD}${message}${NC}"
    else
        echo -e "${color}${message}${NC}"
    fi
}

# Function to check if essential dependencies are installed
check_dependencies() {
    print_message $BLUE "Checking for essential dependencies..." true

    # List of dependencies to check
    DEPENDENCIES=("git" "cmake" "make" "clang" "clang++" "tmux")
    for DEP in "${DEPENDENCIES[@]}"; do
        command -v "$DEP" &>/dev/null
        if [ $? -ne 0 ]; then
            print_message $RED "$DEP is not installed. Please install it before continuing." false
            MISSING_DEPENDENCIES+=("$DEP")
        fi
    done

    # If there are missing dependencies, prompt the user to install them
    if [ ${#MISSING_DEPENDENCIES[@]} -gt 0 ]; then
        ask_to_install_dependencies
    else
        print_message $GREEN "All required dependencies are installed.\n" true
    fi
}

# Function to ask if the user wants to install missing dependencies
ask_to_install_dependencies() {
    print_message $YELLOW "The following dependencies are required but missing: ${MISSING_DEPENDENCIES[*]}" true
    print_message $YELLOW "Would you like to install them now? (y/n)" true
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        install_dependencies
        print_message $GREEN "Dependencies installed. Returning to main menu..." true
        sleep 2
        main_menu
    else
        print_message $RED "Cannot proceed without the required dependencies. Exiting..." true
        exit 1
    fi
}

# Function to install the missing dependencies
install_dependencies() {
    for DEP in "${MISSING_DEPENDENCIES[@]}"; do
        sudo apt install -y "$DEP" || { print_message $RED "Failed to install $DEP. Exiting." true; exit 1; }
    done
}

# Function to ask the user where their AzerothCore is installed
ask_for_core_installation_path() {
    print_message $YELLOW "Where is your existing AzerothCore installation located? (default: $HOME/azerothcore)" true
    read -r user_input

    # If user input is empty, use default path
    if [ -z "$user_input" ]; then
        AZEROTHCORE_DIR="$HOME/azerothcore"
    else
        AZEROTHCORE_DIR="$user_input"
    fi

    # Update the build directory dynamically based on AZEROTHCORE_DIR
    BUILD_DIR="$AZEROTHCORE_DIR/build"
    AUTH_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/authserver"
    WORLD_SERVER_EXEC="$AZEROTHCORE_DIR/env/dist/bin/worldserver"

    print_message $GREEN "AzerothCore directory set to: $AZEROTHCORE_DIR" true
    print_message $GREEN "Build directory set to: $BUILD_DIR" true
    print_message $GREEN "Auth server exec set to: $AUTH_SERVER_EXEC" true
    print_message $GREEN "World server exec set to: $WORLD_SERVER_EXEC" true
}

# Function to download updates to AzerothCore
update_source_code() {
    print_message $YELLOW "Updating your AzerothCore source code..." true
    cd "$AZEROTHCORE_DIR" || handle_error "Failed to change directory to $AZEROTHCORE_DIR"
    
    # Fetch updates from the remote repository (only update tracking branches)
    git fetch origin || handle_error "Git fetch failed"
    
    # Automatically detect the default branch (e.g., 'main' or 'master')
    DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
    
    # Check if there are any new commits in the remote repository
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$DEFAULT_BRANCH")  # Use the detected default branch

    if [ "$LOCAL" != "$REMOTE" ]; then
        print_message $YELLOW "New commits found. Pulling updates..." true
        # Pull the latest changes (merge them into the local branch)
        git pull origin "$DEFAULT_BRANCH" || handle_error "Git pull failed"
    else
        print_message $GREEN "No new commits. Local repository is up to date." true
    fi
    
    print_message $GREEN "AzerothCore source code updated successfully.\n" true
}

# Function to display a welcome message
welcome_message() {
    clear
    print_message $BLUE "----------------------------------------------" true
    print_message $BLUE "Welcome to AzerothCore Rebuild!           " true
    print_message $BLUE "----------------------------------------------" true
    echo ""
    print_message $BLUE "This script helps you manage your existing AzerothCore server by allowing you to:" true
    print_message $BLUE "  - Update the AzerothCore source code" true
    print_message $BLUE "  - Rebuild the server with the latest changes" true
    print_message $BLUE "  - Run your AzerothCore server" true
    print_message $BLUE "  - Update server module" true
    echo ""
    print_message $BLUE "----------------------------------------------" true
    echo ""
}

# Function to display the menu
show_menu() {
    echo ""
    print_message $YELLOW "Select an option from the menu below:" true
    echo ""
    print_message $YELLOW "1) Rebuild and Run the Server" false
    print_message $YELLOW "2) Rebuild the Server Only" false
    print_message $YELLOW "3) Run the Server (Without Building)" false
    print_message $YELLOW "4) Update Server Modules" false
    print_message $YELLOW "5) Exit" false
    echo ""
}

# Function to handle user input for the menu
handle_menu_choice() {
    read -p "Enter choice [1-5]: " choice
    case $choice in
        1)
            RUN_SERVER=true
            BUILD_ONLY=true
            ;;
        2)
            RUN_SERVER=false
            BUILD_ONLY=true
            ;;
        3)
            RUN_SERVER=true
            BUILD_ONLY=false
            ;;
        4)
            export AZEROTHCORE_DIR
            ./ACmod.sh || { print_message $RED "Failed to execute ACmod.sh. Ensure it exists and is executable." true; }
            ;;
        5)
            print_message $GREEN "Exiting. Thank you for using the AzerothCore rebuild tool!" true
            exit 0
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-5)." false
            return
            ;;
    esac
}

# Function to ask for confirmation before updating or building
ask_for_update_confirmation() {
    while true; do
        print_message $YELLOW "Would you like to update the AzerothCore source code before rebuilding? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]$ ]]; then
            print_message $GREEN "Skipping update. Proceeding with build.\n" true
            break
        else
            print_message $RED "Invalid input. Please enter 'y' for yes or 'n' for no." false
        fi
    done

    # Ask the user how many cores to use for building, after update or skipping
    ask_for_cores
}

# Function to ask the user how many cores they want to use for the build
ask_for_cores() {
    # Get the number of available CPU cores
    AVAILABLE_CORES=$(nproc)

    # Ask the user for the number of cores to use for building (default to all cores)
    print_message $YELLOW "Available CPU cores: $AVAILABLE_CORES"
    read -p "Enter the number of cores to use for building (default: all cores): " CORES

    # If user input is empty, default to using all cores
    if [ -z "$CORES" ]; then
        CORES=$AVAILABLE_CORES
        print_message $GREEN "Using all $CORES cores for the build." true
    elif [ "$CORES" -gt "$AVAILABLE_CORES" ]; then
        print_message $RED "You cannot use more cores than available. Defaulting to $AVAILABLE_CORES cores." true
        CORES=$AVAILABLE_CORES
    else
        print_message $GREEN "Using $CORES cores for the build." true
    fi
}

# Function to build and install AzerothCore with spinner
build_and_install_with_spinner() {
    print_message $YELLOW "Building and installing AzerothCore..." true

    # Ensure BUILD_DIR is correctly updated
    if [ ! -d "$BUILD_DIR" ]; then
        handle_error "Build directory $BUILD_DIR does not exist."
    fi

    # Run cmake with the provided options
    cd "$BUILD_DIR" || handle_error "Failed to change directory to $BUILD_DIR"

    cmake ../ -DCMAKE_INSTALL_PREFIX="$AZEROTHCORE_DIR/env/dist/" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static || handle_error "CMake configuration failed"

    # Run the build process using the specified number of cores
    make -j "$CORES" install || handle_error "Build failed"
    print_message $GREEN "AzerothCore build and installation completed successfully." true
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    print_message $YELLOW "Starting authserver for $COUNTDOWN seconds..." true

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Countdown timer
    COUNTDOWN=45
    while [ $COUNTDOWN -gt 0 ]; do
        if [ $COUNTDOWN -eq 1 ]; then
            # Print countdown with singular "second", in green
            echo -ne "${GREEN}Giving Authserver time to finish: $COUNTDOWN second  \r"
        else
            # Print countdown with plural "seconds", in green
            echo -ne "${GREEN}Giving Authserver time to finish: $COUNTDOWN seconds \r"
        fi
        sleep 1
        ((COUNTDOWN--))
    done

    # Kill the authserver after 60 seconds
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null  # Wait for the authserver process to properly exit
    print_message $GREEN "Exiting. Thank you for using the AzerothCore rebuild tool!" true
    exit
}

# Function to run worldserver and authserver in tmux session
run_tmux_session() {
    # Clear the screen to avoid jumbled output
    clear

    print_message $YELLOW "Starting Azerothcore" false

    # Start a new tmux session named "azeroth", attach to it immediately (we don't want to start it detached)
    tmux new-session -s azeroth -d

    # Wait for tmux session to initialize
    sleep 1

    # Split the screen horizontally
    tmux split-window -h

    # Rename the panes
    tmux send-keys -t azeroth:0.0 "rename-pane 'Authserver'" C-m
    tmux send-keys -t azeroth:0.1 "rename-pane 'Worldserver'" C-m

    # Run authserver in left pane and worldserver in right pane
    tmux send-keys -t azeroth:0.0 "cd ~/azerothcore/env/dist/bin && ./authserver" C-m
    sleep 10
    tmux send-keys -t azeroth:0.1 "cd ~/azerothcore/env/dist/bin && ./worldserver" C-m

    # Detach from the tmux session
    tmux detach -s azeroth

    # Print the updated, epic message after clearing the screen
    clear  # Clear the screen before displaying the message
    print_message $CYAN "----------------------------------------------------"
    print_message $WHITE "\n  AzerothCore has been reawakened!"
    print_message $WHITE "  The server is ready, but there's a new challenge..."
    echo ""
    print_message $YELLOW "  The NPCs have become sentient and they want royalties"
    print_message $YELLOW "  They've started forming a union. Negotiations begin soon."
    echo ""
    print_message $CYAN "  Settle the negotiations: 'tmux attach -t azeroth'"
    print_message $CYAN "----------------------------------------------------" 
    echo ""  # Add some space before closing
    exit
}

# Main function to start the script
main_menu() {
    clear

    # Display welcome message
    welcome_message

    # Check for dependencies
    check_dependencies

    # After dependency checks in the main function
    ask_for_core_installation_path

    # Show the menu in a loop
    while true; do
        show_menu
        handle_menu_choice

        # Proceed with selected action
        if [ "$BUILD_ONLY" = true ]; then
            ask_for_update_confirmation
            build_and_install_with_spinner
        fi

        if [ "$RUN_SERVER" = true ]; then
            # Run authserver and worldserver in tmux session
            run_tmux_session
        elif [ "$BUILD_ONLY" = false ]; then
            print_message $GREEN "Only server run was selected. No build or update occurred." true
        fi

        # Run authserver for 60 seconds (Only for option 2)
        if [ "$BUILD_ONLY" = true ] && [ "$RUN_SERVER" = false ]; then
            run_authserver
        fi

        # Reset action flags after execution
        RUN_SERVER=false
        BUILD_ONLY=false
    done
}

# Function to handle errors
handle_error() {
    print_message $RED "$1" true
    exit 1
}

# Run the main menu function when the script starts
main_menu
