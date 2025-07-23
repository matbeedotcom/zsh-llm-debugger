# llm_debugger.plugin.zsh

# Enable debugging (set to 1 to enable, 0 to disable)
# Debug mode disabled by default to prevent job table overflow
export LLM_DEBUGGER_DEBUG=${LLM_DEBUGGER_DEBUG:-0}

# Define paths
plugin_dir="${0:A:h}"
LLM_DEBUGGER_SCRIPT="${plugin_dir}/run_ollama_debugger.sh"

LLM_DEBUGGER_LOG_FILE="$HOME/.llm_debugger_zsh.log" # Log file for Zsh plugin

# Suppress job control messages for job completion
setopt NO_NOTIFY
setopt NO_HUP
setopt NO_CHECK_JOBS
setopt NO_BG_NICE

# Debug function - optimized to avoid subprocess creation
llm_debugger_debug() {
    if [[ $LLM_DEBUGGER_DEBUG -eq 1 ]]; then
        # Use a simple timestamp or no timestamp to avoid subprocess creation
        # This prevents the "job table full" error from $(date) calls
        print -r -- "[DEBUG] $1" >>"$LLM_DEBUGGER_LOG_FILE"
    fi
}

# Function to restore key bindings
llm_debugger_restore_bindings() {
    llm_debugger_debug "Restoring original key bindings"
    bindkey '^I' expand-or-complete
    bindkey '\e' cancel-or-ignore

    # Unbind custom widgets if they exist
    if zle -L | grep -q '^llm_debugger_accept_suggestion$'; then
        zle -D llm_debugger_accept_suggestion 2>/dev/null
        llm_debugger_debug "Unbound llm_debugger_accept_suggestion"
    fi
    if zle -L | grep -q '^llm_debugger_cancel_suggestion$'; then
        zle -D llm_debugger_cancel_suggestion 2>/dev/null
        llm_debugger_debug "Unbound llm_debugger_cancel_suggestion"
    fi
}

# Function to suppress job control messages
llm_debugger_suppress_jobs() {
    # Disable job control notifications temporarily
    unsetopt NOTIFY 2>/dev/null || true
    unsetopt HUP 2>/dev/null || true
    unsetopt CHECK_JOBS 2>/dev/null || true
    unsetopt BG_NICE 2>/dev/null || true

}

# Function to restore job control settings
llm_debugger_restore_jobs() {
    # Restore our preferred job control settings
    setopt NO_NOTIFY 2>/dev/null || true
    setopt NO_HUP 2>/dev/null || true
    setopt NO_CHECK_JOBS 2>/dev/null || true
    setopt NO_BG_NICE 2>/dev/null || true

}

# Cleanup function to be called manually if needed
llm_debugger_cleanup() {
    llm_debugger_debug "Running cleanup"
    llm_debugger_restore_bindings

    # Clean up any temporary streaming files
    rm -f "/tmp/llm_debugger_$$_"*
    rm -f "/tmp/llm_debugger_generate_result"

    # Reset suggestion variables
    llm_debugger_suggestion=""
    llm_debugger_has_suggestion=0
    llm_debugger_original_buffer=""
    llm_debugger_original_cursor=""

    # Reset processing flags
    LLM_DEBUGGER_PROCESSING=0
    LLM_DEBUGGER_WIDGET_ACTIVE=0

    # Clear any region highlighting
    region_highlight=()

    # Clean up any lingering background jobs
    llm_debugger_suppress_jobs
    jobs -p | while read pid; do
        if [[ -n "$pid" ]]; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    llm_debugger_restore_jobs
}

# Ensure the Python script is executable
if [[ ! -x "$LLM_DEBUGGER_SCRIPT" ]]; then
    llm_debugger_debug "Python debugger script not found or not executable at $LLM_DEBUGGER_SCRIPT"
    echo "Python debugger script not found or not executable at $LLM_DEBUGGER_SCRIPT"
    return 1
fi

llm_debugger_debug "Python debugger script found at $LLM_DEBUGGER_SCRIPT"

# Global variables to accumulate suggestion data
typeset -g llm_debugger_suggestion=""
typeset -g llm_debugger_has_suggestion=0

# Global variables for inline suggestions (like zsh-autosuggestions)
typeset -g llm_debugger_original_buffer=""
typeset -g llm_debugger_original_cursor=""

# Global variables for streaming display
typeset -g llm_debugger_streaming_buffer=""
typeset -g llm_debugger_streaming_think_mode=0
typeset -g llm_debugger_final_command=""

# Function to process streaming output from Python script
llm_debugger_process_stream() {
    llm_debugger_streaming_buffer=""
    llm_debugger_streaming_think_mode=0
    llm_debugger_final_command=""

    local line
    local char
    local buffer=""

    # Read character by character from stdin
    while IFS= read -r -d $'\0' char || IFS= read -r char; do
        # Handle special markers from Python script
        if [[ "$buffer" == *"THINK_START"* ]]; then
            llm_debugger_streaming_think_mode=1
            buffer="${buffer%THINK_START*}"
            continue
        fi

        if [[ "$buffer" == *"THINK_END"* ]]; then
            llm_debugger_streaming_think_mode=0
            buffer="${buffer%THINK_END*}"
            continue
        fi

        buffer+="$char"

        # If we're in think mode, display differently
        if [[ $llm_debugger_streaming_think_mode -eq 1 ]]; then
            # For think content, we can collect but not display in the command line
            # Maybe show a different indicator
            llm_debugger_streaming_buffer="💭 Thinking..."
        else
            # Regular command content - display in real time
            llm_debugger_streaming_buffer="$buffer"
            llm_debugger_final_command="$buffer"
        fi
    done
}

# Function to display streaming debug analysis for ? mode
llm_debugger_display_streaming_debug_analysis() {
    local python_pid="$1"
    local stream_file="$2"

    # Monitor the streaming output for debug analysis
    local last_size=0
    local current_content=""
    local display_buffer=""
    local in_think=0
    local suggestion=""

    printf "\n" # Start on new line

    while kill -0 "$python_pid" 2>/dev/null; do
        if [[ -f "$stream_file" ]]; then
            local current_size=$(wc -c <"$stream_file" 2>/dev/null || echo "0")
            if [[ $current_size -gt $last_size ]]; then
                # Read new content
                local new_content=$(tail -c +$((last_size + 1)) "$stream_file" 2>/dev/null)
                current_content+="$new_content"

                # Process the content for display
                if [[ "$current_content" == *"<think[THINK_START]"* ]]; then
                    in_think=1
                    printf "\r\033[2K\033[90m💭 Analyzing error..."
                elif [[ "$current_content" == *"[THINK_END]"* ]]; then
                    in_think=0
                    # Extract suggestion after think tags - look for commands in markdown
                    local content_after_think="${current_content##*\[THINK_END\]}"

                    # Try to extract command from various markdown formats
                    suggestion=""

                    # Look for **`command`** format
                    if [[ "$content_after_think" == *'**`'*'`**'* ]]; then
                        suggestion="${content_after_think##*\*\*\`}"
                        suggestion="${suggestion%%\`\*\**}"
                    # Look for `command` format
                    elif [[ "$content_after_think" == *'`'*'`'* ]]; then
                        suggestion="${content_after_think##*\`}"
                        suggestion="${suggestion%%\`*}"
                    # Look for lines starting with common command prefixes
                    elif [[ "$content_after_think" == *'find '* ]]; then
                        suggestion=$(echo "$content_after_think" | grep -o 'find [^[:space:]]*[[:space:]]*[^[:space:]]*' | head -1)
                    elif [[ "$content_after_think" == *'ls '* ]]; then
                        suggestion=$(echo "$content_after_think" | grep -o 'ls [^[:space:]]*' | head -1)
                    else
                        # Fallback: get first meaningful line
                        suggestion=$(echo "$content_after_think" | grep -v '^[[:space:]]*$' | head -1)
                    fi

                    # Clean up the suggestion
                    suggestion="${suggestion## }"  # Remove leading spaces
                    suggestion="${suggestion%% }"  # Remove trailing spaces
                    suggestion="${suggestion%\%*}" # Remove % suffix

                    if [[ -n "$suggestion" ]]; then
                        printf "\r\033[2K\033[33m🔧\033[0m %s" "$suggestion"
                    else
                        printf "\r\033[2K\033[33m🔧\033[0m Processing..."
                    fi
                elif [[ $in_think -eq 0 ]]; then
                    # Not in think mode, show suggestion being built
                    display_buffer="$current_content"
                    # Clean up display buffer
                    display_buffer="${display_buffer//<think\[THINK_START\]*/}"
                    display_buffer="${display_buffer//\[THINK_END\]*/}"
                    display_buffer="${display_buffer#$'\n'}"   # Remove leading newline
                    display_buffer="${display_buffer## }"      # Remove leading spaces
                    display_buffer="${display_buffer%%$'\n'*}" # Keep only first line
                    display_buffer="${display_buffer%\%*}"     # Remove % suffix
                    display_buffer="${display_buffer%% }"      # Remove trailing spaces

                    if [[ -n "$display_buffer" ]]; then
                        printf "\r\033[2K\033[33m🔧\033[0m %s" "$display_buffer"
                        suggestion="$display_buffer"
                    fi
                fi

                last_size=$current_size
            fi
        fi
        sleep 0.1
    done

    # Wait for completion
    wait $python_pid

    # Clear the line and show final suggestion
    printf "\r\033[2K"

    if [[ -n "$suggestion" ]]; then
        # Store the suggestion for key bindings
        llm_debugger_suggestion="$suggestion"
        llm_debugger_has_suggestion=1

        # Display the final suggestion
        local my_yellow=$'\e[33m'
        local my_reset=$'\e[0m'
        local message="${my_yellow}Suggested command:${my_reset} $suggestion"
        print -- "$message"

        # Bind Tab key to accept the suggestion
        zle -N llm_debugger_accept_suggestion
        bindkey '^I' llm_debugger_accept_suggestion # '^I' is Tab
        llm_debugger_debug "Bound Tab key to llm_debugger_accept_suggestion"

        # Bind Escape key to cancel the suggestion
        zle -N llm_debugger_cancel_suggestion
        bindkey '\e' llm_debugger_cancel_suggestion # Escape key
        llm_debugger_debug "Bound Escape key to llm_debugger_cancel_suggestion"
    else
        printf "\033[91mNo suggestion generated\033[0m\n"
    fi
}

# Global variables to prevent recursion and excessive subprocess creation
typeset -g LLM_DEBUGGER_HAS_SCRIPT=""
typeset -g LLM_DEBUGGER_PROCESSING=0
typeset -g LLM_DEBUGGER_WIDGET_ACTIVE=0

# Function to execute command and start analysis if there's an error
llm_debugger_execute_and_analyze() {
    local command="$*"
    llm_debugger_debug "Executing command: $command"

    # Create temporary files for script output - use /tmp with PID to avoid mktemp subprocess
    local temp_output="/tmp/llm_debugger_$$_output"
    local exit_status

    # Function to cleanup temp files
    cleanup_temps() {
        rm -f "$temp_output"
        llm_debugger_debug "Cleaned up temporary files"
    }

    llm_debugger_debug "Using script to capture command execution"

    # Use script to capture the command execution with proper TTY behavior
    # This preserves the exact terminal output as the user would see it
    # Cache script command availability to avoid repeated subprocess calls
    if [[ -z "$LLM_DEBUGGER_HAS_SCRIPT" ]]; then
        if command -v script >/dev/null 2>&1; then
            LLM_DEBUGGER_HAS_SCRIPT=1
        else
            LLM_DEBUGGER_HAS_SCRIPT=0
        fi
    fi

    if [[ "$LLM_DEBUGGER_HAS_SCRIPT" -eq 1 ]]; then
        # Use script command for better capture (BSD syntax with shell)
        script -q -e "$temp_output" /bin/zsh -c "$command" >/dev/null 2>&1
        exit_status=$?
        llm_debugger_debug "Command executed with script, exit status: $exit_status"

        # Display the captured output to the user
        if [[ -s "$temp_output" ]]; then
            echo
            cat "$temp_output"
        fi
    else
        # Fallback to traditional method if script is not available
        llm_debugger_debug "script command not available, falling back to traditional capture"
        local output
        output=$(eval "$command" 2>&1)
        exit_status=$?
        echo "$output" >"$temp_output"

        # Display the output
        echo
        print -r -- "$output"
    fi

    # If the command failed, start analysis
    if [[ $exit_status -ne 0 ]]; then
        llm_debugger_debug "Command failed, starting streaming analysis"

        # Reset the suggestion variable
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0

        # Create output file for debug mode
        local debug_output_file="/tmp/llm_debugger_$$_debug_output"
        rm -f "$debug_output_file"

        llm_debugger_debug "Started Python debugger for command: $command"

        # Show thinking indicator
        printf "\n\033[90m💭 Analyzing error...\033[0m"

        # Use proper debug mode with tools and few-shot examples
        "${plugin_dir}/run_ollama_debugger.sh" "$command" "$temp_output" "None" "script" >"$debug_output_file" 2>&1
        local exit_code=$?

        llm_debugger_debug "Python debugger exit code: $exit_code"
        if [[ -f "$debug_output_file" ]]; then
            llm_debugger_debug "Debug output file exists, size: $(wc -c <"$debug_output_file" 2>/dev/null || echo 0)"
        else
            llm_debugger_debug "Debug output file does not exist"
        fi

        # Clear the thinking line
        printf "\r\033[2K"

        if [[ $exit_code -eq 0 && -f "$debug_output_file" && -s "$debug_output_file" ]]; then
            local suggested_command=$(cat "$debug_output_file")
            suggested_command="${suggested_command## }" # Remove leading spaces
            suggested_command="${suggested_command%% }" # Remove trailing spaces
            llm_debugger_debug "Raw suggestion: '$suggested_command'"

            if [[ -n "$suggested_command" ]]; then
                # Store the suggestion for key bindings
                llm_debugger_suggestion="$suggested_command"
                llm_debugger_has_suggestion=1

                # Display the final suggestion
                local my_yellow=$'\e[33m'
                local my_reset=$'\e[0m'
                local message="${my_yellow}🔧 Suggested command:${my_reset} $suggested_command"
                print -- "$message"

                # Bind Tab key to accept the suggestion
                zle -N llm_debugger_accept_suggestion
                bindkey '^I' llm_debugger_accept_suggestion # '^I' is Tab
                llm_debugger_debug "Bound Tab key to llm_debugger_accept_suggestion"

                # Bind Escape key to cancel the suggestion
                zle -N llm_debugger_cancel_suggestion
                bindkey '\e' llm_debugger_cancel_suggestion # Escape key
                llm_debugger_debug "Bound Escape key to llm_debugger_cancel_suggestion"
            else
                printf "\033[91mNo suggestion generated (empty output)\033[0m\n"
                llm_debugger_debug "Suggestion was empty after processing"
            fi
        else
            printf "\033[91mError: Failed to analyze command (exit code: $exit_code)\033[0m\n"
            llm_debugger_debug "Debug failed - exit code: $exit_code, file exists: $([[ -f "$debug_output_file" ]] && echo "yes" || echo "no"), file size: $(wc -c <"$debug_output_file" 2>/dev/null || echo 0)"
            if [[ -f "$debug_output_file" ]]; then
                llm_debugger_debug "Debug output file contents: $(cat "$debug_output_file" 2>/dev/null)"
            fi
        fi

        # Clean up
        rm -f "$debug_output_file"
    else
        llm_debugger_debug "Command succeeded, no analysis needed"
    fi

    # Cleanup temporary files
    cleanup_temps
}

# Widget to partially accept the inline suggestion (word by word)
llm_debugger_partial_accept_inline_suggestion() {
    llm_debugger_debug "Partial accept key pressed - attempting to accept next word"
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_original_buffer" ]]; then
        # Calculate how much of the suggestion to accept (up to next word boundary)
        local original_length=${#llm_debugger_original_buffer}
        local current_length=${#BUFFER}
        local suggestion_part="${BUFFER:$original_length}"

        # Find the next word boundary in the suggestion
        local word_end=0
        local i=0
        local in_word=0

        # Skip any leading spaces
        while [[ $i -lt ${#suggestion_part} && "${suggestion_part:$i:1}" == " " ]]; do
            ((i++))
        done

        # Find end of next word
        while [[ $i -lt ${#suggestion_part} ]]; do
            local char="${suggestion_part:$i:1}"
            if [[ "$char" =~ [[:space:]] ]]; then
                if [[ $in_word -eq 1 ]]; then
                    break
                fi
            else
                in_word=1
            fi
            ((i++))
        done

        word_end=$i

        if [[ $word_end -gt 0 ]]; then
            # Accept up to the word boundary
            local new_cursor=$((original_length + word_end))
            CURSOR=$new_cursor

            # Update the original buffer to include the accepted part
            llm_debugger_original_buffer="${BUFFER:0:$new_cursor}"
            llm_debugger_original_cursor=$new_cursor

            # Update highlighting for remaining suggestion
            local remaining_start=$((new_cursor + 1))
            local remaining_end=$((${#BUFFER} + 1))

            if [[ $remaining_start -lt $remaining_end ]]; then
                region_highlight=("$remaining_start $remaining_end fg=8")
            else
                # Fully accepted, clear everything
                region_highlight=()
                llm_debugger_suggestion=""
                llm_debugger_has_suggestion=0
                llm_debugger_original_buffer=""
                llm_debugger_original_cursor=""
                llm_debugger_restore_inline_bindings
            fi

            llm_debugger_debug "Partially accepted to position $new_cursor"
            zle redisplay
        else
            # Nothing more to accept, fully accept
            llm_debugger_accept_inline_suggestion
        fi
    else
        # No suggestion, perform default forward-word action
        llm_debugger_debug "No inline suggestion available, performing forward-word"
        zle forward-word
    fi
}

# Widget to accept the inline suggestion (like zsh-autosuggestions)
llm_debugger_accept_inline_suggestion() {
    llm_debugger_debug "Accept key pressed - attempting to accept inline suggestion"
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_original_buffer" ]]; then
        # Accept the suggestion by keeping the current buffer (which includes the suggestion)
        # Remove highlighting
        region_highlight=()

        # Reset cursor to end of buffer
        CURSOR=${#BUFFER}

        # Clear suggestion state
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_original_buffer=""
        llm_debugger_original_cursor=""

        # Restore original key bindings
        llm_debugger_restore_inline_bindings

        llm_debugger_debug "Accepted inline suggestion: $BUFFER"

        # Refresh the display
        zle redisplay
    else
        # No suggestion, perform default action based on key pressed
        llm_debugger_debug "No inline suggestion available, performing default action"
        # Check which key was pressed and perform appropriate default action
        if [[ "$KEYS" == $'\e[C' || "$KEYS" == $'\eOC' ]]; then
            zle forward-char # Right arrow default
        elif [[ "$KEYS" == $'\e' ]]; then
            zle end-of-line # End key default
        else
            zle expand-or-complete # Tab default
        fi
    fi
}

# Widget to clear the inline suggestion
llm_debugger_clear_inline_suggestion_widget() {
    llm_debugger_debug "Clear key pressed - attempting to clear inline suggestion"
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_original_buffer" ]]; then
        # Clear the suggestion
        llm_debugger_clear_inline_suggestion

        # Clear suggestion state
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0

        # Restore original key bindings
        llm_debugger_restore_inline_bindings

        llm_debugger_debug "Cleared inline suggestion"

        # Refresh the display
        zle redisplay
    else
        # No suggestion, perform default action
        llm_debugger_debug "No inline suggestion to clear, performing default action"
        if [[ "$KEYS" == $'\e' ]]; then
            zle send-break # Escape default
        elif [[ "$KEYS" == $'\C-c' ]]; then
            zle send-break # Ctrl+C default
        fi
    fi
}

# Function to restore original key bindings
llm_debugger_restore_inline_bindings() {
    # Restore original key bindings
    bindkey '^[[C' forward-char     # Right Arrow
    bindkey '^[OC' forward-char     # Right Arrow (alternate)
    bindkey '^E' end-of-line        # End key
    bindkey '^[[1;5C' forward-word  # Ctrl+Right Arrow
    bindkey '^[f' forward-word      # Alt+F
    bindkey '^[' send-break         # Escape
    bindkey '^C' send-break         # Ctrl+C
    bindkey '^I' expand-or-complete # Tab

    llm_debugger_debug "Restored original key bindings"
}

# Simple key handler for suggestions (no complex widget binding)
llm_debugger_simple_key_handler() {
    # Check if we're in suggestion mode
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Get the pressed key
        local key="$KEYS"

        case "$key" in
        $'\e[C' | $'\eOC' | $'\e' | $'\t' | $'\C-e') # Right arrow, Tab, End, Escape
            # Accept the suggestion
            BUFFER="$llm_debugger_suggestion"
            CURSOR=${#BUFFER}
            region_highlight=()
            llm_debugger_suggestion=""
            llm_debugger_has_suggestion=0
            llm_debugger_debug "Accepted suggestion via key: $key"
            zle redisplay
            ;;
        $'\C-c' | $'\e') # Ctrl+C or Escape to cancel
            # Clear the suggestion
            BUFFER=""
            CURSOR=0
            region_highlight=()
            llm_debugger_suggestion=""
            llm_debugger_has_suggestion=0
            llm_debugger_debug "Cancelled suggestion via key: $key"
            zle redisplay
            ;;
        *)
            # Any other key should clear suggestion and proceed normally
            BUFFER=""
            CURSOR=0
            region_highlight=()
            llm_debugger_suggestion=""
            llm_debugger_has_suggestion=0
            llm_debugger_debug "Cleared suggestion, proceeding with normal key handling"
            # Let the key continue to normal handling
            ;;
        esac
    fi
}

# Legacy widget functions (kept for backward compatibility)
llm_debugger_accept_suggestion() {
    llm_debugger_accept_inline_suggestion
}

llm_debugger_cancel_suggestion() {
    llm_debugger_clear_inline_suggestion_widget
}

# Function to show inline suggestion (like zsh-autosuggestions)
llm_debugger_show_inline_suggestion() {
    local suggestion="$1"

    # Save current buffer and cursor position
    llm_debugger_original_buffer="$BUFFER"
    llm_debugger_original_cursor="$CURSOR"

    # Add suggestion to buffer
    BUFFER="${BUFFER}${suggestion}"

    # Calculate highlighting positions (1-indexed for region_highlight)
    local suggestion_start=$((llm_debugger_original_cursor + 1))
    local suggestion_end=$((${#BUFFER}))

    # Style the suggestion part with gray color (like zsh-autosuggestions)
    if [[ $suggestion_start -le $suggestion_end ]]; then
        region_highlight=("$suggestion_start $suggestion_end fg=8")
    fi

    # Keep cursor at original position so suggestion appears after cursor
    CURSOR="$llm_debugger_original_cursor"

    llm_debugger_debug "Showing inline suggestion: '$suggestion' at positions $suggestion_start-$suggestion_end"
}

# Function to clear inline suggestion
llm_debugger_clear_inline_suggestion() {
    if [[ -n "$llm_debugger_original_buffer" ]]; then
        BUFFER="$llm_debugger_original_buffer"
        CURSOR="$llm_debugger_original_cursor"
        region_highlight=()
        llm_debugger_original_buffer=""
        llm_debugger_original_cursor=""
        llm_debugger_debug "Cleared inline suggestion"
    fi
}

# Synchronous function for ? mode (works within zle widget)
llm_debugger_execute_and_analyze_sync() {
    local command="$1"
    llm_debugger_debug "Executing and analyzing command synchronously: $command"

    # Create temporary files for script output - use /tmp with PID to avoid mktemp subprocess
    local temp_output="/tmp/llm_debugger_$$_output"
    local exit_status
    local result_file="/tmp/llm_debugger_debug_result"
    local debug_output_file="/tmp/llm_debugger_$$_debug_output"

    # Function to cleanup temp files
    cleanup_temps() {
        rm -f "$temp_output" "$result_file" "$debug_output_file"
        llm_debugger_debug "Cleaned up temporary files"
    }

    # Execute the command using script to capture full terminal session
    llm_debugger_debug "Using script to capture command execution"

    # Cache script command availability to avoid repeated subprocess calls
    if [[ -z "$LLM_DEBUGGER_HAS_SCRIPT" ]]; then
        if command -v script >/dev/null 2>&1; then
            LLM_DEBUGGER_HAS_SCRIPT=1
        else
            LLM_DEBUGGER_HAS_SCRIPT=0
        fi
    fi

    # Clear buffer and show loading message
    BUFFER=""
    CURSOR=0

    # Show execution indicator
    printf "\n\033[90m🔧 Executing command...\033[0m"

    if [[ "$LLM_DEBUGGER_HAS_SCRIPT" -eq 1 ]]; then
        # Use script command for better capture (BSD syntax with shell)
        script -q -e "$temp_output" /bin/zsh -c "$command" >/dev/null 2>&1
        exit_status=$?
        llm_debugger_debug "Command executed with script, exit status: $exit_status"
    else
        # Fallback to traditional method if script is not available
        llm_debugger_debug "script command not available, falling back to traditional capture"
        local output
        output=$(eval "$command" 2>&1)
        exit_status=$?
        echo "$output" >"$temp_output"
    fi

    # Clear the execution line
    printf "\r\033[2K"

    # Display the captured output to the user
    if [[ -s "$temp_output" ]]; then
        echo
        cat "$temp_output"
    fi

    # If the command failed, start analysis
    if [[ $exit_status -ne 0 ]]; then
        llm_debugger_debug "Command failed, starting analysis"

        # Reset the suggestion variable
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0

        # Clean up any existing result file
        rm -f "$debug_output_file"

        llm_debugger_debug "Started Python debugger for command: $command"

        # Show thinking indicator
        printf "\n\033[90m💭 Analyzing error...\033[0m"

        # Use proper debug mode with tools and few-shot examples
        # Run synchronously to avoid job control messages
        "${plugin_dir}/run_ollama_debugger.sh" "$command" "$temp_output" "None" "script" >"$debug_output_file" 2>&1
        local exit_code=$?

        # Clear the thinking line
        printf "\r\033[2K"

        # Read the result and set up inline suggestion
        if [[ $exit_code -eq 0 && -f "$debug_output_file" && -s "$debug_output_file" ]]; then
            local suggested_command=$(cat "$debug_output_file")
            # Clean up the command
            suggested_command="${suggested_command## }"      # Remove leading spaces
            suggested_command="${suggested_command%% }"      # Remove trailing spaces
            suggested_command="${suggested_command%%$'\n'*}" # Keep only first line

            if [[ -n "$suggested_command" ]]; then
                # Display the final suggestion as a message first
                local my_yellow=$'\e[33m'
                local my_reset=$'\e[0m'
                local message="${my_yellow}🔧 Suggested command:${my_reset} $suggested_command"
                print -- "$message"

                # Clear buffer and show suggestion inline (like zsh-autosuggestions)
                BUFFER=""
                CURSOR=0
                llm_debugger_show_inline_suggestion "$suggested_command"

                # Store suggestion data
                llm_debugger_suggestion="$suggested_command"
                llm_debugger_has_suggestion=1
                llm_debugger_debug "Set up inline suggestion for ? command: '$suggested_command'"
            else
                BUFFER=""
                CURSOR=0
                printf "\033[91mNo suggestion generated (empty output)\033[0m\n"
                llm_debugger_debug "Suggested command was empty"
            fi
        else
            BUFFER=""
            CURSOR=0
            printf "\033[91mError: Failed to analyze command (exit code: $exit_code)\033[0m\n"
            llm_debugger_debug "Command analysis failed - exit code: $exit_code"
            if [[ -f "$debug_output_file" ]]; then
                llm_debugger_debug "Debug output file contents: $(cat "$debug_output_file" 2>/dev/null)"
            fi
        fi
    else
        llm_debugger_debug "Command succeeded, no analysis needed"
        # Clear buffer since command was successful
        BUFFER=""
        CURSOR=0
    fi

    # Clean up temp files
    cleanup_temps

    # Redraw
    zle redisplay
}

# Synchronous function for ?? mode (works within zle widget)
llm_debugger_generate_command_interactive_sync() {
    local prompt="$1"
    llm_debugger_debug "Generating command synchronously from prompt: $prompt"

    # Use a simple file for communication
    local result_file="/tmp/llm_debugger_generate_result"
    local temp_prompt="/tmp/llm_debugger_$$_prompt_sync"
    echo "$prompt" >"$temp_prompt"

    # Clean up any existing result file
    rm -f "$result_file"

    # Reset state
    llm_debugger_suggestion=""
    llm_debugger_has_suggestion=0
    llm_debugger_clear_inline_suggestion

    # Clear buffer and show loading message
    BUFFER=""
    CURSOR=0

    # Show thinking indicator
    printf "\n\033[36m💭 Generating command...\033[0m"

    # Run the Python script synchronously (no streaming)
    # Run synchronously to avoid job control messages
    "${plugin_dir}/run_ollama_debugger.sh" "GENERATE_MODE" "$temp_prompt" "None" "generate" >"$result_file" 2>/dev/null
    local exit_code=$?

    # Clear the thinking line
    printf "\r\033[2K"

    # Read the result and set up inline suggestion
    if [[ $exit_code -eq 0 && -f "$result_file" && -s "$result_file" ]]; then
        local generated_command=$(cat "$result_file")
        # Clean up the command
        generated_command="${generated_command## }"      # Remove leading spaces
        generated_command="${generated_command%% }"      # Remove trailing spaces
        generated_command="${generated_command%%$'\n'*}" # Keep only first line

        if [[ -n "$generated_command" ]]; then
            # Clear buffer and show suggestion inline (like zsh-autosuggestions)
            BUFFER=""
            CURSOR=0
            llm_debugger_show_inline_suggestion "$generated_command"

            # Store suggestion data
            llm_debugger_suggestion="$generated_command"
            llm_debugger_has_suggestion=1
            llm_debugger_debug "Set up inline suggestion: '$generated_command'"
        else
            BUFFER=""
            CURSOR=0
            printf "\033[91mNo command generated (empty output)\033[0m\n"
            llm_debugger_debug "Generated command was empty"
        fi
    else
        BUFFER=""
        CURSOR=0
        printf "\033[91mError: Failed to generate command (exit code: $exit_code)\033[0m\n"
        llm_debugger_debug "Command generation failed - exit code: $exit_code"
        if [[ -f "$result_file" ]]; then
            llm_debugger_debug "Result file contents: $(cat "$result_file" 2>/dev/null)"
        fi
    fi

    # Clean up temp files
    rm -f "$temp_prompt" "$result_file"

    # Redraw
    zle redisplay
}

# Function to generate command for interactive ?? mode
llm_debugger_generate_command_interactive() {
    local prompt="$1"
    llm_debugger_debug "Generating command interactively from prompt: $prompt"

    # Use a simple file for communication
    local result_file="/tmp/llm_debugger_generate_result"

    # Reset state completely
    llm_debugger_suggestion=""
    llm_debugger_has_suggestion=0
    llm_debugger_clear_inline_suggestion

    # Clean up any existing result file
    rm -f "$result_file"

    # Create a temporary file for the prompt - use /tmp with PID to avoid subprocess
    local temp_prompt="/tmp/llm_debugger_$$_prompt_interactive"
    echo "$prompt" >"$temp_prompt"

    # Clear buffer and show animated loading spinner
    BUFFER=""
    CURSOR=0

    local spinner_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spinner_index=0

    # Start the Python script in background
    # Suppress job control messages before starting background process
    llm_debugger_suppress_jobs
    "${plugin_dir}/run_ollama_debugger.sh" "GENERATE_MODE" "$temp_prompt" "None" "generate" >"$result_file" 2>/dev/null &
    local python_pid=$!
    llm_debugger_debug "Started ollama_debugger.py in interactive mode with PID $python_pid"

    # Show loading spinner in the terminal output area
    while kill -0 "$python_pid" 2>/dev/null; do
        printf "\r\033[2K\033[36m%s\033[0m \033[90mGenerating suggestion...\033[0m" "${spinner_chars[$spinner_index]}"
        spinner_index=$(((spinner_index + 1) % ${#spinner_chars[@]}))
        sleep 0.1
    done

    # Wait for completion and clear the loading message
    wait $python_pid
    printf "\r\033[2K"

    # Read the result
    if [[ -f "$result_file" && -s "$result_file" ]]; then
        local generated_command=$(cat "$result_file")
        generated_command="${generated_command## }"
        generated_command="${generated_command%% }"

        if [[ -n "$generated_command" ]]; then
            # Show the suggestion inline (like zsh-autosuggestions)
            BUFFER=""
            CURSOR=0
            llm_debugger_show_inline_suggestion "$generated_command"

            # Store the suggestion
            llm_debugger_suggestion="$generated_command"
            llm_debugger_has_suggestion=1

            llm_debugger_debug "Set up inline suggestion: $generated_command"

            # Refresh display to show the suggestion
            zle redisplay
        else
            BUFFER=""
            CURSOR=0
            printf "\033[91mNo command generated\033[0m\n"
            zle reset-prompt
        fi
    else
        BUFFER=""
        CURSOR=0
        printf "\033[91mError: Failed to generate command\033[0m\n"
        zle reset-prompt
    fi

    # Clean up temp files
    rm -f "$temp_prompt" "$result_file"

    # Restore job control settings
    llm_debugger_restore_jobs
}

# Function to generate command from text prompt with inline UI (for function calls)
llm_debugger_generate_command() {
    local prompt="$1"
    llm_debugger_debug "Generating command from prompt: $prompt"

    # Use a simple file for communication instead of FIFO
    local result_file="/tmp/llm_debugger_generate_result"

    # Reset the suggestion variable
    llm_debugger_suggestion=""
    llm_debugger_has_suggestion=0

    # Clean up any existing result file
    rm -f "$result_file"

    # Create a temporary file for the prompt - use /tmp with PID to avoid subprocess
    local temp_prompt="/tmp/llm_debugger_$$_prompt_function"
    echo "$prompt" >"$temp_prompt"

    # Display animated loading spinner with better styling
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    # Create streaming output file
    local stream_file="/tmp/llm_debugger_$$_stream"
    rm -f "$stream_file"

    # Start the Python script in streaming mode, redirecting to stream file
    # Suppress job control messages before starting background process
    llm_debugger_suppress_jobs
    "${plugin_dir}/run_ollama_debugger.sh" "GENERATE_MODE" "$temp_prompt" "None" "generate" "stream" >"$stream_file" 2>/dev/null &
    local python_pid=$!
    llm_debugger_debug "Started ollama_debugger.py in streaming mode with PID $python_pid"

    # Monitor the streaming output
    local last_size=0
    local current_content=""
    local display_buffer=""
    local in_think=0

    while kill -0 "$python_pid" 2>/dev/null; do
        if [[ -f "$stream_file" ]]; then
            local current_size=$(wc -c <"$stream_file" 2>/dev/null || echo "0")
            if [[ $current_size -gt $last_size ]]; then
                # Read new content
                local new_content=$(tail -c +$((last_size + 1)) "$stream_file" 2>/dev/null)
                current_content+="$new_content"

                # Process the content for display
                if [[ "$current_content" == *"<think[THINK_START]"* ]]; then
                    in_think=1
                    printf "\r\033[2K\033[90m💭 Thinking..."
                elif [[ "$current_content" == *"[THINK_END]"* ]]; then
                    in_think=0
                    printf "\r\033[2K\033[32m▶\033[0m "
                    # Extract command after think tags
                    display_buffer="${current_content##*\[THINK_END\]}"
                    display_buffer="${display_buffer## }"
                    display_buffer="${display_buffer%%$'\n'*}"
                    display_buffer="${display_buffer%\%*}"
                    printf "%s" "$display_buffer"
                elif [[ $in_think -eq 0 ]]; then
                    # Not in think mode, show command being built
                    display_buffer="$current_content"
                    # Clean up display buffer
                    display_buffer="${display_buffer//<think\[THINK_START\]*/}"
                    display_buffer="${display_buffer//\[THINK_END\]*/}"
                    display_buffer="${display_buffer## }"
                    display_buffer="${display_buffer%%$'\n'*}"
                    display_buffer="${display_buffer%\%*}"
                    if [[ -n "$display_buffer" ]]; then
                        printf "\r\033[2K\033[32m▶\033[0m %s" "$display_buffer"
                    fi
                fi

                last_size=$current_size
            fi
        fi
        sleep 0.1
    done

    # Wait for completion and read final result
    wait $python_pid

    # Copy stream file to result file for final processing
    if [[ -f "$stream_file" ]]; then
        # Clean the content and save to result file
        local final_content=$(cat "$stream_file")
        final_content="${final_content//<think\[THINK_START\]*/}"
        final_content="${final_content//\[THINK_END\]*/}"
        final_content="${final_content## }"
        final_content="${final_content%% }"
        final_content="${final_content%%$'\n'*}"
        final_content="${final_content%\%*}"
        echo "$final_content" >"$result_file"
        rm -f "$stream_file"
    fi

    # Clear the line
    printf "\r\033[2K"

    # Read the result
    if [[ -f "$result_file" && -s "$result_file" ]]; then
        local generated_command=$(cat "$result_file")
        # Remove any extra whitespace
        generated_command="${generated_command## }"
        generated_command="${generated_command%% }"

        if [[ -n "$generated_command" ]]; then
            llm_debugger_suggestion="$generated_command"
            llm_debugger_has_suggestion=1
            llm_debugger_debug "Received suggestion: $llm_debugger_suggestion"

            # Show the suggestion inline (like zsh-autosuggestions)
            llm_debugger_show_inline_suggestion "$generated_command"

            llm_debugger_debug "Generated inline suggestion"
        else
            printf "\033[91mNo command generated\033[0m\n"
        fi
    else
        printf "\033[91mError: Failed to generate command\033[0m\n"
    fi

    # Clean up temp files
    rm -f "$temp_prompt" "$result_file"

    # Restore job control settings
    llm_debugger_restore_jobs
}

# Custom accept-line widget to intercept commands starting with '?' or '??'
llm_debugger_accept_line() {
    # Prevent recursion and excessive processing
    if [[ $LLM_DEBUGGER_PROCESSING -eq 1 || $LLM_DEBUGGER_WIDGET_ACTIVE -eq 1 ]]; then
        zle accept-line-orig
        return
    fi

    # Set widget active flag
    LLM_DEBUGGER_WIDGET_ACTIVE=1

    local cmd="${BUFFER}"
    llm_debugger_debug "accept-line widget triggered with buffer: '$cmd'"

    # Check if we're in suggestion mode
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # User pressed Enter while a suggestion is active - accept it
        local accepted_suggestion="$llm_debugger_suggestion"
        BUFFER="$accepted_suggestion"
        CURSOR=${#BUFFER}
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_debug "Accepted suggestion via Enter: $BUFFER"

        # Just accept the suggestion into the buffer, don't execute yet
        # Let the user press Enter again to execute
        LLM_DEBUGGER_WIDGET_ACTIVE=0
        zle redisplay
        return
    fi

    if [[ $cmd == \?\?* ]]; then
        # Handle ?? - generate command from text prompt
        LLM_DEBUGGER_PROCESSING=1
        local prompt="${cmd#\?\?}"
        prompt="${prompt# }" # Remove leading space
        llm_debugger_debug "Intercepted command generation prompt with '??': $prompt"

        # Clear the buffer completely and reset display
        BUFFER=""
        CURSOR=0
        region_highlight=()
        llm_debugger_debug "Cleared buffer for interactive generation"

        # Generate command and show inline - but call it synchronously in the widget
        llm_debugger_generate_command_interactive_sync "$prompt"
        LLM_DEBUGGER_PROCESSING=0
        LLM_DEBUGGER_WIDGET_ACTIVE=0
    elif [[ $cmd == \?* ]]; then
        # Handle ? - debug command execution
        LLM_DEBUGGER_PROCESSING=1
        local command="${cmd#\?}"
        command="${command# }" # Remove leading space
        llm_debugger_debug "Intercepted command with '?': $command"

        # Clear the buffer completely and reset display
        BUFFER=""
        CURSOR=0
        region_highlight=()
        llm_debugger_debug "Cleared buffer for debug execution"

        # Execute and analyze command and show inline - call synchronously in the widget
        llm_debugger_execute_and_analyze_sync "$command"
        LLM_DEBUGGER_PROCESSING=0
        LLM_DEBUGGER_WIDGET_ACTIVE=0
    else
        llm_debugger_debug "Command does not start with '?', executing normally"
        LLM_DEBUGGER_WIDGET_ACTIVE=0
        zle accept-line-orig
    fi
}

# Convenience functions for direct usage
debug_command() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: debug_command <command>"
        echo "Example: debug_command ls /nonexistent"
        return 1
    fi
    local command="$*"
    llm_debugger_execute_and_analyze "$command"
}

debug_command_openai() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: debug_command_openai <command>"
        echo "Example: debug_command_openai python3 -c 'import missing'"
        return 1
    fi
    local command="$*"

    # Temporarily switch to openai debugger
    local original_script="$LLM_DEBUGGER_SCRIPT"
    LLM_DEBUGGER_SCRIPT="${plugin_dir}/run_openai_debugger.sh"

    llm_debugger_execute_and_analyze "$command"

    # Restore original script
    LLM_DEBUGGER_SCRIPT="$original_script"
}

generate_command() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: generate_command <description>"
        echo "Example: generate_command list all python files"
        return 1
    fi
    local prompt="$*"
    llm_debugger_generate_command "$prompt"
}

# Simple forward-char wrapper to handle suggestions
llm_debugger_forward_char() {
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Accept the suggestion
        BUFFER="$llm_debugger_suggestion"
        CURSOR=${#BUFFER}
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_debug "Accepted suggestion via right arrow"
    else
        # Normal forward-char behavior
        zle forward-char-orig
    fi
}

# Cancel suggestion widget (for Escape key)
llm_debugger_cancel_suggestion_widget() {
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Clear the suggestion and buffer
        BUFFER=""
        CURSOR=0
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_original_buffer=""
        llm_debugger_original_cursor=""
        llm_debugger_debug "Cancelled suggestion via Escape"
        zle redisplay
    else
        # Normal escape behavior - send break
        zle send-break
    fi
}

# Interrupt suggestion widget (for Ctrl+C)
llm_debugger_interrupt_suggestion_widget() {
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Clear the suggestion and buffer
        BUFFER=""
        CURSOR=0
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_original_buffer=""
        llm_debugger_original_cursor=""
        llm_debugger_debug "Cancelled suggestion via Ctrl+C"
        zle redisplay
    else
        # Normal Ctrl+C behavior - send interrupt
        zle send-break
    fi
}

# Simple end-of-line wrapper to handle suggestions
llm_debugger_end_of_line() {
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Accept the suggestion
        BUFFER="$llm_debugger_suggestion"
        CURSOR=${#BUFFER}
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_debug "Accepted suggestion via end key"
    else
        # Normal end-of-line behavior
        zle end-of-line-orig
    fi
}

# Tab wrapper to handle suggestions (accept suggestion or do normal completion)
llm_debugger_tab_complete() {
    if [[ $llm_debugger_has_suggestion -eq 1 && -n "$llm_debugger_suggestion" ]]; then
        # Accept the suggestion
        BUFFER="$llm_debugger_suggestion"
        CURSOR=${#BUFFER}
        region_highlight=()
        llm_debugger_suggestion=""
        llm_debugger_has_suggestion=0
        llm_debugger_debug "Accepted suggestion via tab"
    else
        # Normal tab completion behavior
        zle expand-or-complete
    fi
}

# Save original widgets
zle -A accept-line accept-line-orig
zle -A forward-char forward-char-orig
zle -A end-of-line end-of-line-orig
llm_debugger_debug "Saved original widgets"

# Create and register custom widgets
zle -N llm_debugger_cancel_suggestion_widget
zle -N llm_debugger_interrupt_suggestion_widget
zle -N llm_debugger_tab_complete

# Replace widgets with our custom versions
zle -N accept-line llm_debugger_accept_line
zle -N forward-char llm_debugger_forward_char
zle -N end-of-line llm_debugger_end_of_line

# Bind keys globally for suggestion interaction
bindkey '^[' llm_debugger_cancel_suggestion_widget    # Escape (cancel suggestion)
bindkey '^C' llm_debugger_interrupt_suggestion_widget # Ctrl+C (cancel suggestion)
bindkey '^I' llm_debugger_tab_complete                # Tab (accept suggestion or complete)

llm_debugger_debug "Replaced widgets with suggestion-aware versions and bound cancel keys"
