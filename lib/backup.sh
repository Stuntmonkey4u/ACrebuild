#!/bin/bash

# Function to list available backups
list_backups() {
    print_message $BLUE "--- Available Backups ---" true
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        print_message $YELLOW "No backups found in $BACKUP_DIR." false
        return 1
    fi

    print_message $CYAN "Available backup files in $BACKUP_DIR:" false
    i=0 # Ensure i is reset if list_backups is called multiple times in a session
    BACKUP_FILES=() # Ensure array is reset before populating
    for backup_file in "$BACKUP_DIR"/*.tar.gz; do
        print_message $WHITE "  [$((i+1))] $(basename "$backup_file")" false
        BACKUP_FILES[i]="$backup_file" # Store full path
        i=$((i+1))
    done
    print_message $CYAN "  [0] Go Back to Backup/Restore Menu" false
    echo ""
    return 0
}

create_backup_dry_run() {
    print_message $BLUE "--- Starting Backup Creation (Dry Run) ---" true

    local current_db_user="$DB_USER"
    if [ -z "$current_db_user" ]; then
        print_message $YELLOW "Database username is not set. For a dry run, we will use the default '$DEFAULT_DB_USER'." true
        DB_USER="$DEFAULT_DB_USER"
    fi
    print_message $CYAN "[DRY RUN] Would be using database user: $DB_USER" false

    if [ ! -d "$BACKUP_DIR" ]; then
        print_message $CYAN "[DRY RUN] Backup directory $BACKUP_DIR does not exist. Would create it." false
    fi

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_SUBDIR="$BACKUP_DIR/backup_$TIMESTAMP"
    print_message $CYAN "[DRY RUN] Would create backup subdirectory: $BACKUP_SUBDIR" false

    DATABASES=("$AUTH_DB_NAME" "$CHAR_DB_NAME" "$WORLD_DB_NAME")
    for DB_NAME in "${DATABASES[@]}"; do
        print_message $CYAN "[DRY RUN] Would back up database: $DB_NAME" false
        if is_docker_setup; then
            print_message $WHITE "  Command: docker compose exec ac-db mysqldump -u\"$DB_USER\" -p\"...\" \"$DB_NAME\" > \"$BACKUP_SUBDIR/$DB_NAME.sql\"" false
        else
            print_message $WHITE "  Command: mysqldump -u\"$DB_USER\" -p\"...\" \"$DB_NAME\" > \"$BACKUP_SUBDIR/$DB_NAME.sql\"" false
        fi
    done

    print_message $CYAN "[DRY RUN] Would back up server configuration files..." false
    for CONFIG_FILE in "${SERVER_CONFIG_FILES[@]}"; do
        if [ -f "$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE" ]; then
            print_message $CYAN "[DRY RUN] Would copy configuration file $CONFIG_FILE to $BACKUP_SUBDIR/" false
            print_message $WHITE "  Command: cp \"$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE\" \"$BACKUP_SUBDIR/\"" false
        else
            print_message $YELLOW "[DRY RUN] Warning: Configuration file $SERVER_CONFIG_DIR_PATH/$CONFIG_FILE not found. Would skip." false
        fi
    done

    ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
    print_message $CYAN "[DRY RUN] Would create archive $ARCHIVE_NAME..." false
    print_message $WHITE "  Command: tar -czf \"$BACKUP_DIR/$ARCHIVE_NAME\" -C \"$BACKUP_DIR\" \"backup_$TIMESTAMP\"" false
    print_message $CYAN "[DRY RUN] Would clean up temporary backup directory..." false
    print_message $WHITE "  Command: rm -rf \"$BACKUP_SUBDIR\"" false

    print_message $GREEN "--- Backup Dry Run Completed Successfully ---" true
    echo ""
    read -n 1 -s -r -p "Press any key to return to the Backup/Restore menu..."
    echo ""
}

create_backup() {
    print_message $BLUE "--- Starting Backup Creation ---" true

    local current_db_user="$DB_USER"
    if [ -z "$current_db_user" ]; then
        print_message $YELLOW "Database username is not set. Enter the database username (e.g., acore):" true
        read -r db_user_input
        if [ -n "$db_user_input" ]; then
            DB_USER="$db_user_input"
            if [[ "$save_choice" =~ ^[Yy]$ ]]; then
                save_config_value "DB_USER" "$DB_USER"
            fi
        else
            print_message $RED "Database username cannot be empty for backup. Aborting." true
            return 1
        fi
    fi

    local effective_db_pass=""
    if [ -z "$DB_PASS" ]; then
        print_message $YELLOW "Enter the database password for user '$DB_USER':" true
        read -s new_db_pass
        echo ""
        effective_db_pass="$new_db_pass"
        if [ -n "$effective_db_pass" ]; then
            print_message $YELLOW "Save this database password to configuration? (Not Recommended)" true
            read -r save_pass_choice
            if [[ "$save_pass_choice" =~ ^[Yy]$ ]]; then
                save_config_value "DB_PASS" "$effective_db_pass"
                DB_PASS="$effective_db_pass"
            fi
        fi
    else
        print_message $CYAN "Using saved database password for user '$DB_USER'." false
        effective_db_pass="$DB_PASS"
    fi

    mkdir -p "$BACKUP_DIR" || { print_message $RED "Failed to create backup directory." true; return 1; }
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_SUBDIR="$BACKUP_DIR/backup_$TIMESTAMP"
    mkdir -p "$BACKUP_SUBDIR" || { print_message $RED "Failed to create timestamped backup subdirectory." true; return 1; }
    print_message $GREEN "Created backup subdirectory: $BACKUP_SUBDIR" false

    DATABASES=("$AUTH_DB_NAME" "$CHAR_DB_NAME" "$WORLD_DB_NAME")
    for DB_NAME in "${DATABASES[@]}"; do
        print_message $CYAN "Backing up database: $DB_NAME..." false
        local dump_cmd=""
        if is_docker_setup; then
            dump_cmd="docker compose exec -T ac-db mysqldump -u\"$DB_USER\" -p\"$effective_db_pass\" \"$DB_NAME\""
        else
            dump_cmd="mysqldump -u\"$DB_USER\" -p\"$effective_db_pass\" \"$DB_NAME\""
        fi

        if eval "$dump_cmd" > "$BACKUP_SUBDIR/$DB_NAME.sql"; then
            print_message $GREEN "Database $DB_NAME backed up successfully." false
        else
            print_message $RED "Error backing up database $DB_NAME." true
            rm -rf "$BACKUP_SUBDIR"
            return 1
        fi
    done

    print_message $CYAN "Backing up server configuration files..." false
    for CONFIG_FILE in "${SERVER_CONFIG_FILES[@]}"; do
        if [ -f "$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE" ]; then
            cp "$SERVER_CONFIG_DIR_PATH/$CONFIG_FILE" "$BACKUP_SUBDIR/"
            print_message $GREEN "Configuration file $CONFIG_FILE backed up." false
        else
            print_message $YELLOW "Warning: Config file $SERVER_CONFIG_DIR_PATH/$CONFIG_FILE not found." false
        fi
    done

    ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
    print_message $CYAN "Creating archive $ARCHIVE_NAME..." false
    if tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "backup_$TIMESTAMP"; then
        print_message $GREEN "Archive $ARCHIVE_NAME created successfully." false
    else
        print_message $RED "Error creating archive $ARCHIVE_NAME." true
        rm -rf "$BACKUP_SUBDIR"
        return 1
    fi

    rm -rf "$BACKUP_SUBDIR"
    print_message $GREEN "Backup process completed successfully." true
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
    echo ""
}

restore_backup() {
    print_message $BLUE "--- Starting Restore Process ---" true
    list_backups || return 1

    print_message $YELLOW "Enter the number of the backup to restore:" true
    read -r backup_choice
    [[ "$backup_choice" == "0" ]] && return 0
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#BACKUP_FILES[@]} ]; then
        print_message $RED "Invalid selection." true
        return 1
    fi

    SELECTED_BACKUP_FILE="${BACKUP_FILES[$((backup_choice-1))]}"
    print_message $CYAN "You selected to restore: $(basename "$SELECTED_BACKUP_FILE")" false

    # ... (password logic similar to create_backup) ...
    local effective_db_pass="$DB_PASS"
    if [ -z "$effective_db_pass" ]; then
        print_message $YELLOW "Enter DB password for user '$DB_USER':" true
        read -s effective_db_pass
        echo ""
    fi

    print_message $RED "WARNING: This will overwrite your current databases and configuration files." true
    print_message $YELLOW "Are you sure you want to continue? (y/n)" true
    read -r confirmation
    [[ ! "$confirmation" =~ ^[Yy]$ ]] && { print_message $GREEN "Restore aborted." true; return 1; }

    TEMP_RESTORE_DIR="$BACKUP_DIR/restore_temp_$(date +"%Y%m%d_%H%M%S")"
    mkdir -p "$TEMP_RESTORE_DIR" || { print_message $RED "Failed to create temp directory." true; return 1; }

    print_message $CYAN "Extracting backup archive..." false
    tar -xzf "$SELECTED_BACKUP_FILE" -C "$TEMP_RESTORE_DIR" || { print_message $RED "Error extracting archive." true; rm -rf "$TEMP_RESTORE_DIR"; return 1; }

    EXTRACTED_CONTENT_DIR=$(find "$TEMP_RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ -z "$EXTRACTED_CONTENT_DIR" ]; then
        print_message $RED "Could not find extracted content directory." true
        rm -rf "$TEMP_RESTORE_DIR"
        return 1
    fi

    DATABASES=("$AUTH_DB_NAME" "$CHAR_DB_NAME" "$WORLD_DB_NAME")
    for DB_NAME in "${DATABASES[@]}"; do
        SQL_FILE="$EXTRACTED_CONTENT_DIR/$DB_NAME.sql"
        if [ ! -f "$SQL_FILE" ]; then
            print_message $YELLOW "Warning: SQL file for $DB_NAME not found. Skipping." false
            continue
        fi
        print_message $CYAN "Restoring database: $DB_NAME..." false

        local import_cmd=""
        if is_docker_setup; then
            import_cmd="docker compose exec -T ac-db mysql -u\"$DB_USER\" -p\"$effective_db_pass\" \"$DB_NAME\""
        else
            import_cmd="mysql -u\"$DB_USER\" -p\"$effective_db_pass\" \"$DB_NAME\""
        fi

        if cat "$SQL_FILE" | eval "$import_cmd"; then
            print_message $GREEN "Database $DB_NAME restored successfully." false
        else
            print_message $RED "Error restoring database $DB_NAME." true
            rm -rf "$TEMP_RESTORE_DIR"
            return 1
        fi
    done

    print_message $CYAN "Restoring server configuration files..." false
    mkdir -p "$SERVER_CONFIG_DIR_PATH" || { print_message $RED "Failed to create server config dir." true; rm -rf "$TEMP_RESTORE_DIR"; return 1; }
    for CONFIG_FILE in "${SERVER_CONFIG_FILES[@]}"; do
        if [ -f "$EXTRACTED_CONTENT_DIR/$CONFIG_FILE" ]; then
            cp "$EXTRACTED_CONTENT_DIR/$CONFIG_FILE" "$SERVER_CONFIG_DIR_PATH/"
            print_message $GREEN "Config file $CONFIG_FILE restored." false
        fi
    done

    rm -rf "$TEMP_RESTORE_DIR"
    print_message $GREEN "Restore process completed successfully." true
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
    echo ""
}
