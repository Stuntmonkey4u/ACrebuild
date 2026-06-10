# AzerothCore Rebuild Script Comprehensive Audit Report

## Executive Summary

Overall Scores (0–10)
* **Security:** 4/10
* **Reliability:** 5/10
* **Maintainability:** 6/10
* **Portability:** 6/10
* **User Experience:** 7/10
* **Production Readiness:** 4/10

---

## Section 1: Code Quality Audit
**Architecture & Organization:** The project successfully abstracts complex configurations into logical modules (`core.sh`, `server.sh`, etc.), which improves initial readability.
**Duplication:** Found repetitive logic for starting/stopping Docker containers vs TMUX sessions across multiple files.
**Global Variables:** Heavy reliance on global variables loaded via `load_config` creates tight coupling and side effects if variables are accidentally modified.
**Recommendations:** Centralize Docker/TMUX dispatch into generic `server_action` handlers. Limit scope of variables using `local` heavily.

---

## Section 2: Shell Script Security Audit
**Command Execution Paths:**
* **Unsafe eval/Command injections:** The `run_command` and `save_config_value` use variable interpolation that could execute arbitrary commands if a user inputs shell metacharacters. `sed "s|^\s*${key_to_save}=.*|${key_to_save}=\"${escaped_value}\"|"` is particularly vulnerable if `key_to_save` contains malicious input.
* **Quoting:** Several variables in `print_message $RED "Message"` are unquoted, resulting in `SC2086` warnings (word splitting and globbing risks).
* **Word Splitting:** `read -r -a cmd_parts <<< "$command_str"` fails spectacularly on quoted strings, causing unexpected command parsing.

---

## Section 3: Configuration Security
**ACrebuild.conf Handling:**
* **Plaintext Passwords:** `DB_PASS` is stored in plaintext in the `.conf` file. If the machine is compromised, the DB credentials are automatically leaked.
* **File Permissions:** `save_config` sets permissions to `600`, which is good, but any parent directory weakness could expose the file.
* **Secure Alternatives:** Use `~/.my.cnf` for MySQL credentials rather than a custom config file, relying on standard secure tools, or integrate with a secrets manager for enterprise setups.

---

## Section 4: Update System Audit
**Self-Update & Source Updates:**
* **Rollbacks:** The `update_source_code` simply runs `git pull`. If it fails mid-merge, the directory is left in a broken state without a hard reset mechanism.
* **Verification:** No GPG signature verification of commits during `git pull`, trusting the remote repository implicitly.
* **Partial Updates:** If the network fails during `make install` after an update, the old server state is lost and the new one is incomplete.

---

## Section 5: Module Installation Security
* **Git URL Validation:** Git URLs for modules are checked minimally (must end in `.git`), but any URL is accepted.
* **Supply Chain Risks:** Users are prompted to paste arbitrary module URLs. Cloning and integrating untrusted third-party C++ code directly into the build pipeline without review is a critical supply chain risk.

---

## Section 6: Backup & Restore Audit
**Critical Flaws:**
* **Restore Pathing:** `EXTRACTED_CONTENT_DIR=$(find "$TEMP_RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d -name "backup_*" | head -n 1)` - if the archive contains multiple directories, `find` can misbehave if not piped to `head -n 1`. The tests show it was fixed, but the previous `find` was unsafe.
* **Atomic Restores:** The restore function drops existing tables to replace them. If the restore fails, the databases are permanently destroyed with no automatic fallback to the pre-restore backup (which the user can opt-out of).
* **Validation:** Backups are never tested or validated with `mysql --dry-run` or similar before being applied.

---

## Section 7: Database Management Audit
* **Credential Handling:** Passing passwords via `MYSQL_PWD="$DB_PASS"` is safer than `-p$DB_PASS` which exposes passwords to `ps aux`. However, `docker compose exec -e MYSQL_PWD="$DB_PASS"` can sometimes be viewed via Docker inspect or logs depending on the exact Compose version and settings.
* **Injection Risks:** Database names and user variables are passed directly into bash commands. If `DB_NAME` gets altered to include `; DROP TABLE auth;`, it will execute.

---

## Section 8: Docker Mode Audit
* **Assumptions:** Assumes the executable is strictly `docker compose` (V2). Older setups using `docker-compose` (V1) will fail, or may fall back unexpectedly depending on `$DOCKER_EXEC_PATH` resolution.
* **Container States:** The script waits for standard containers (`ac-database`, `ac-worldserver`). Custom container names in the user's `docker-compose.yml` will break server status detection.
* **Volume Handling:** DB backups rely on `mysqldump` running inside the container. It does not perform Docker volume snapshots, missing an opportunity for faster and more atomic backups.

---

## Section 9: Server Management Audit
* **Process Detection (TMUX):** Checking for `tmux has-session` assumes that if the TMUX session exists, the server is healthy. It does not check if the server process *inside* TMUX actually crashed.
* **PID Tracking:** The script does not use `.pid` files, instead relying on raw `pkill` or TMUX session destruction. This can orphan child processes.
* **Race Conditions:** `nc -z localhost $PORT` is used to verify server startup, which only confirms the TCP port bound, not that the server is ready for players.

---

## Section 10: Build System Audit
* **Partial Builds:** `make -j "$CORES" install` will fail on low-memory servers (e.g. 1GB RAM VPS) when using multiple cores due to `cc1plus` running out of memory. There is no auto-fallback to single-core building upon `OOMKilled` events.
* **Corruption:** Interrupted builds leave half-compiled object files which are sometimes not cleared by `make clean`.

---

## Section 11: Error Handling Audit
* **Infinite Recursion:** `handle_error` asks the user to retry, which calls `build_and_install_with_spinner`, which calls `handle_error` on failure. A user repeatedly typing `y` or an automated yes pipe causes a stack overflow in bash.
* **Silent Failures:** Some commands execute without `|| handle_error`, swallowing fatal exceptions (e.g., directory creation failures in some edge cases).

---

## Section 12: Logging & Diagnostics Audit
* **Formatting:** Logging lacks structured JSON output for log aggregators (e.g., Datadog, ELK).
* **Debug Levels:** No `--debug` or `set -x` flag natively exposed for users to troubleshoot why the script is failing. Error messages are generic ("Build failed").

---

## Section 13: Setup Wizard Audit
* **Validation:** The wizard accepts invalid paths for the `AZEROTHCORE_DIR` without failing hard, leading to downstream crashes.
* **Tilde Expansion:** Entering `~/azerothcore` fails later because bash does not expand `~` when referenced inside double-quoted variables in the script without explicit expansion.

---

## Section 14: Linux Compatibility Audit
* **Package Managers:** Supports `apt`, `yum`, `pacman`, `brew`. However, dependency maps in `dependencies.sh` assume standard package names which vary heavily between Debian and Arch.
* **Shell Compatibility:** Shebang is `#!/bin/bash`. If run on Alpine (which uses `ash`/`busybox`), it fails instantly. Needs strictly standard POSIX `sh` or enforcing `bash` installation.

---

## Section 15: Dependency Audit
* **Missing Checks:** `mysql-client` is missing from the standard check but is required for database access. `tmux` is required for standard mode but not enforced before starting the server process (it errors out gracefully, but late).
* **Version Validation:** CMake requires specific versions (typically 3.16+) for AzerothCore, but the script only checks if `cmake` exists, not if the version is compatible.

---

## Section 16: Reliability & Recovery Audit
* **Disk Full:** Backups do not check for available disk space. A full disk during `tar -czf` results in a corrupted, empty archive, and potentially overwrites older backups.
* **Graceful Degradation:** If the database is unreachable, the entire script hangs or crashes rather than degrading to a "View Logs" only mode.

---

## Section 17: UX & Administrator Experience Audit
* **Destructive Actions:** Restoring a database doesn't require typing a confirmation phrase (e.g., "RESTORE"), only a `y/n` prompt, making accidental overrides easy.
* **Navigation Flow:** Frequent clearing of the screen hides important context from the previous command output.

---

## Section 18: Production Readiness Audit
Not suitable for enterprise production environments due to:
* Lack of dry-run capabilities for destructive actions.
* In-memory, plaintext secret handling.
* Unsafe recursion and shell injection vulnerabilities.
* Unverified backup integrity.

---

## Section 19: Missing Features Analysis
1. **Automated Health Checks:** Auto-restart worldserver on crash.
2. **Backup Retention:** Automatically prune backups older than X days to prevent disk exhaustion.
3. **Rollbacks:** Git snapshotting prior to pulls.
4. **Discord Webhooks:** Critical for remote administration.

---

## Findings Table

| Title | Severity | File | Function | Description | Failure Scenario | Business/User Impact | Recommended Fix |
|---|---|---|---|---|---|---|---|
| Infinite Recursion | Critical | lib/core.sh | handle_error | Recursively calls build function | Build fails, user retries infinitely | Stack overflow, server hang | Replace recursion with retry loop |
| Config Injection | High | lib/ui.sh | save_config_value | Naive eval in sed | Malicious user input in config value | Arbitrary Code Execution | Sanitize inputs, avoid eval |
| Tilde Path Bug | High | lib/wizard.sh | N/A | `~` not expanded in double quotes | User types `~/folder` | Directory not found | Call `expand_path` utility |
| Backup Restore Override | High | lib/backup.sh | restore_backup | Drops DBs before ensuring backup is valid | Corrupted backup is extracted | Complete Data Loss | Validate SQL integrity before drop |
| Word Splitting Bug | Medium | lib/core.sh | run_command | `read -a` strips quotes | Space-separated string passed | Command syntax error | Use `$@` array passing directly |
| Plaintext Passwords | Medium | ACrebuild.conf | N/A | Passwords saved to disk | Server compromised | DB access compromised | Use `~/.my.cnf` |

---

## Security Findings

**Critical**
* None directly exploitable by external network users, but critical for internal privilege escalation.

**High**
* **Command Injection via Configuration:** Improper escaping when saving to `ACrebuild.conf`.

**Medium**
* **Plaintext Password Storage:** `DB_PASS` saved in config file.
* **Unquoted Variables:** SC2086 warnings leading to potential globbing attacks.

**Low**
* **MySQL Process Leaks:** `mysql -p` might leak to process table depending on environment.

---

## Reliability Findings
* **Data Loss:** Restoring a backup overwrites the DB without strict validation of the incoming `.sql` file structure.
* **Downtime:** `make -j $(nproc)` on low memory machines causes OOM crashes, bringing down the whole OS.
* **Corruption:** Failed `tar` due to out-of-disk space leaves 0-byte corrupted archives.

---

## Missing Features
* **High Impact:** Backup Retention Policy (Cron cleanup), Backup Validation.
* **Medium Impact:** Automated Health Checks & Auto-restart.
* **Nice-to-Have:** Discord Webhooks for server status changes.

---

## Quick Wins
1. Wrap all variables in double quotes (`"$VAR"`).
2. Use `read -r` everywhere to prevent backslash mangling.
3. Add `mysql-client` to the dependency array.
4. Add a warning about CPU cores vs RAM size in the build menu.

---

## Refactoring Opportunities
1. **Remove `run_command` string splitting:** Transition completely to Bash arrays.
2. **Centralized Retry Logic:** Remove `handle_error` recursion and implement a dedicated, flat retry handler.

---

## Production Launch Blockers
1. Fix the infinite recursion bug in `handle_error`.
2. Implement pre-restore validation and enforce pre-restore backups.
3. Fix dynamic path resolution for newer AzerothCore directory structures (`env/bin` vs `env/dist/bin`).
