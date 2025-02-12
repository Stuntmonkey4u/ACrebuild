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
BACKUP_DIR="$HOME/azerothcore_backups"

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
    print_message $YELLOW "5) Backup and Restore Database" false
    print_message $YELLOW "6) Exit" false
    echo ""
}

handle_menu_choice() {
    read -p "Enter choice [1-6]: " choice
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
            MODULE_DIR="${AZEROTHCORE_DIR}/modules"
            update_modules "$MODULE_DIR"
            ;;
        5)
            while true; do
                show_backup_menu
                handle_backup_menu_choice
            done
            ;;
        6)
            print_message $GREEN "Exiting. Thank you for using the AzerothCore rebuild tool!" true
            exit 0
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-6)." false
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
    if ! make -j "$CORES" install; then
        # If the build fails, offer to run "make clean"
        print_message $YELLOW "Build failed. Would you like to run 'make clean' to attempt to fix the issue? (y/n)" true
        read -r clean_answer
        if [[ "$clean_answer" =~ ^[Yy]$ ]]; then
            print_message $YELLOW "Running 'make clean' to attempt recovery..." true
            make clean || { print_message $RED "'make clean' failed. Exiting." true; exit 1; }
            # After clean, try building again
            print_message $YELLOW "Retrying the build..." true
            if ! make -j "$CORES" install; then
                handle_error "Build failed again after running make clean."
            fi
        else
            handle_error "Build failed and clean was not run. Exiting."
        fi
    fi

    print_message $GREEN "AzerothCore build and installation completed successfully." true
}

# Function to run authserver for 60 seconds with countdown
run_authserver() {
    print_message $YELLOW "Starting authserver and waiting for it to be ready..." true

    # Check if authserver exists
    if [ ! -f "$AUTH_SERVER_EXEC" ]; then
        handle_error "authserver executable not found at $AUTH_SERVER_EXEC"
    fi

    # Run the authserver in the background
    "$AUTH_SERVER_EXEC" &
    AUTH_SERVER_PID=$!

    # Wait for the authserver to be ready by checking if the server is listening on the specified port
    AUTH_SERVER_PORT=3724  # Replace this with the actual port your authserver uses
    echo -ne "${GREEN}Waiting for authserver to be ready on port $AUTH_SERVER_PORT...\r"

    # Wait for authserver to start accepting connections (max wait 60 seconds)
    for i in {1..60}; do
        # Check if port is open
        nc -z localhost $AUTH_SERVER_PORT && break
        sleep 1
    done

    # If we didn't break out of the loop, the server isn't ready
    if ! nc -z localhost $AUTH_SERVER_PORT; then
        handle_error "Authserver did not start within the expected time frame."
    fi

    echo -ne "${GREEN}Authserver is ready! Waiting 5 seconds before closing...\r"
    sleep 5

    # Kill the authserver process
    kill "$AUTH_SERVER_PID"
    wait "$AUTH_SERVER_PID" 2>/dev/null  # Wait for the authserver process to properly exit

    print_message $GREEN "Authserver shutdown complete. Exiting. Thank you for using the AzerothCore rebuild tool!" true
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

    # Run authserver in left pane
    tmux send-keys -t azeroth:0.0 "cd ~/azerothcore/env/dist/bin && ./authserver" C-m

    # Wait for the authserver to be ready (port 3724 open)
    AUTH_SERVER_PORT=3724  # Port used by authserver
    echo -ne "${GREEN}Waiting for authserver to be ready on port $AUTH_SERVER_PORT...\r"

    # Wait for authserver to start accepting connections (max wait 60 seconds)
    for i in {1..60}; do
        # Check if port is open
        nc -z localhost $AUTH_SERVER_PORT && break
        sleep 1
    done

    # If we didn't break out of the loop, the authserver isn't ready
    if ! nc -z localhost $AUTH_SERVER_PORT; then
        handle_error "Authserver did not start within the expected time frame."
    fi

    # Once authserver is ready, start the worldserver in the right pane
    tmux send-keys -t azeroth:0.1 "cd ~/azerothcore/env/dist/bin && ./worldserver" C-m

    # Detach from the tmux session
    tmux detach -s azeroth

   # Print the updated, hilarious message after worldserver starts
    clear  # Clear the screen before displaying the message
    print_message $CYAN "----------------------------------------------------"
    print_message $WHITE "\n  Congrats, Admin! AzerothCore is officially live!"
    echo ""
    print_message $YELLOW "  You have just unleashed a digital world where anything can go wrong."
    print_message $YELLOW "  But hey, that’s what backups are for, right?"
    echo ""
    print_message $CYAN "  Now sit back, relax, and wait for the chaos to begin."
    print_message $CYAN "  Or... maybe just keep an eye on it. You know, for safety."
    echo ""
    print_message $WHITE "  To rule Azeroth, type: 'tmux attach -t azeroth'"
    print_message $CYAN "----------------------------------------------------" 
    echo ""  # Add some space before closing
    exit
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
        echo -e "${RED}Error: The directory $module_dir does not exist.${NC}"
        return
    fi

    echo -e "${BLUE}=== Starting Update Check for Modules ===${NC}"
    echo -e "${CYAN}Checking for updates in the directory: $module_dir${NC}"

    modules_with_updates=()

    for module in "$module_dir"/*; do
        if [ -d "$module" ] && [ -d "$module/.git" ]; then
            echo -e "${GREEN}Found Git repository: $module${NC}"

            # Fetch the latest changes from the remote repository
            run_command "git fetch origin" "$module"

            local=$(run_command "git rev-parse @" "$module")
            remote=$(run_command "git rev-parse @{u}" "$module")

            if [ "$local" != "$remote" ]; then
                echo -e "${YELLOW}Update available for $(basename $module)!${NC}"
                modules_with_updates+=("$module")
            else
                echo -e "${GREEN}$(basename $module) is already up to date.${NC}"
            fi
            echo
        fi
    done

    if [ ${#modules_with_updates[@]} -eq 0 ]; then
        echo -e "${GREEN}No updates found for any modules.${NC}"
        return
    fi

    while true; do
        echo -e "${CYAN}=== Available Updates ===${NC}"

        if [ ${#modules_with_updates[@]} -gt 0 ]; then
            echo -e "${YELLOW}The following modules have updates available:${NC}"
            for module in "${modules_with_updates[@]}"; do
                echo -e "- $(basename $module)"
            done
        fi

        echo -e "\n${YELLOW}Select an action:${NC}"
        echo -e "1. Update all modules"
        echo -e "2. Update specific modules"
        echo -e "3. Quit"

        # Separate the prompt color from user input
        echo -e -n "${CYAN}Enter your choice (1, 2, or 3): ${NC}"
        read choice

        if [ "$choice" == "3" ]; then
            echo -e "${GREEN}Exiting without updating any modules.${NC}"
            return
        elif [ "$choice" == "1" ]; then
            echo -e -n "${YELLOW}Are you sure you want to update all modules? (y/n): ${NC}"
            read confirm
            if [ "${confirm,,}" == "y" ]; then
                for module in "${modules_with_updates[@]}"; do
                    update_module "$module"
                done
                echo -e "${GREEN}All selected modules have been updated successfully. Exiting...${NC}"
                return
            else
                echo -e "${RED}Update canceled.${NC}"
            fi
        elif [ "$choice" == "2" ]; then
            while true; do
                echo -e "${CYAN}Available modules for update:${NC}"
                if [ ${#modules_with_updates[@]} -eq 0 ]; then
                    echo -e "${GREEN}No more modules available to update.${NC}"
                    return  # Return to main menu
                fi
                for i in "${!modules_with_updates[@]}"; do
                    echo -e "$((i+1)). $(basename ${modules_with_updates[i]})"
                done
                echo -e "$(( ${#modules_with_updates[@]} + 1 )). Back"

                echo -e -n "${YELLOW}Enter module number to update or $(( ${#modules_with_updates[@]} + 1 )) to go back: ${NC}"
                read specific_choice

                if [ "$specific_choice" -eq $(( ${#modules_with_updates[@]} + 1 )) ]; then
                    # Break out of this specific modules menu
                    break
                fi

                if [ "$specific_choice" -ge 1 ] && [ "$specific_choice" -le ${#modules_with_updates[@]} ]; then
                    module_index=$((specific_choice-1))
                    module_path=${modules_with_updates[$module_index]}
                    echo -e -n "${YELLOW}Are you sure you want to update $(basename $module_path)? (y/n): ${NC}"
                    read confirm
                    if [ "${confirm,,}" == "y" ]; then
                        update_module "$module_path"
                        unset modules_with_updates[$module_index]
                        modules_with_updates=("${modules_with_updates[@]}") # Re-index array
                    else
                        echo -e "${RED}Update canceled for $(basename $module_path).${NC}"
                    fi
                else
                    echo -e "${RED}Invalid module number: $specific_choice${NC}"
                fi
            done
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
# Function to prompt the user for MySQL credentials
get_mysql_credentials() {
    print_message $CYAN "Please enter your MySQL username:" true
    read -p "MySQL Username: " MYSQL_USER
    print_message $CYAN "Please enter your MySQL password:" true
    read -s -p "MySQL Password: " MYSQL_PASSWORD
    echo ""  # For a clean line after the password input
}

# Function to create the backup directory if it doesn't exist
create_backup_directory() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        if [ $? -eq 0 ]; then
            print_message $GREEN "Backup directory created: $BACKUP_DIR" true
        else
            print_message $RED "Error creating backup directory: $BACKUP_DIR" true
            exit 1
        fi
    fi
}



# Function to list available databases
list_databases() {
    # Connect to MySQL and list databases
    DATABASES=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" | tail -n +2)
    if [ $? -ne 0 ]; then
        print_message $RED "Error: Unable to connect to MySQL with the provided credentials." true
        return 1
    fi

    print_message $CYAN "Available Databases:" true
    echo "$DATABASES"
}

# Function to select databases for backup
select_databases_to_backup() {
    # List available databases
    list_databases
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Ask the user which databases to back up
    print_message $YELLOW "Enter the names of databases to back up, separated by space (or press Enter to backup all):" true
    read -r selected_databases

    if [ -z "$selected_databases" ]; then
        # If no selection, default to backup of known important databases
        selected_databases="acore_auth acore_characters acore_playerbots acore_world"
    fi

    # Backup the selected databases
    for db in $selected_databases; do
        if echo "$DATABASES" | grep -q "^$db$"; then
            backup_database "$db"
        else
            print_message $RED "Database '$db' does not exist on this server." true
        fi
    done
}

# Function to back up a database
backup_database() {
    local db="$1"
    print_message $CYAN "Backing up database: $db..." true

    # Ensure the backup directory exists before starting backup
    create_backup_directory

    # Get the current date to name the backup file
    DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    BACKUP_FILE="$BACKUP_DIR/${db}_backup_$DATE.sql.gz"

    # Run mysqldump and compress the backup
    mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$db" | gzip > "$BACKUP_FILE"

    # Check if the backup was successful
    if [ $? -eq 0 ]; then
        print_message $GREEN "Backup successful! $db saved as $BACKUP_FILE" true
    else
        print_message $RED "Backup failed for $db." true
    fi
}

# Function to list the existing backups
list_backups() {
    # Ensure the backup directory exists before listing backups
    create_backup_directory

    print_message $CYAN "Listing all backups in $BACKUP_DIR..." true
    ls -lh "$BACKUP_DIR"
}

# Function to restore a database from a backup
restore_database() {
print_message $CYAN "Listing all backups in $BACKUP_DIR..." true
    ls -lh "$BACKUP_DIR"

    # Ask the user which backup to restore
    print_message $YELLOW "Enter the backup file name (with .sql.gz) to restore from:" true
    read -r backup_file

    # Ensure the file exists
    if [ ! -f "$BACKUP_DIR/$backup_file" ]; then
        print_message $RED "Backup file $backup_file does not exist." true
        return
    fi

    # Restore the database from the backup file
    gunzip < "$BACKUP_DIR/$backup_file" | mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD"

    # Check if the restore was successful
    if [ $? -eq 0 ]; then
        print_message $GREEN "Database restore successful from $backup_file" true
    else
        print_message $RED "Database restore failed." true
    fi
}

# Function to delete backups older than a specified number of days
delete_old_backups() {
    DAYS_TO_KEEP=7 # Number of days to keep backups
    find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +$DAYS_TO_KEEP -exec rm {} \;
    print_message $GREEN "Deleted backups older than $DAYS_TO_KEEP days." true
}

# Function to show the backup menu
show_backup_menu() {
    echo ""
    print_message $YELLOW "Select an option for database backup:" true
    echo ""
    print_message $YELLOW "1) Create a New Backup" false
    print_message $YELLOW "2) List Existing Backups" false
    print_message $YELLOW "3) Restore a Backup" false
    print_message $YELLOW "4) Delete Old Backups" false
    print_message $YELLOW "5) Return to Main Menu" false
    echo ""
}

# Function to handle the backup menu input
handle_backup_menu_choice() {
    read -p "Enter choice [1-5]: " choice
    case $choice in
        1)
            get_mysql_credentials
            select_databases_to_backup
            ;;
        2)
            list_backups
            ;;
        3)
            restore_database
            ;;
        4)
            delete_old_backups
            ;;
        5)
            main_menu
            ;;
        *)
            print_message $RED "Invalid choice. Please select a valid option (1-5)." false
            return
            ;;
    esac
}

# Run the main menu function when the script starts
main_menu
