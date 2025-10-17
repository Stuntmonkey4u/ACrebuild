#!/bin/bash

# A unique identifier for our cron job to find and manage it
CRON_COMMENT_TAG="ACREBUILD_BACKUP_JOB"

# Function to check if the cron service is running
check_cron_service() {
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet cron || systemctl is-active --quiet crond; then
            return 0 # Service is active
        else
            return 1 # Service is not active
        fi
    elif command -v pgrep &>/dev/null; then
        if pgrep -x "cron" >/dev/null || pgrep -x "crond" >/dev/null; then
            return 0 # Process is running
        else
            return 1 # Process is not running
        fi
    fi
    # Fallback if no check method is available
    return 2
}

# Function to setup the automated backup schedule
setup_backup_schedule() {
    print_message $BLUE "--- Setup Automated Backup Schedule ---" true

    # Check for saved password
    if [ -z "$DB_PASS" ]; then
        print_message $RED "Error: A database password must be saved in the configuration to set up automated backups." true
        print_message $YELLOW "Please go to the Backup/Restore menu, run a manual backup, and choose to save the password." true
        return 1
    fi

    # Scheduling wizard
    local schedule_choice
    print_message $YELLOW "Choose a schedule frequency:" true
    print_message $CYAN "  [1] Daily" false
    print_message $CYAN "  [2] Weekly" false
    read -p "Enter choice [1-2]: " schedule_choice

    local cron_schedule=""
    local day_of_week
    local hour
    local minute

    print_message $YELLOW "Enter the time for the backup (24-hour format)." true
    read -p "Hour (0-23): " hour
    read -p "Minute (0-59): " minute

    # Basic validation
    if ! [[ "$hour" =~ ^[0-9]+$ && "$hour" -ge 0 && "$hour" -le 23 ]] ||        ! [[ "$minute" =~ ^[0-9]+$ && "$minute" -ge 0 && "$minute" -le 59 ]]; then
        print_message $RED "Invalid time format. Aborting." true
        return 1
    fi

    case "$schedule_choice" in
        1) # Daily
            cron_schedule="$minute $hour * * *"
            ;;
        2) # Weekly
            read -p "Day of week (0=Sun, 1=Mon, ..., 6=Sat): " day_of_week
            if ! [[ "$day_of_week" =~ ^[0-6]$ ]]; then
                print_message $RED "Invalid day of week. Aborting." true
                return 1
            fi
            cron_schedule="$minute $hour * * $day_of_week"
            ;;
        *)
            print_message $RED "Invalid choice. Aborting." true
            return 1
            ;;
    esac

    # Construct the command to be run
    local script_path="$SCRIPT_DIR_PATH/ACrebuild.sh"
    local cron_log_path="$SCRIPT_LOG_DIR/$DEFAULT_CRON_LOG_FILENAME"
    # This is the most robust way to construct a cron command with redirection.
    # It ensures the cd and the script run together, and all output goes to the log.
    local command_to_run="{ cd '$SCRIPT_DIR_PATH' && '$script_path' --run-backup; } > '$cron_log_path' 2>&1"

    # Remove any existing backup job for this script
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT_TAG") | crontab -

    # Add the new job
    (crontab -l 2>/dev/null; echo "$cron_schedule $command_to_run # $CRON_COMMENT_TAG") | crontab -

    if [ $? -eq 0 ]; then
        print_message $GREEN "Backup schedule successfully created!" true
    else
        print_message $RED "Error: Failed to create backup schedule." true
    fi
}

# Function to view the current backup schedule
view_backup_schedule() {
    print_message $BLUE "--- Current Automated Backup Schedule ---" true

    local existing_job
    existing_job=$(crontab -l 2>/dev/null | grep "$CRON_COMMENT_TAG")

    if [ -n "$existing_job" ]; then
        print_message $CYAN "An automated backup job is scheduled:" false
        print_message $WHITE "  $existing_job" false
    else
        print_message $YELLOW "No automated backup job is currently scheduled." false
    fi
}

# Function to disable automated backups
disable_automated_backups() {
    print_message $BLUE "--- Disable Automated Backups ---" true

    local existing_job
    existing_job=$(crontab -l 2>/dev/null | grep "$CRON_COMMENT_TAG")

    if [ -z "$existing_job" ]; then
        print_message $YELLOW "No automated backup job is currently scheduled." false
        return
    fi

    print_message $YELLOW "This will remove the following scheduled job:" true
    print_message $WHITE "  $existing_job" false
    read -p "Are you sure you want to disable automated backups? (y/n): " confirm_disable

    if [[ "$confirm_disable" =~ ^[Yy]$ ]]; then
        (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT_TAG") | crontab -
        if [ $? -eq 0 ]; then
            print_message $GREEN "Automated backup schedule successfully disabled." true
        else
            print_message $RED "Error: Failed to disable automated backups." true
        fi
    else
        print_message $GREEN "Operation cancelled." false
    fi
}
