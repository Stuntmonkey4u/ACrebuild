#!/bin/bash

# Function to check if essential dependencies are installed
check_dependencies() {
    echo ""
    print_message $BLUE "Checking for essential dependencies..." true

    local dependencies_met=false
    while ! $dependencies_met; do
        MISSING_DEPENDENCIES=()

        if is_docker_setup; then
            local DEPENDENCIES=("git" "docker")
            print_message $CYAN "Docker mode: checking for git and docker..." false
            for DEP in "${DEPENDENCIES[@]}"; do
                if ! command -v "$DEP" &>/dev/null; then
                    MISSING_DEPENDENCIES+=("$DEP")
                fi
            done
            # Ensure we have the full path to docker exec
            if [ -z "$DOCKER_EXEC_PATH" ] && command -v docker &>/dev/null; then
                DOCKER_EXEC_PATH=$(command -v docker)
            fi
        else
            local DEPENDENCIES=("git" "cmake" "make" "clang" "clang++" "tmux" "nc")
            print_message $CYAN "Standard mode: checking for build and server tools..." false
            for DEP in "${DEPENDENCIES[@]}"; do
                if ! command -v "$DEP" &>/dev/null; then
                    MISSING_DEPENDENCIES+=("$DEP")
                fi
            done

            if command -v dpkg &> /dev/null; then
                if ! dpkg -s libboost-all-dev &> /dev/null; then
                    MISSING_DEPENDENCIES+=("libboost-all-dev")
                fi
            fi
        fi

        if [ ${#MISSING_DEPENDENCIES[@]} -eq 0 ]; then
            print_message $GREEN "All required dependencies are installed.\n" true
            dependencies_met=true
        else
            print_message $YELLOW "The following dependencies are required but missing: ${MISSING_DEPENDENCIES[*]}" true
            print_message $YELLOW "Would you like to try and install them now? (y/n)" true
            read -r answer
            if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                install_dependencies
            else
                print_message $RED "Critical: Cannot proceed without the required dependencies. Exiting..." true
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
            declare -A dep_map
            dep_map["git"]="git"
            dep_map["cmake"]="cmake"
            dep_map["make"]="make"
            dep_map["clang"]="clang"
            dep_map["clang++"]="clang"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="netcat-openbsd"
            dep_map["docker"]="docker.io"
            dep_map["libboost-all-dev"]="libboost-all-dev"

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
                if [ -n "${dep_map[$dep]}" ]; then
                    packages_to_install+=("${dep_map[$dep]}")
                fi
            done
            packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u))

            if [ ${#packages_to_install[@]} -gt 0 ]; then
                sudo apt install -y "${packages_to_install[@]}" || { print_message $RED "Error: Failed to install packages using apt. Please install them manually." true; exit 1; }
            fi
            ;;
        "yum")
            print_message $CYAN "Using 'yum' package manager." false
            sudo yum groupinstall -y "Development Tools"
            declare -A dep_map
            dep_map["cmake"]="cmake"
            dep_map["clang"]="clang"
            dep_map["tmux"]="tmux"
            dep_map["nc"]="nmap-ncat"
            dep_map["docker"]="docker"

            local packages_to_install=()
            for dep in "${MISSING_DEPENDENCIES[@]}"; do
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
            dep_map["clang"]="llvm"
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
