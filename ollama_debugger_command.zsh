#!/bin/zsh

# debug_command.zsh
# Usage: ./debug_command.zsh <command> [args...]

# Function to display usage information
usage() {
    echo "Usage: $0 <command> [args...]"
    echo "Example: $0 ls /nonexistent_directory"
    exit 1
}

# Check if at least one argument is provided
if [ $# -lt 1 ]; then
    usage
fi

# Reconstruct the command from arguments
user_command="$@"

# Log file for the ZSH script
log_file="debug_command.log"

# Start logging
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting execution of command: $user_command" | tee -a "$log_file"

# Create temporary files for script output
temp_output=$(mktemp)
temp_json=$(mktemp)

# Function to clean up temporary files on exit
cleanup() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Cleaning up temporary files." | tee -a "$log_file"
    rm -f "$temp_output" "$temp_json"
}
trap cleanup EXIT

# Execute the command using script to capture full terminal session
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Executing command with script..." | tee -a "$log_file"

# Use script to capture the command execution with proper TTY behavior
# -q: quiet mode (no start/done messages)
# -e: return exit status of child process (compatibility with util-linux)
# For BSD script with complex commands: script [-q] [-e] [file] [shell] [-c] [command]
set +e
script -q -e "$temp_output" /bin/zsh -c "$user_command" >/dev/null 2>&1
exit_status=$?
set -e

# Display the captured output
if [ -s "$temp_output" ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Command output:" | tee -a "$log_file"
    cat "$temp_output" | tee -a "$log_file"
fi

# If the command failed, proceed to interact with the Python shell debugger
if [ $exit_status -ne 0 ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Command failed with exit status $exit_status. Launching shell debugger..." | tee -a "$log_file"

    # Gather additional error details
    working_directory=$(pwd)
    shell_path="$SHELL"
    PATH_var="$PATH"
    system_information=$(uname -a)

    if [ -f /etc/os-release ]; then
        os_release=$(cat /etc/os-release)
    else
        os_release="OS release information not available"
    fi

    # Extract the base command (first word of the user command)
    base_command=$(echo "$user_command" | awk '{print $1}')

    if command -v "$base_command" >/dev/null 2>&1; then
        command_binary_details=$(which "$base_command")
        command_version=$("$base_command" --version 2>/dev/null || echo "Version information not available")
    else
        command_binary_details="Command not found in PATH"
        command_version="Version information not available"
    fi

    # Gather environment variables as a JSON object using jq
    environment_variables=$(env | jq -Rn '
        [inputs | split("=") | {(.[0]): .[1]}] | add
    ')

    # Read the script output as both stdout and stderr since script captures everything
    script_output=$(cat "$temp_output")

    # For script output, we treat it as stderr since that's where error messages typically appear
    # and the command failed. For successful parts, they would be mixed in the same output.

    # Clean up control characters and properly escape for JSON
    # Remove carriage returns and other control characters, then escape with jq
    cleaned_script_output=$(echo "$script_output" | tr -d '\r' | tr -d '\0')
    escaped_script_output=$(echo "$cleaned_script_output" | jq -Rs .)
    escaped_os_release=$(echo "$os_release" | tr -d '\n' | jq -Rs .)
    escaped_system_information=$(echo "$system_information" | tr -d '\n' | jq -Rs .)
    escaped_command_binary_details=$(echo "$command_binary_details" | tr -d '\n' | jq -Rs .)
    escaped_command_version=$(echo "$command_version" | tr -d '\n' | jq -Rs .)

    # Note: BSD script doesn't support separate timing files
    timing_info="Not available (BSD script)"
    escaped_timing_info=$(echo "$timing_info" | jq -Rs .)

    # Create a JSON payload with all error details
    # Note: For script output, we put the full output in stderr since it contains error info
    # and leave stdout empty since script combines everything
    error_details=$(jq -n \
        --arg command "$user_command" \
        --arg exit_status "$exit_status" \
        --argjson stdout "[]" \
        --arg stderr "$cleaned_script_output" \
        --arg working_directory "$working_directory" \
        --arg shell "$shell_path" \
        --arg PATH "$PATH_var" \
        --arg system_information "$system_information" \
        --arg os_release "$os_release" \
        --arg command_binary_details "$command_binary_details" \
        --arg command_version "$command_version" \
        --argjson environment_variables "$environment_variables" \
        --arg timing_info "$timing_info" \
        '{
            command: $command,
            exit_status: ($exit_status | tonumber),
            stdout: $stdout,
            stderr: $stderr,
            working_directory: $working_directory,
            shell: $shell,
            PATH: $PATH,
            system_information: $system_information,
            os_release: $os_release,
            command_binary_details: $command_binary_details,
            command_version: $command_version,
            environment_variables: $environment_variables,
            timing_info: $timing_info,
            capture_method: "script"
        }')

    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Error details gathered using script." | tee -a "$log_file"

    # Optionally, verify the JSON structure
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Generated JSON payload:" | tee -a "$log_file"
    echo "$error_details" | jq . | tee -a "$log_file"

    # Save the JSON payload to a temporary file
    echo "$error_details" >"$temp_json"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Error details saved to $temp_json." | tee -a "$log_file"

    # Check if Python script exists
    python_script="ollama_debugger.py"
    if [ ! -f "$python_script" ]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Python shell debugger script not found: $python_script" | tee -a "$log_file"
        exit 1
    fi

    # Execute the Python shell debugger script with the JSON file
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Executing Python shell debugger script..." | tee -a "$log_file"
    python3 "$python_script" "$temp_json" | tee -a "$log_file"

    insert_final_response() {
        LBUFFER+="final response from model"
    }
fi
