#!/bin/bash

# Function to check the Git status of the script's directory
check_script_git_status() {
    print_message $BLUE "Checking script's Git repository status..." true
    # Determine the directory of the sourced script first
    local sourced_script_dir
    sourced_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

    # Attempt to find the top-level directory of the Git repository
    local repo_root
    repo_root=$(git -C "$sourced_script_dir" rev-parse --show-toplevel 2>/dev/null)

    if [ -z "$repo_root" ]; then
        SCRIPT_IS_GIT_REPO=false
        # Fallback to the sourced script dir for path context, even though it's not a git repo.
        SCRIPT_DIR_PATH="$sourced_script_dir"
        print_message $YELLOW "Could not determine the script's repository root. Not a git repo or git is not installed." true
        return
    fi

    SCRIPT_DIR_PATH="$repo_root"
    print_message $CYAN "Script repository root found at: $SCRIPT_DIR_PATH" false

    # Now that we have the repo root, we can perform the checks.
    # The .git directory check is implicitly handled by the success of `rev-parse --show-toplevel`.
    print_message $GREEN "  .git directory found." false

    # Confirm it's part of a Git working tree (somewhat redundant, but good for sanity check)
    if git -C "$SCRIPT_DIR_PATH" rev-parse --is-inside-work-tree &>/dev/null; then
        print_message $GREEN "  Script directory is part of a Git working tree." false
        # Check if 'origin' remote is configured
        if git -C "$SCRIPT_DIR_PATH" remote get-url origin &>/dev/null; then
            print_message $GREEN "  'origin' remote is configured for the script's repository." false
            SCRIPT_IS_GIT_REPO=true
            print_message $GREEN "Script is confirmed to be in a Git repository with an 'origin' remote." true
        else
            SCRIPT_IS_GIT_REPO=false
            print_message $YELLOW "  'origin' remote is NOT configured for the script's repository." false
            print_message $YELLOW "Script is in a Git repository, but 'origin' remote is missing." true
        fi
    else
        # This case is unlikely if `rev-parse --show-toplevel` succeeded, but included for robustness.
        SCRIPT_IS_GIT_REPO=false
        print_message $YELLOW "  Script directory is NOT part of a Git working tree (rev-parse check failed)." false
    fi
}

# Function to check for script updates from Git repository
check_for_script_updates() {
    # This function should only run if the script is in a git repo with 'origin' remote
    if [ "$SCRIPT_IS_GIT_REPO" != true ]; then
        return
    fi

    # Check for network connectivity to github.com first
    # -c 1: send 1 ICMP ECHO_REQUEST packet
    # -W 1: wait 1 second for a response (timeout)
    # &>/dev/null: suppress all output (stdout and stderr)
    if ! ping -c 1 -W 1 github.com &>/dev/null; then
        # Silently exit if github.com is not reachable
        return
    fi

    # Silently fetch updates from 'origin' remote to update local remote-tracking branches
    # -q: quiet mode, suppresses most output
    # Errors during fetch are intentionally ignored for a silent background check.
    # If fetch fails, subsequent comparisons will likely not indicate an update, which is acceptable.
    git -C "$SCRIPT_DIR_PATH" fetch origin -q

    # Get the commit hash of the local HEAD
    # 2>/dev/null: suppress stderr if the command fails (e.g., not a git repo, though SCRIPT_IS_GIT_REPO should prevent this)
    LOCAL_HEAD=$(git -C "$SCRIPT_DIR_PATH" rev-parse HEAD 2>/dev/null)
    # If LOCAL_HEAD could not be determined, something is wrong; silently exit.
    if [ -z "$LOCAL_HEAD" ]; then
        return
    fi

    # Get the commit hash of the remote's default branch using the 'origin/HEAD' symbolic ref.
    REMOTE_HEAD=$(git -C "$SCRIPT_DIR_PATH" rev-parse "origin/HEAD" 2>/dev/null)
    # If REMOTE_HEAD could not be determined (e.g., default branch deleted from remote, or never fetched),
    # silently exit.
    if [ -z "$REMOTE_HEAD" ]; then
        return
    fi

    # Compare the local HEAD commit with the remote HEAD commit.
    # If they are different, it means there's an update available.
    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
        SCRIPT_UPDATE_AVAILABLE=true
    else
        SCRIPT_UPDATE_AVAILABLE=false
    fi
}

# Function to download updates to AzerothCore
update_source_code() {
    print_message $YELLOW "Updating your AzerothCore source code..." true
    cd "$AZEROTHCORE_DIR" || handle_error "Failed to change directory to $AZEROTHCORE_DIR"

    # Fetch updates from the remote repository (only update tracking branches)
    git fetch origin || handle_error "Git fetch failed"

    # Check if there are any new commits in the remote repository
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/HEAD") # Use the symbolic-ref for the remote's default branch

    if [ "$LOCAL" != "$REMOTE" ]; then
        print_message $YELLOW "New commits found. Pulling updates..." true
        # Pull the latest changes from the configured upstream branch.
        git pull || handle_error "Git pull failed"
    else
        print_message $GREEN "No new commits. Local repository is up to date." true
    fi

    print_message $GREEN "AzerothCore source code updated successfully.\n" true
}

# Function to self-update the script from its Git repository
self_update_script() {
    print_message $BLUE "--- ACrebuild Script Self-Update ---" true

    # Ensure SCRIPT_DIR_PATH is set (should be by check_script_git_status)
    if [ -z "$SCRIPT_DIR_PATH" ]; then
        print_message $RED "Error: Script directory path not set. Cannot determine location for update." true
        return 1
    fi

    print_message $CYAN "Changing to script directory: $SCRIPT_DIR_PATH" false
    cd "$SCRIPT_DIR_PATH" || { print_message $RED "Error: Could not change to script directory '$SCRIPT_DIR_PATH'. Update aborted." true; return 1; }

    # Fetch Updates
    print_message $CYAN "Fetching remote updates for ACrebuild.sh..." false
    if ! git fetch origin; then
        print_message $RED "Error: 'git fetch origin' failed. Update aborted." true
        # Attempt to change back to original directory if possible, though not critical for script exit/restart
        OLDPWD_PREV="${OLDPWD:-$HOME}" # Fallback if OLDPWD is not set
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    # Check for Updates
    LOCAL_HEAD=$(git rev-parse HEAD)
    REMOTE_HEAD=$(git rev-parse "origin/HEAD")

    if [ -z "$REMOTE_HEAD" ]; then
        print_message $RED "Error: Could not determine the remote's default branch. Update aborted." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        print_message $GREEN "ACrebuild.sh is already up to date." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 0 # Success, no update needed
    fi

    # Updates Available
    print_message $YELLOW "An update is available for ACrebuild.sh." true
    print_message $YELLOW "  Current version: $LOCAL_HEAD" false
    print_message $YELLOW "  Available version: $REMOTE_HEAD" false

    # Check for Local Changes
    # `git status --porcelain` outputs machine-readable status. Empty means no changes.
    if [ -n "$(git status --porcelain)" ]; then
        print_message $RED "You have local uncommitted changes in the script directory." true
        print_message $RED "Please commit or stash them before updating to prevent conflicts." true
        print_message $RED "Update aborted." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    # Ask for Confirmation
    echo ""
    print_message $YELLOW "Do you want to pull the latest changes? (y/n)" true
    read -r updateConfirm
    if [[ ! "$updateConfirm" =~ ^[Yy]$ ]]; then
        print_message $GREEN "Self-update cancelled by user." false
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 0 # User cancelled, not an error
    fi

    # Perform Update
    print_message $CYAN "Pulling latest changes..." false
    if ! git pull; then
        print_message $RED "Error: 'git pull' failed. Update aborted. You might need to resolve conflicts manually." true
        OLDPWD_PREV="${OLDPWD:-$HOME}"
        cd "$OLDPWD_PREV" &>/dev/null
        return 1
    fi

    print_message $GREEN "ACrebuild.sh updated successfully!" true
    print_message $YELLOW "Restarting the script to apply changes..." true
    sleep 2 # Give user a moment to read the message

    # Change back to the original directory before exec, if possible,
    # so the restarted script starts from the same CWD as the user initially ran it from.
    OLDPWD_PREV="${OLDPWD:-$HOME}"
    cd "$OLDPWD_PREV" &>/dev/null

    local script_actual_name=$(basename "$0")
    exec "$SCRIPT_DIR_PATH/$script_actual_name" "$@" # Replace current script process with the new version
    # If exec fails for some reason (it shouldn't normally), exit to prevent unexpected behavior.
    print_message $RED "Error: Failed to restart the script with exec. Please restart it manually." true
    exit 1
}

# Function to apply SQL files from a module
apply_module_sql() {
    local module_dir=$1
    local sql_files_to_apply=()

    # Find all .sql files in the module's data directory
    if [ -d "$module_dir/data/sql/db_world" ]; then
        for sql_file in "$module_dir"/data/sql/db_world/*.sql; do
            sql_files_to_apply+=("$sql_file")
        done
    fi
    if [ -d "$module_dir/data/sql/db_char" ]; then
        for sql_file in "$module_dir"/data/sql/db_char/*.sql; do
            sql_files_to_apply+=("$sql_file")
        done
    fi
    if [ -d "$module_dir/data/sql/db_auth" ]; then
        for sql_file in "$module_dir"/data/sql/db_auth/*.sql; do
            sql_files_to_apply+=("$sql_file")
        done
    fi

    if [ ${#sql_files_to_apply[@]} -eq 0 ]; then
        print_message $GREEN "No new SQL files found for module $(basename "$module_dir")." false
        return
    fi

    print_message $YELLOW "The following SQL files were found for module $(basename "$module_dir"):" true
    for sql_file in "${sql_files_to_apply[@]}"; do
        print_message $YELLOW "  - $(basename "$sql_file")" false
    done

    print_message $YELLOW "Would you like to apply these SQL files now? (y/n)" true
    read -r apply_sql_choice
    if [[ "$apply_sql_choice" =~ ^[Yy]$ ]]; then
        for sql_file in "${sql_files_to_apply[@]}"; do
            local db_name=""
            if [[ "$sql_file" == *"db_world"* ]]; then
                db_name="$WORLD_DB_NAME"
            elif [[ "$sql_file" == *"db_char"* ]]; then
                db_name="$CHAR_DB_NAME"
            elif [[ "$sql_file" == *"db_auth"* ]]; then
                db_name="$AUTH_DB_NAME"
            fi

            if [ -n "$db_name" ]; then
                print_message $CYAN "Applying $(basename "$sql_file") to database '$db_name'..." false
                if is_docker_setup; then
                    cat "$sql_file" | docker compose exec -i -T -e MYSQL_PWD="$DB_PASS" ac-database mysql -u"$DB_USER" "$db_name"
                else
                    cat "$sql_file" | MYSQL_PWD="$DB_PASS" mysql -u"$DB_USER" "$db_name"
                fi
                if [ $? -eq 0 ]; then
                    print_message $GREEN "Successfully applied $(basename "$sql_file")." false
                else
                    print_message $RED "Error applying $(basename "$sql_file")." true
                fi
            fi
        done
    else
        print_message $CYAN "Skipping SQL import for module $(basename "$module_dir")." false
    fi
}

# Function to update a specific module by pulling the latest changes
update_module() {
    local module_dir=$1
    print_message $BLUE "Attempting to pull latest changes for module $(basename "$module_dir")..." false
    if run_command "git pull" "$module_dir"; then
        print_message $GREEN "Successfully updated module $(basename "$module_dir")." false
        apply_module_sql "$module_dir"
    else
        print_message $RED "Failed to update module $(basename "$module_dir"). Please check output above for errors (e.g., merge conflicts, detached HEAD, network issues)." true
    fi
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
        print_message $BLUE "============ MODULE UPDATE OPTIONS ============" true # Changed heading
        echo ""
        if [ ${#modules_with_updates[@]} -gt 0 ]; then
            print_message $YELLOW "The following modules have updates available:" true
            for module_path_item in "${modules_with_updates[@]}"; do
                # Using a bullet point for each module
                print_message $YELLOW "  • $(basename "$module_path_item")" false
            done
        fi
        echo ""
        print_message $CYAN "Select an action:" true # Changed to CYAN for sub-heading
        echo ""
        print_message $YELLOW "  [1] Update All Modules           (Shortcut: A)" false
        print_message $YELLOW "  [2] Update Specific Modules      (Shortcut: S)" false
        print_message $YELLOW "  [3] Quit Module Update           (Shortcut: Q)" false
        echo ""
        print_message $BLUE "-----------------------------------------------" true # Added footer
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
                # Changed heading for specific module update
                print_message $BLUE "-------- SPECIFIC MODULE UPDATE --------" true
                echo ""
                if [ ${#modules_with_updates[@]} -eq 0 ]; then
                    print_message $GREEN "No more modules available to update in this session." true
                    # Added a footer here as well for consistency before breaking
                    print_message $BLUE "-----------------------------------------------" true
                    break # Break from specific module selection, back to A/S/Q
                fi
                print_message $YELLOW "Available modules for update:" false
                for i in "${!modules_with_updates[@]}"; do
                    # Formatting as "[i+1] module_name"
                    print_message $YELLOW "  [$((i+1))] $(basename "${modules_with_updates[i]}")" false
                done
                local back_option_number=$(( ${#modules_with_updates[@]} + 1 ))
                print_message $YELLOW "  [$back_option_number] Back to previous menu" false
                echo ""
                print_message $BLUE "-----------------------------------------------" true # Added footer
                # Updated prompt to reflect the dynamic back_option_number
                read -p "$(echo -e "${YELLOW}${BOLD}Enter module number to update or $back_option_number to go back: ${NC}")" specific_choice
                echo ""

                if ! [[ "$specific_choice" =~ ^[0-9]+$ ]]; then
                    print_message $RED "Invalid input: '$specific_choice' is not a number." true
                    continue
                fi

                # Using the dynamic back_option_number for comparison
                if [ "$specific_choice" -eq "$back_option_number" ]; then
                    break # Break from specific module selection, back to A/S/Q
                fi

                if [ "$specific_choice" -ge 1 ] && [ "$specific_choice" -le "${#modules_with_updates[@]}" ]; then
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

                        # Check if all modules have been updated
                        if [ ${#modules_with_updates[@]} -eq 0 ]; then
                            print_message $GREEN "All available module updates completed. Returning to main menu..." true
                            return # Return from update_modules to the main menu loop
                        fi
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
