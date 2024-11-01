#!/bin/bash
set -E
set -m
set -x

# Trap various signals
#trap 'kill $(jobs -p | xargs)' SIGINT SIGTERM EXIT


# Array to store subshell PIDs
declare -a subshell_pids=()

# Log file for debugging
LOG_FILE="tmp/run-dev.log"

# Function to log messages
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Function to check if a process is running
is_process_running() {
    local pid=$1
    if kill -0 "$pid"; then
        log_message "PID: $pid is running"
        return 0
    else
        log_message "PID: $pid is NOT running"
        return 1
    fi
}

# Define a function to handle cleanup
cleanup() {
    log_message "Current Processes:"
    eval ps >> $LOG_FILE

    log_message "Initiating cleanup..."

    # Kill all registered subshell processes by group process ID
    for pid in "${subshell_pids[@]}"; do
      log_message "attempting to kill PID $pid..."
        if is_process_running "$pid"; then
            log_message "Terminating process $pid"
            kill -- -"$pid" >>$LOG_FILE 2>&1
            wait -- -"$pid" >/dev/null
        fi
    done

    log_message "Cleanup complete"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Function to start a process and register its PID
start_process() {
    local process_name="$1"
    local command="$2"

    # Start the process in a subshell with proper output redirection
    (
        eval "$command"
    ) >/dev/null 2> "$LOG_FILE" &

    local pid=$!

    # Wait briefly to check if the process started successfully
    sleep 1
    if is_process_running "$pid"; then
        subshell_pids+=("$pid")
        log_message "Started $process_name (PID: $pid)"
        return 0
    else
        log_message "Failed to start $process_name"
        return 1
    fi
}

# Main process
main() {
    # clear log file
    : > "$LOG_FILE"

    log_message "Starting run-dev.sh..."

    # Source environment variables
    if [[ -f .env ]]; then
        source .env
    else
        log_message "Warning: .env file not found"
    fi

    # Start Ollama if configured
    if [[ -n "${OLLAMA_MODEL:-}" ]]; then
        start_process "Ollama" "ollama run '${OLLAMA_MODEL}'" || \
            log_message "Failed to start Ollama"
    fi

    # Start Ngrok if configured
    if [[ -n "${NGROK_DOMAIN:-}" ]] && [[ -n "${PORT:-}" ]]; then
        start_process "Ngrok" "ngrok http '${PORT}' --url '${NGROK_DOMAIN}'" || \
            log_message "Failed to start Ngrok"
    fi

    echo "echoing pids"
    for pid in "${subshell_pids[@]}"; do
      echo "$pid"
    done

    # Monitor processes and wait for exit command
    log_message "All processes started. Type 'exit' to quit"
    while read -r -p "> " input; do
        if [[ "${input,,}" == "exit" ]]; then
            log_message "Exit command received"
            break
        fi
    done
}

# Run main function
main
