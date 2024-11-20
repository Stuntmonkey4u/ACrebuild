#!/bin/bash

# Define colors for better readability in the terminal
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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
        print_message $GREEN "All required dependencies are installed." true
    fi
}

# Function to ask if the user wants to install missing dependencies
ask_to_install_dependencies() {
    print_message $YELLOW "The following dependencies are missing: ${MISSING_DEPENDENCIES[*]}" true
    print_message $YELLOW "Do you want to install them? (y/n)" true
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

# Function to display a welcome message
welcome_message() {
    clear
    print_message $BLUE "=====================================" true
    print_message $BLUE "      Welcome to AzerothCore Setup   " true
    print_message $BLUE "=====================================" true
    print_message $BLUE "This script will help you update, build, and run AzerothCore on your system." true
    print_message $BLUE "=====================================" true
    echo ""
}

# Function to display the menu
show_menu() {
    print_message $YELLOW "Please choose an option:" true
    echo ""
    print_message $YELLOW "1) Build and run the server" false
    print_message $YELLOW "2) Only build the server" false
    print_message $YELLOW "3) Run the server without building" false
    print_message $YELLOW "4) Exit" false
    echo ""
}

# Function to handle user input for the menu
handle_menu_choice() {
    while true; do
        read -p "Enter choice [1-4]: " choice
        case $choice in
            1)
                RUN_SERVER=true
                BUILD_ONLY=true
                break
                ;;
            2)
                RUN_SERVER=false
                BUILD_ONLY=true
                break
                ;;
            3)
                RUN_SERVER=true
                BUILD_ONLY=false
                break
                ;;
            4)
                print_message $GREEN "Exiting the script..." true
                exit 0
                ;;
            *)
                print_message $RED "Invalid input. Please enter a valid option (1-4)." false
                ;;
        esac
    done
}

# Function to ask for confirmation before updating or building
ask_for_update_confirmation() {
    while true; do
        print_message $YELLOW "Do you want to update the AzerothCore source code before building? (y/n)" true
        read -r confirmation
        if [[ "$confirmation" =~ ^[Yy]$ ]]; then
            update_source_code
            break
        elif [[ "$confirmation" =~ ^[Nn]$ ]]; then
            print_message $GREEN "Skipping update. Proceeding with build." true
            break
        else
            print_message $RED "Invalid input. Please enter 'y' for yes or 'n' for no." false
        fi
    done
}

# Function to update the AzerothCore source code
update_source_code() {
    print_message $YELLOW "Updating AzerothCore source code..." true
    cd "$AZEROTHCORE_DIR" || handle_error "Failed to change directory to $AZEROTHCORE_DIR"
    
    sudo git pull origin master || handle_error "Git pull failed"
    print_message $GREEN "AzerothCore source code updated successfully." true
}

# Function to build and install AzerothCore with spinner
build_and_install_with_spinner() {
    print_message $YELLOW "Building and installing AzerothCore..." true

    # Run cmake with the provided options
    cd "$BUILD_DIR" || handle_error "Failed to change directory to $BUILD_DIR"

    cmake ../ -DCMAKE_INSTALL_PREFIX=$HOME/azerothcore/env/dist/ -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static || handle_error "CMake configuration failed"

    # Run 'make' with parallel jobs and install
    make -j "$(nproc)" install || handle_error "Build failed"
    print_message $GREEN "AzerothCore build and installation completed successfully." true
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    print_message $YELLOW "Starting authserver for 60 seconds..." true

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Countdown timer
    COUNTDOWN=60
    while [ $COUNTDOWN -gt 0 ]; do
        if [ $COUNTDOWN -eq 1 ]; then
            # Print countdown with singular "second"
            echo -ne "Time remaining: $COUNTDOWN second  \r"
        else
            # Print countdown with plural "seconds"
            echo -ne "Time remaining: $COUNTDOWN seconds \r"
        fi
        sleep 1
        ((COUNTDOWN--))
    done

    # Kill the authserver after 60 seconds
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null  # Wait for the authserver process to properly exit
    print_message $GREEN "authserver has been stopped after 60 seconds." true
}

# Function to run worldserver and authserver in tmux session
run_tmux_session() {
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

    # Print the updated, epic message
    print_message $GREEN "\nAzeroth has been reborn!\n" true
    print_message $GREEN "The forces of light and darkness await their champions!\n" true
    print_message $GREEN "Prepare for the epic battle that lies ahead!\n" true
    print_message $YELLOW "To switch to the tmux session, run: 'tmux attach -t azeroth'\n" true
}

# Main function to start the script
main_menu() {
    clear

    # Display welcome message
    welcome_message

    # Check for dependencies
    check_dependencies

    # Show the menu and handle user choice
    show_menu
    handle_menu_choice

    # Proceed with selected action
    if [ "$BUILD_ONLY" = true ]; then
        ask_for_update_confirmation
        build_and_install_with_spinner
    fi

    if [ "$RUN_SERVER" = true ]; then
        run_tmux_session
        print_message $GREEN "Server executed in tmux session." true
    elif [ "$BUILD_ONLY" = false ]; then
        print_message $GREEN "Only server run was selected. No build or update occurred." true
    fi
}

# Start the main menu function
main_menu
