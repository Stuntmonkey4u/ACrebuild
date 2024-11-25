#!/bin/bash

# Define color scheme
CYAN='\033[0;36m'
GREEN='\033[38;5;82m'
YELLOW='\033[1;33m'
RED='\033[38;5;196m'
BLUE='\033[38;5;117m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

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

# Main execution block
MODULE_DIR="$HOME/azerothcore/modules"  # Change this to your modules directory if needed

update_modules "$MODULE_DIR"
