#!/bin/bash

# This file contains all the global variable definitions for the script.
# It should be sourced first by the main script to ensure these variables
# are available to all other library files.

# SERVER_CONFIG_FILES is an array, will be kept as is for now or managed differently if needed.
SERVER_CONFIG_FILES=("authserver.conf" "worldserver.conf") # Array of config files to back up

# Process Management Variables
TMUX_SESSION_NAME="azeroth"
AUTHSERVER_PANE_TITLE="Authserver" # Used in current script, good to formalize
WORLDSERVER_PANE_TITLE="Worldserver" # Used in current script, good to formalize
WORLDSERVER_CONSOLE_COMMAND_STOP="server shutdown 1" # 300 seconds = 5 minutes for graceful shutdown

# Configuration File Variables
CONFIG_DIR="${HOME}/.ACrebuild"
CONFIG_FILE="${CONFIG_DIR}/ACrebuild.conf"

# Default values for configuration
DEFAULT_AZEROTHCORE_DIR="/root/azerothcore-wotlk"
DEFAULT_BACKUP_DIR="${HOME}/ac_backups"
DEFAULT_DB_USER="acore"
DEFAULT_DB_USER_DOCKER="root" # Docker-specific default user
DEFAULT_DB_PASS=""
DEFAULT_AUTH_DB_NAME="acore_auth"
DEFAULT_CHAR_DB_NAME="acore_characters"
DEFAULT_WORLD_DB_NAME="acore_world"
DEFAULT_SERVER_CONFIG_DIR_PATH_SUFFIX="env/dist/etc"
DEFAULT_SERVER_LOG_DIR_PATH_SUFFIX="env/dist/logs"
DEFAULT_AUTH_SERVER_LOG_FILENAME="Auth.log"
DEFAULT_WORLD_SERVER_LOG_FILENAME="Server.log"
DEFAULT_ERROR_LOG_FILENAME="Errors.log"
DEFAULT_SCRIPT_LOG_DIR="${HOME}/.ACrebuild/logs"
DEFAULT_SCRIPT_LOG_FILENAME="ACrebuild.log"
DEFAULT_CRON_LOG_FILENAME="cron_backup.log"
DEFAULT_POST_SHUTDOWN_DELAY_SECONDS=10
DEFAULT_AUTH_PORT=3724
DEFAULT_WORLD_PORT=8085
DEFAULT_CORES_FOR_BUILD=""
DEFAULT_USE_DOCKER=false

# Runtime variables - These will be loaded from config or set to default by load_config()
AZEROTHCORE_DIR=""
DOCKER_EXEC_PATH=""
BUILD_DIR=""
SCRIPT_DIR_PATH=""
SCRIPT_IS_GIT_REPO=false
AUTH_SERVER_EXEC=""
WORLD_SERVER_EXEC=""
BACKUP_DIR=""
DB_USER=""
DB_PASS=""
AUTH_DB_NAME=""
CHAR_DB_NAME=""
WORLD_DB_NAME=""
SERVER_CONFIG_DIR_PATH=""
SERVER_LOG_DIR_PATH=""
AUTH_SERVER_LOG_FILENAME="" # Renamed from AUTH_SERVER_LOG_FILE to avoid confusion with full path for clarity
WORLD_SERVER_LOG_FILENAME="" # Renamed from WORLD_SERVER_LOG_FILE to avoid confusion with full path for clarity
ERROR_LOG_FILENAME=""
# SCRIPT_LOG_DIR_CONF and SCRIPT_LOG_FILENAME_CONF were part of an earlier idea and are no longer used.
# SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME are loaded directly, and print_message handles pre-config state.
SCRIPT_LOG_FILE="" # Actual path to script log file, derived by load_config from SCRIPT_LOG_DIR and SCRIPT_LOG_FILENAME
POST_SHUTDOWN_DELAY_SECONDS=""
AUTH_PORT=""
WORLD_PORT=""
CORES="" # Runtime variable, takes its value from CORES_FOR_BUILD in config.
USE_DOCKER=""

# Runtime flags for controlling the main loop
BUILD_ONLY=false
RUN_SERVER=false
