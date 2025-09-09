#!/bin/bash

# Function to check if essential dependencies are installed
check_dependencies() {
    echo""
    print_message $BLUE "Checking for essential dependencies..." true

    while true; do
        MISSING_DEPENDENCIES=() # Initialize or clear the array for each check

        # List of dependencies to check
        local DEPENDENCIES=("git" "cmake" "make" "clang" "clang++" "tmux" "nc")
        for DEP in "${DEPENDENCIES[@]}"; do
            if ! command -v "$DEP" &>/dev/null; then
                MISSING_DEPENDENCIES+=("$DEP")
            fi
        done

        # Conditionally check for Docker if it's a Docker-based setup
        if is_docker_setup; then
            if ! command -v docker &>/dev/null; then
                MISSING_DEPENDENCIES+=("docker")
            fi
        fi

        # Evaluate if dependencies are met
        if [ ${#MISSING_DEPENDENCIES[@]} -eq 0 ]; then
            print_message $GREEN "All required dependencies are installed.\n" true
            break # Exit the loop, success
        else
            # Announce missing dependencies
            print_message $YELLOW "The following dependencies are required but missing: ${MISSING_DEPENDENCIES[*]}" true
            print_message $YELLOW "Would you like to try and install them now? (y/n)" true
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                install_dependencies # This function uses the global MISSING_DEPENDENCIES array and exits on failure
                print_message $BLUE "Re-checking dependencies after installation attempt..." true
                # The loop will now repeat and re-check
            else
                print_message $RED "--------------------------------------------------------------------" true
                print_message $RED "Critical: Cannot proceed without the required dependencies. Exiting..." true
                print_message $RED "--------------------------------------------------------------------" true
                exit 1
            fi
        fi
    done
}

# Function to install the missing dependencies
install_dependencies() {
    print_message $BLUE "Attempting to install missing dependencies..." true
    local pkg_manager
    pkg_manager=$(get_package_manager)

    case $pkg_manager in
        "apt")
            print_message $CYAN "Using 'apt' package manager." false
            sudo apt update
            # Map generic dependency names to specific package names for apt
            declare -A dep_map
            dep_map["git"]="git"
            dep_map["cmake"]="cmake"
            dep_map["make"]="make"
            dep_map["clang"]="clang"
            dep_map["clang++"]="clang"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="netcat-openbsd"
            dep_map["docker"]="docker.io" # Use docker.io for simplicity

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
                if [ -n "${dep_map[$dep]}" ]; then
                    packages_to_install+=("${dep_map[$dep]}")
                fi
            done
            # Remove duplicates
            packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u))

            if [ ${#packages_to_install[@]} -gt 0 ]; then
                sudo apt install -y "${packages_to_install[@]}" || { print_message $RED "Error: Failed to install packages using apt. Please install them manually." true; exit 1; }
            fi
            ;;
        "yum")
            print_message $CYAN "Using 'yum' package manager." false
            # For yum, it's often easier to install groups and then individual packages.
            # Assuming 'Development Tools' covers git, make, gcc (for clang).
            sudo yum groupinstall -y "Development Tools"

            declare -A dep_map
            dep_map["cmake"]="cmake"
            dep_map["clang"]="clang"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="nmap-ncat" # Provides nc
            dep_map["docker"]="docker"

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
                 # git and make are in Dev Tools, so we only need to check for the others
                if [[ "$dep" != "git" && "$dep" != "make" && "$dep" != "clang++" ]]; then
                    if [ -n "${dep_map[$dep]}" ]; then
                        packages_to_install+=("${dep_map[$dep]}")
                    fi
                fi
            done
            packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u))

            if [ ${#packages_to_install[@]} -gt 0 ]; then
                sudo yum install -y "${packages_to_install[@]}" || { print_message $RED "Error: Failed to install packages using yum. Please install them manually." true; exit 1; }
            fi
            ;;
        "pacman")
            print_message $CYAN "Using 'pacman' package manager." false
            # For pacman, 'base-devel' group is key.
            sudo pacman -Syu --noconfirm
            sudo pacman -S --noconfirm --needed base-devel

            declare -A dep_map
            dep_map["git"]="git"
            dep_map["cmake"]="cmake"
            dep_map["clang"]="clang"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="openbsd-netcat"
            dep_map["docker"]="docker"

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
                if [[ "$dep" != "make" && "$dep" != "clang++" ]]; then
                     if [ -n "${dep_map[$dep]}" ]; then
                        packages_to_install+=("${dep_map[$dep]}")
                    fi
                fi
            done
            packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u))

            if [ ${#packages_to_install[@]} -gt 0 ]; then
                sudo pacman -S --noconfirm --needed "${packages_to_install[@]}" || { print_message $RED "Error: Failed to install packages using pacman. Please install them manually." true; exit 1; }
            fi
            ;;
        "brew")
            print_message $CYAN "Using 'brew' package manager (for macOS)." false
            brew update

            declare -A dep_map
            dep_map["git"]="git"
            dep_map["cmake"]="cmake"
            dep_map["make"]="make"
            dep_map["clang"]="llvm" # Brew uses llvm for clang
            dep_map["clang++"]="llvm"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="netcat"
            dep_map["docker"]="docker"

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
                if [ -n "${dep_map[$dep]}" ]; then
                    packages_to_install+=("${dep_map[$dep]}")
                fi
            done
            packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u))

            if [ ${#packages_to_install[@]} -gt 0 ]; then
                brew install "${packages_to_install[@]}" || { print_message $RED "Error: Failed to install packages using brew. Please install them manually." true; exit 1; }
            fi
            ;;
        "unsupported")
            print_message $RED "Unsupported package manager." true
            print_message $RED "Please install the following dependencies manually: ${MISSING_DEPENDENCIES[*]}" true
            exit 1
            ;;
    esac
}
