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
    echo ""
    print_message $YELLOW "The following dependencies are required but missing: ${MISSING_DEPENDENCIES[*]}" true
    print_message $YELLOW "Would you like to try and install them now? (y/n)" true
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        install_dependencies
        echo ""
        print_message $GREEN "Dependencies installation attempt finished." true
        print_message $BLUE "Please check the output above for any errors. Returning to main menu..." true
        sleep 3
        main_menu
    else
        echo ""
        print_message $RED "--------------------------------------------------------------------" true
        print_message $RED "Critical: Cannot proceed without the required dependencies. Exiting..." true
        print_message $RED "--------------------------------------------------------------------" true
        exit 1
    fi
}

# Function to install the missing dependencies
install_dependencies() {
    print_message $BLUE "Attempting to install missing dependencies..." true
    for DEP in "${MISSING_DEPENDENCIES[@]}"; do
        print_message $YELLOW "Installing $DEP..." false
        sudo apt install -y "$DEP" || { print_message $RED "Error: Failed to install $DEP. Please install it manually and restart the script. Exiting." true; exit 1; }
        print_message $GREEN "$DEP installed successfully." false
    done
}

# Function to ask the user where their AzerothCore is installed
ask_for_core_installation_path() {
    echo ""
    print_message $YELLOW "Where is your existing AzerothCore installation located?" true
    print_message $YELLOW "Press ENTER to use the default path: ($HOME/azerothcore)" false
    read -r user_input
    echo ""

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
    print_message $BLUE "This script provides an interactive way to manage your AzerothCore server, including:" true
    print_message $BLUE "  - Updating the AzerothCore source code." true
    print_message $BLUE "  - Rebuilding the server with the latest changes." true
    print_message $BLUE "  - Running your AzerothCore server (authserver and worldserver)." true
    print_message $BLUE "  - Updating server modules conveniently." true
    echo ""
    print_message $BLUE "----------------------------------------------" true
    echo ""
}

# Function to display the menu
show_menu() {
    echo ""
    print_message $BLUE "-------------------- MAIN MENU ---------------------" true
    print_message $YELLOW "Select an option from the menu below:" true
    echo ""
    print_message $YELLOW "[R] Rebuild and Run Server (1)" false
    print_message $YELLOW "[B] Rebuild Server Only (2)" false
    print_message $YELLOW "[S] Run Server Only (3)" false
    print_message $YELLOW "[M] Update Server Modules (4)" false
    print_message $YELLOW "[C] Show Current Configuration (5)" false
    print_message $YELLOW "[Q] Quit Script (6)" false
    echo ""
    print_message $BLUE "----------------------------------------------------" true
}

# Function to display current configuration
show_current_configuration() {
    echo ""
    print_message $BLUE "---------------- CURRENT CONFIGURATION ---------------" true
    echo ""
    print_message $GREEN "AzerothCore Directory: $AZEROTHCORE_DIR" false
    print_message $GREEN "Build Directory:       $BUILD_DIR" false
    print_message $GREEN "Auth Server Exec:    $AUTH_SERVER_EXEC" false
    print_message $GREEN "World Server Exec:   $WORLD_SERVER_EXEC" false
    
    if [ -n "$CORES" ]; then
        print_message $GREEN "Cores for Building:    $CORES" false
    else
        print_message $YELLOW "Cores for Building:    Not yet set (will be asked before build)." false
    fi
    echo ""
    print_message $BLUE "----------------------------------------------------" true
    echo ""
    read -n 1 -s -r -p "Press any key to return to the main menu..."
    echo "" # Add a newline after the key press
}

# Function to handle user input for the menu
handle_menu_choice() {
    echo ""
    read -p "$(echo -e "${YELLOW}${BOLD}Enter choice [R, B, S, M, C, Q, or 1-6]: ${NC}")" choice
    case $choice in
        1|[Rr])
            RUN_SERVER=true
            BUILD_ONLY=true
            ;;
        2|[Bb])
            RUN_SERVER=false
            BUILD_ONLY=true
            ;;
        3|[Ss])
            RUN_SERVER=true
            BUILD_ONLY=false
            ;;
        4|[Mm])
            MODULE_DIR="${AZEROTHCORE_DIR}/modules"
            update_modules "$MODULE_DIR"
            # Ensure flags are reset if returning from module update without other actions
            RUN_SERVER=false 
            BUILD_ONLY=false
            return # Return to main menu to avoid falling through
            ;;
        5|[Cc])
            show_current_configuration
            # Ensure flags are reset if returning from status display
            RUN_SERVER=false
            BUILD_ONLY=false
            return # Return to main menu to avoid falling through
            ;;
        6|[Qq])
            echo ""
            print_message $GREEN "Exiting. Thank you for using the AzerothCore Rebuild Tool!" true
            exit 0
            ;;
        *)
            echo ""
            print_message $RED "Invalid choice. Please select a valid option (R, B, S, M, C, Q, or 1-6)." false
            return
            ;;
    esac
}

# Function to ask for confirmation before updating or building
ask_for_update_confirmation() {
    echo ""
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
}

# Function to ask the user how many cores they want to use for the build
ask_for_cores() {
    # Get the number of available CPU cores
    AVAILABLE_CORES=$(nproc)
    echo ""
    print_message $YELLOW "CPU Core Selection for Building:" true
    print_message $YELLOW "Available CPU cores: $AVAILABLE_CORES" false
    print_message $YELLOW "Press ENTER to use all available cores ($AVAILABLE_CORES)." false
    read -p "$(echo -e "${YELLOW}${BOLD}Enter the number of cores to use (e.g., 1, 2, $AVAILABLE_CORES): ${NC}")" CORES
    echo ""

    # If user input is empty, default to using all cores
    if [ -z "$CORES" ]; then
        CORES=$AVAILABLE_CORES
        print_message $GREEN "Using all $CORES cores for the build." true
    elif ! [[ "$CORES" =~ ^[0-9]+$ ]]; then
        print_message $RED "Invalid input: '$CORES' is not a number. Defaulting to $AVAILABLE_CORES cores." true
        CORES=$AVAILABLE_CORES
    elif [ "$CORES" -eq 0 ]; then
        print_message $RED "You cannot use 0 cores. Defaulting to 1 core." true
        CORES=1
    elif [ "$CORES" -gt "$AVAILABLE_CORES" ]; then
        print_message $RED "You cannot use more cores than available ($AVAILABLE_CORES). Defaulting to $AVAILABLE_CORES cores." true
        CORES=$AVAILABLE_CORES
    else
        print_message $GREEN "Using $CORES core(s) for the build." true
    fi
}

# Function to build and install AzerothCore with spinner
build_and_install_with_spinner() {
    echo ""
    print_message $BLUE "--- Starting AzerothCore Build and Installation ---" true
    print_message $YELLOW "Building and installing AzerothCore... This may take a while." true

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
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    echo ""
    print_message $BLUE "--- Temporary Authserver Run (Test Build) ---" true
    print_message $YELLOW "Starting authserver and waiting for it to be ready..." true
    echo ""

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "Authserver executable not found at $AUTH_SERVER_EXEC. Build might have failed or path is incorrect."
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Wait for the authserver to be ready by checking if the server is listening on the specified port
    AUTH_SERVER_PORT=3724 
    print_message $CYAN "Waiting for authserver to be ready on port $AUTH_SERVER_PORT (max 60 seconds)..." false
    
    # Simple spinner
    for i in {1..60}; do
        echo -ne "${CYAN}Checking port $AUTH_SERVER_PORT: attempt $i/60 ${SPINNER[$((i % ${#SPINNER[@]}))]} \r${NC}"
        nc -z localhost $AUTH_SERVER_PORT && break
        sleep 1
    done
    echo -ne "\r${NC}                                                                          \r" # Clear spinner line

    if ! nc -z localhost $AUTH_SERVER_PORT; then
        handle_error "Authserver did not start or become ready on port $AUTH_SERVER_PORT within 60 seconds."
    fi

    print_message $GREEN "Authserver is ready! It will run for a few seconds then shut down." true
    sleep 5 

    # Kill the authserver process
    print_message $YELLOW "Shutting down temporary authserver..." true
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null 

    echo ""
    print_message $GREEN "Temporary authserver shutdown complete." true
    print_message $BLUE "Returning to main menu..." true
    sleep 2 # Give user time to read message
}

# Function to run worldserver and authserver in tmux session
run_tmux_session() {
    clear
    echo ""
    print_message $BLUE "--- Starting AzerothCore Servers in TMUX ---" true
    print_message $YELLOW "Attempting to start authserver and worldserver in a new TMUX session named 'azeroth'..." false
    echo ""

    # Start a new tmux session named "azeroth", attach to it immediately (we don't want to start it detached)
    tmux new-session -s azeroth -d || handle_error "Failed to create new TMUX session. Is TMUX installed and working?"

    # Wait for tmux session to initialize
    sleep 1

    # Split the screen horizontally
    tmux split-window -h

    # Rename the panes
    tmux send-keys -t azeroth:0.0 "rename-pane 'Authserver'" C-m
    tmux send-keys -t azeroth:0.1 "rename-pane 'Worldserver'" C-m

    # Run authserver in left pane
    tmux send-keys -t azeroth:0.0 "cd ~/azerothcore/env/dist/bin && ./authserver" C-m

    # Wait for the authserver to be ready (port 3724 open)
    AUTH_SERVER_PORT=3724
    print_message $CYAN "Waiting for authserver to be ready on port $AUTH_SERVER_PORT (max 60 seconds)..." false

    # Simple spinner for waiting
    SPINNER=('\' '|' '/' '-')
    for i in {1..60}; do
        echo -ne "${CYAN}Checking port $AUTH_SERVER_PORT: attempt $i/60 ${SPINNER[$((i % ${#SPINNER[@]}))]} \r${NC}"
        nc -z localhost $AUTH_SERVER_PORT && break
        sleep 1
    done
    echo -ne "\r${NC}                                                                          \r" # Clear spinner line

    if ! nc -z localhost $AUTH_SERVER_PORT; then
        handle_error "Authserver did not start or become ready on port $AUTH_SERVER_PORT within 60 seconds. Check TMUX session 'azeroth' for errors."
    fi
    
    print_message $GREEN "Authserver appears to be ready." true
    echo ""
    print_message $YELLOW "Starting worldserver in the other TMUX pane..." true
    # Once authserver is ready, start the worldserver in the right pane
    tmux send-keys -t azeroth:0.1 "cd $AZEROTHCORE_DIR/env/dist/bin && ./worldserver" C-m

    # Detach from the tmux session
    tmux detach -s azeroth

   # Print the updated, hilarious message after worldserver starts
    clear 
    echo ""
    print_message $CYAN "----------------------------------------------------------------------" true
    print_message $WHITE "\n  🚀 Congrats, Admin! AzerothCore should now be LIVE in TMUX! 🚀" true
    echo ""
    print_message $YELLOW "  You've just launched a world of adventure (and potential bugs)." true
    print_message $YELLOW "  Remember, with great power comes great responsibility... to check the logs." true
    echo ""
    print_message $CYAN "  To manage your server and witness the (hopefully orderly) chaos:" true
    print_message $WHITE "    ${BOLD}tmux attach -t azeroth${NC}" true
    echo ""
    print_message $CYAN "  Inside TMUX: Ctrl+B, then D to detach. Use arrow keys for panes." true
    print_message $CYAN "----------------------------------------------------------------------" true
    echo "" 
    exit 0
}

# Function to run a command and capture its output
run_command() {
    local command=$1
    local cwd=$2
    if [ -z "$cwd" ]; then
        eval "$command"
    else
        (cd "$cwd" && eval "$command")
    fi
}

# Function to update a specific module by pulling the latest changes
update_module() {
    local module_dir=$1
    echo -e "${BLUE}Pulling the latest changes for $module_dir...${NC}"
    run_command "git pull origin HEAD" "$module_dir"
    echo -e "${GREEN}Successfully updated $module_dir.${NC}"
}

# Function to check for updates in modules
update_modules() {
    local module_dir=$1

    if [ ! -d "$module_dir" ]; then
        echo ""
        print_message $RED "Error: The module directory '$module_dir' does not exist." true
        print_message $RED "Please ensure the path is correct or create the directory if necessary." true
        return
    fi

    echo ""
    print_message $BLUE "=== Starting Update Check for Modules in '$module_dir' ===" true
    echo ""

    modules_with_updates=()
    found_git_repo=false

    for module in "$module_dir"/*; do
        if [ -d "$module" ] && [ -d "$module/.git" ]; then
            found_git_repo=true
            print_message $GREEN "Found Git repository: $(basename "$module")" false

            # Fetch the latest changes from the remote repository
            print_message $CYAN "Fetching updates for $(basename "$module")..." false
            run_command "git fetch origin" "$module"

            local=$(run_command "git rev-parse @" "$module")
            remote=$(run_command "git rev-parse @{u}" "$module") # Check against upstream tracking branch

            if [ "$local" != "$remote" ]; then
                print_message $YELLOW "Update available for $(basename "$module")!" true
                modules_with_updates+=("$module")
            else
                print_message $GREEN "$(basename "$module") is already up to date." true
            fi
            echo "" 
        fi
    done

    if ! $found_git_repo; then
        echo ""
        print_message $YELLOW "No Git repositories found in subdirectories of '$module_dir'." true
        print_message $BLUE "Module updates are skipped if no .git directories are present in module subfolders." true
        return
    fi
    
    if [ ${#modules_with_updates[@]} -eq 0 ]; then
        echo ""
        print_message $GREEN "All modules with Git repositories are already up to date." true
        return
    fi

    while true; do
        echo ""
        print_message $CYAN "=== Module Update Options ===" true
        if [ ${#modules_with_updates[@]} -gt 0 ]; then
            print_message $YELLOW "The following modules have updates available:" true
            for module_path_item in "${modules_with_updates[@]}"; do
                print_message $YELLOW "  - $(basename "$module_path_item")" false
            done
        fi
        echo ""
        print_message $YELLOW "Select an action:" false
        print_message $YELLOW "[A] Update all listed modules (1)" false
        print_message $YELLOW "[S] Update specific modules (2)" false
        print_message $YELLOW "[Q] Quit module update (3)" false
        echo ""
        # Separate the prompt color from user input
        read -p "$(echo -e "${YELLOW}${BOLD}Enter choice ([A]ll, [S]pecific, [Q]uit, or 1-3): ${NC}")" choice
        echo ""

        if [[ "$choice" == "3" || "$choice" =~ ^[Qq]$ ]]; then
            print_message $GREEN "Exiting module update. Returning to main menu..." true
            return
        elif [[ "$choice" == "1" || "$choice" =~ ^[Aa]$ ]]; then
            print_message $YELLOW "Are you sure you want to update all listed modules? (y/n)" true
            read confirm
            if [[ "${confirm,,}" == "y" ]]; then
                for module_to_update in "${modules_with_updates[@]}"; do
                    update_module "$module_to_update"
                done
                echo ""
                print_message $GREEN "All selected modules have been updated successfully." true
                return 
            else
                print_message $RED "Update canceled." false
            fi
        elif [[ "$choice" == "2" || "$choice" =~ ^[Ss]$ ]]; then
            while true;
            do
                echo ""
                print_message $CYAN "--- Specific Module Update ---" true
                if [ ${#modules_with_updates[@]} -eq 0 ]; then
                    print_message $GREEN "No more modules available to update in this session." true
                    break # Break from specific module selection, back to A/S/Q
                fi
                print_message $YELLOW "Available modules for update:" false
                for i in "${!modules_with_updates[@]}"; do
                    print_message $YELLOW "$((i+1)). $(basename "${modules_with_updates[i]}")" false
                done
                print_message $YELLOW "$(( ${#modules_with_updates[@]} + 1 )). Back to previous menu" false
                echo ""
                read -p "$(echo -e "${YELLOW}${BOLD}Enter module number to update or $(( ${#modules_with_updates[@]} + 1 )) to go back: ${NC}")" specific_choice
                echo ""

                if ! [[ "$specific_choice" =~ ^[0-9]+$ ]]; then
                    print_message $RED "Invalid input: '$specific_choice' is not a number." true
                    continue
                fi

                if [ "$specific_choice" -eq $(( ${#modules_with_updates[@]} + 1 )) ]; then
                    break # Break from specific module selection, back to A/S/Q
                fi

                if [ "$specific_choice" -ge 1 ] && [ "$specific_choice" -le ${#modules_with_updates[@]} ]; then
                    module_index=$((specific_choice-1))
                    module_path_to_update=${modules_with_updates[$module_index]}
                    print_message $YELLOW "Are you sure you want to update $(basename "$module_path_to_update")? (y/n)" true
                    read confirm
                    if [[ "${confirm,,}" == "y" ]]; then
                        update_module "$module_path_to_update"
                        # Remove updated module from list
                        unset 'modules_with_updates[module_index]'
                        modules_with_updates=("${modules_with_updates[@]}") # Re-index array
                        print_message $GREEN "$(basename "$module_path_to_update") update process finished." true
                    else
                        print_message $RED "Update canceled for $(basename "$module_path_to_update")." false
                    fi
                else
                    print_message $RED "Invalid module number: $specific_choice. Please choose from the list." true
                fi
            done
        else
            print_message $RED "Invalid choice. Please enter A, S, Q, or 1-3." true
        fi
    done
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
        # Proceed with selected action only if flags are set
        if [ "$BUILD_ONLY" = true ] || [ "$RUN_SERVER" = true ]; then
            if [ "$BUILD_ONLY" = true ]; then
                ask_for_update_confirmation # This function now also calls ask_for_cores
                build_and_install_with_spinner
            fi

            if [ "$RUN_SERVER" = true ]; then
                # If only running the server, and no build was done, we still need to ensure paths are set.
                # ask_for_core_installation_path is called at the start, so paths should be known.
                run_tmux_session # This function now exits the script.
            elif [ "$BUILD_ONLY" = true ] && [ "$RUN_SERVER" = false ]; then
                # This case is for "Rebuild Only" - run temporary authserver
                run_authserver # This function no longer exits, returns to main_menu loop.
            fi
        # This case handles when only module update was chosen and completed.
        # Or if an invalid main menu choice was entered and returned.
        # No specific message needed here as update_modules gives feedback.
        fi
        
        # Reset action flags after execution for the next loop iteration
        RUN_SERVER=false
        BUILD_ONLY=false
    done
}

# Function to handle errors
handle_error() {
    echo "" # Add whitespace before error
    print_message $RED "--------------------------------------------------------------------" true
    print_message $RED "ERROR: $1" true
    if [[ "$1" == *"CMake configuration failed"* || "$1" == *"Build process ('make install') failed"* ]]; then
        print_message $RED "Suggestion: Check the logs in your build directory ($BUILD_DIR) for more details." true
    elif [[ "$1" == *"authserver executable not found"* ]];
        print_message $RED "Suggestion: Ensure AzerothCore was built successfully and the path is correct." true
    elif [[ "$1" == *"TMUX session"* ]];
        print_message $RED "Suggestion: Ensure TMUX is installed ('sudo apt install tmux') and functioning correctly." true
    fi
    print_message $RED "--------------------------------------------------------------------" true
    exit 1
}

# Run the main menu function when the script starts
main_menu
