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
# Guard against recursion with a flag
typeset -g LLM_DEBUGGER_IN_DEBUG=0

llm_debugger_debug() {
    # Guard against recursive calls
    if [[ $LLM_DEBUGGER_IN_DEBUG -eq 1 ]]; then
        return
    fi
    
    if [[ $LLM_DEBUGGER_DEBUG -eq 1 ]]; then
        # Set flag to prevent recursion
        LLM_DEBUGGER_IN_DEBUG=1
        
        # Use a simple timestamp or no timestamp to avoid subprocess creation
        # This prevents the "job table full" error from $(date) calls
        print -r -- "[DEBUG] $1" >>"$LLM_DEBUGGER_LOG_FILE"
        
        # Clear recursion guard
        LLM_DEBUGGER_IN_DEBUG=0
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
        local stream_file="/tmp/llm_debugger_$$_stream"
        rm -f "$debug_output_file" "$stream_file"

        llm_debugger_debug "Started Python debugger for command: $command"

        # Terminal width for formatting
        local term_width=$(tput cols)
        local box_width=$((term_width > 80 ? 80 : term_width - 4))
        
        # Show thinking box
        printf "\n\033[36m╭─ 💭 Analyzing Error ───────────────────────╮\033[0m\n"
        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "Examining the error output..."

        # Use proper debug mode with tools and few-shot examples - capture streaming output
        # Temporarily disable monitor to prevent job control messages
        local old_monitor
        if [[ -o monitor ]]; then
            old_monitor=1
            setopt NO_MONITOR
        else
            old_monitor=0
        fi
        
        "${plugin_dir}/run_ollama_debugger.sh" "$command" "$temp_output" "None" "script" >"$stream_file" 2>&1 &
        local python_pid=$!
        disown  # This prevents job control messages
        
        # Restore monitor option if it was set
        if [[ $old_monitor -eq 1 ]]; then
            setopt MONITOR
        fi
        
        # Monitor the separate output files
        local thinking_last_size=0
        local text_last_size=0
        local think_displayed=0
        local suggested_command=""
        local last_displayed_think=""
        
        while kill -0 "$python_pid" 2>/dev/null; do
            # Check thinking file for updates
            if [[ -f "$thinking_file" ]]; then
                local thinking_size=$(wc -c <"$thinking_file" 2>/dev/null || echo "0")
                if [[ $thinking_size -gt $thinking_last_size ]]; then
                    # Read FULL thinking content to avoid fragments
                    local full_thinking=$(cat "$thinking_file" 2>/dev/null)
                    
                    if [[ $think_displayed -eq 0 ]]; then
                        # Clear the "Examining..." line and show box header
                        printf "\r\033[2K"
                        printf "\033[A\033[2K"  # Move up and clear
                        think_displayed=1
                    else
                        # Clear previous box (move up 11 lines: header + 10 content lines)
                        for ((i=0; i<11; i++)); do
                            printf "\033[A\033[2K"
                        done
                    fi
                    
                    # Show box header with dynamic width
                    local header_dashes=$((box_width - 18))  # 15 chars for "╭─ 💭 Thinking " + 1 for "╮"
                    local dashes=$(printf '─%.0s' $(seq 1 $header_dashes))
                    printf "\033[36m╭─ 💭 Thinking %s╮\033[0m\n" "$dashes"
                    
                    # Get last 10 lines of thinking content
                    local lines=()
                    while IFS= read -r line; do
                        lines+=("$line")
                    done <<< "$full_thinking"
                    
                                    # Process all lines and wrap long ones, then show last 10 display lines
                local display_lines=()
                local start_idx=$((${#lines[@]} > 10 ? ${#lines[@]} - 10 : 0))
                for ((i=start_idx; i<${#lines[@]}; i++)); do
                    local line="${lines[i]}"
                    # Wrap long lines
                    while [[ ${#line} -gt $((box_width - 4)) ]]; do
                        # Find a good break point (space) within the allowed width
                        local break_point=$((box_width - 4))
                        local j=$break_point
                        while [[ $j -gt 0 && "${line:$j:1}" != " " ]]; do
                            ((j--))
                        done
                        # If no space found, break at max width
                        [[ $j -eq 0 ]] && j=$break_point
                        
                        display_lines+=("${line:0:$j}")
                        line="${line:$((j + 1))}"  # Skip the space
                    done
                    # Add remaining part of line
                    [[ -n "$line" ]] && display_lines+=("$line")
                done
                
                # Show last 10 display lines
                local display_start=$((${#display_lines[@]} > 10 ? ${#display_lines[@]} - 10 : 0))
                for ((i=display_start; i<${#display_lines[@]}; i++)); do
                    printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "${display_lines[i]}"
                done
                
                # Fill remaining lines with empty space to maintain 10-line box
                local displayed_lines=$((${#display_lines[@]} > 10 ? 10 : ${#display_lines[@]}))
                for ((i=displayed_lines; i<10; i++)); do
                    printf "\033[36m│\033[0m %-*s \033[36m│\033[0m\n" $((box_width - 4)) ""
                done
                
                thinking_last_size=$thinking_size
            fi
        fi
        
        # Check text file for command updates
        if [[ -f "$text_file" ]]; then
            local text_size=$(wc -c <"$text_file" 2>/dev/null || echo "0")
            if [[ $text_size -gt $text_last_size ]]; then
                # Check if thinking is done (no more updates for a bit)
                if [[ $think_displayed -eq 1 && $(wc -c <"$thinking_file" 2>/dev/null || echo "0") -eq $thinking_last_size ]]; then
                    # Close thinking box if not already closed
                    if [[ $think_displayed -eq 1 ]]; then
                        local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
                        printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
                        printf "\033[32m▶\033[0m Suggested fix: "
                        think_displayed=2
                        fi
                    fi
                    
                    # Read new text content
                    local new_text=$(tail -c +$((text_last_size + 1)) "$text_file" 2>/dev/null)
                    
                    # Extract command from markdown
                    if [[ "$new_text" == *'```'* ]]; then
                        local in_code_block="${new_text#*\`\`\`}"
                        # Skip language identifier
                        if [[ "${in_code_block:0:4}" == "bash" ]]; then
                            in_code_block="${in_code_block:4}"
                        fi
                        in_code_block="${in_code_block#$'\n'}"
                        if [[ "$in_code_block" == *'```'* ]]; then
                            suggested_command="${in_code_block%%\`\`\`*}"
                            suggested_command="${suggested_command%$'\n'}"
                            # Update display
                            printf "\r\033[2K\033[32m▶\033[0m Suggested fix: %s" "$suggested_command"
                        fi
                    fi
                    
                    text_last_size=$text_size
                fi
            fi
            
            sleep 0.01  # Faster refresh for smoother streaming
        done
        
        # Ensure thinking box is closed
        if [[ $think_displayed -eq 1 ]]; then
            local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
            printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
        fi
        
        # Wait for completion
        wait $python_pid 2>/dev/null
        local exit_code=$?

        llm_debugger_debug "Python debugger exit code: $exit_code"
        
        # Log raw model response if debug is enabled
        if [[ $LLM_DEBUGGER_DEBUG -eq 1 ]]; then
            if [[ -f "$thinking_file" ]]; then
                llm_debugger_debug "=== THINKING CONTENT START ==="
                cat "$thinking_file" >> "$LLM_DEBUGGER_LOG_FILE"
                llm_debugger_debug "=== THINKING CONTENT END ==="
            fi
            if [[ -f "$text_file" ]]; then
                llm_debugger_debug "=== TEXT CONTENT START ==="
                cat "$text_file" >> "$LLM_DEBUGGER_LOG_FILE"
                llm_debugger_debug "=== TEXT CONTENT END ==="
            fi
        fi

        # If we didn't extract a command during streaming, try from the final text file
        if [[ -z "$suggested_command" && -f "$text_file" ]]; then
            local full_content=$(cat "$text_file")
            # Try to extract command from markdown
            if [[ "$full_content" == *'```'* ]]; then
                local in_code_block="${full_content#*\`\`\`}"
                # Skip language identifier
                if [[ "${in_code_block:0:4}" == "bash" ]]; then
                    in_code_block="${in_code_block:4}"
                fi
                in_code_block="${in_code_block#$'\n'}"
                if [[ "$in_code_block" == *'```'* ]]; then
                    suggested_command="${in_code_block%%\`\`\`*}"
                    suggested_command="${suggested_command%$'\n'}"
                fi
            else
                # Fallback: first non-empty line
                suggested_command=$(echo "$full_content" | grep -v '^[[:space:]]*$' | head -1)
            fi
        fi
        
        # Clean up the command
            suggested_command="${suggested_command## }" # Remove leading spaces
            suggested_command="${suggested_command%% }" # Remove trailing spaces
        suggested_command="${suggested_command%%$'\n'*}" # Keep only first line

        # Clear the line
        printf "\r\033[2K"

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
            printf "\033[91mNo suggestion generated\033[0m\n"
            llm_debugger_debug "Failed to generate suggestion - exit code: $exit_code"
        fi

        # Clean up
        rm -f "$debug_output_file" "$stream_file" "$thinking_file" "$text_file"
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
    local stream_file="/tmp/llm_debugger_$$_debug_stream"

    # Function to cleanup temp files
    cleanup_temps() {
        rm -f "$temp_output" "$result_file" "$debug_output_file" "$stream_file"
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
        rm -f "$debug_output_file" "$stream_file"

        llm_debugger_debug "Started Python debugger for command: $command"

        # Terminal width for formatting
        local term_width=$(tput cols)
        local box_width=$((term_width > 80 ? 80 : term_width - 4))
        
        # Show thinking box
        printf "\n\033[36m╭─ 💭 Analyzing Error ───────────────────────╮\033[0m\n"
        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "Examining the error output..."
        
        # Run the Python script with output prefix for separate files
        local output_prefix="/tmp/llm_debugger_$$_output"
        local thinking_file="${output_prefix}_thinking"
        local text_file="${output_prefix}_text"
        
        # Clean up any existing files
        rm -f "$thinking_file" "$text_file"
        
        # Temporarily disable monitor to prevent job control messages
        local old_monitor
        if [[ -o monitor ]]; then
            old_monitor=1
            setopt NO_MONITOR
        else
            old_monitor=0
        fi
        
        "${plugin_dir}/run_ollama_debugger.sh" "$command" "$temp_output" "None" "script" "--output-prefix=$output_prefix" >"$stream_file" 2>&1 &
        local python_pid=$!
        disown  # This prevents job control messages
        
        # Restore monitor option if it was set
        if [[ $old_monitor -eq 1 ]]; then
            setopt MONITOR
        fi
        
        # Monitor the streaming output
        local last_size=0
        local current_content=""
        local in_think=0
        local think_content=""
        local think_displayed=0
        local suggested_command=""
        local found_think_tag=0
        
        while kill -0 "$python_pid" 2>/dev/null; do
            if [[ -f "$stream_file" ]]; then
                local current_size=$(wc -c <"$stream_file" 2>/dev/null || echo "0")
                if [[ $current_size -gt $last_size ]]; then
                    # Read new content
                    local new_content=$(tail -c +$((last_size + 1)) "$stream_file" 2>/dev/null)
                    
                    # Display the new content as it arrives (real-time streaming)
                    if [[ -n "$new_content" ]]; then
                        # Check if we're entering think mode
                        if [[ "$new_content" == *"<think>"* ]]; then
                            # Clear the "Examining..." line and show real content
                            printf "\r\033[2K"
                            # Move up to overwrite the initial "Examining..." line
                            printf "\033[A\033[2K"
                            in_think=1
                            found_think_tag=1
                        fi
                        
                        # Process the content
                        current_content+="$new_content"
                        
                        # If in think mode, display thinking content in real-time
                        if [[ $in_think -eq 1 ]]; then
                            # Extract think content
                            local temp_content="${current_content#*<think>}"
                            if [[ "$temp_content" == *"</think>"* ]]; then
                                # End of thinking
                                local think_text="${temp_content%%</think>*}"
                                # Display remaining think content
                                local lines_to_display="${think_text#*$last_displayed_think}"
                                while IFS= read -r line; do
                                    [[ -z "$line" && $think_displayed -eq 0 ]] && continue
                                    think_displayed=1
                                    # Word wrap if needed
                                    while [[ ${#line} -gt $((box_width - 4)) ]]; do
                                        local wrap_point=$((box_width - 4))
                                        local i=$wrap_point
                                        while [[ $i -gt 0 && "${line:$i:1}" != " " ]]; do
                                            ((i--))
                                        done
                                        [[ $i -eq 0 ]] && i=$wrap_point
                                        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "${line:0:$i}"
                                        line="${line:$((i + 1))}"
                                    done
                                    printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "$line"
                                done <<< "$lines_to_display"
                                
                                # Close thinking box
                                local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
                            printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
                                in_think=0
                                printf "\033[32m▶\033[0m Suggested fix: "
                                last_displayed_think="$think_text"
                            else
                                # Still in think mode, display new content line by line
                                local new_think_lines="${temp_content#*$last_displayed_think}"
                                # Only show complete lines
                                while IFS= read -r line; do
                                    if [[ -n "$line" ]]; then
                                        # Word wrap if needed
                                        while [[ ${#line} -gt $((box_width - 4)) ]]; do
                                            local wrap_point=$((box_width - 4))
                                            local i=$wrap_point
                                            while [[ $i -gt 0 && "${line:$i:1}" != " " ]]; do
                                                ((i--))
                                            done
                                            [[ $i -eq 0 ]] && i=$wrap_point
                                            printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "${line:0:$i}"
                                            line="${line:$((i + 1))}"
                                        done
                                        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "$line"
                                        last_displayed_think+=$'\n'"$line"
                                        think_displayed=1
                                    fi
                                done <<< "${new_think_lines%%$'\n'*}"
                            fi
                        else
                            # Not in think mode - look for command
                            if [[ "$current_content" == *"\`\`\`"* ]]; then
                                local after_fence="${current_content#*\`\`\`}"
                                after_fence="${after_fence#*$'\n'}"
                                if [[ "$after_fence" == *"\`\`\`"* ]]; then
                                    suggested_command="${after_fence%%\`\`\`*}"
                                    suggested_command="${suggested_command%$'\n'}"
                                    # Display the command as it's being generated
                                    printf "\r\033[2K\033[32m▶\033[0m Suggested fix: %s" "$suggested_command"
                                fi
                            elif [[ $found_think_tag -eq 0 && $think_displayed -eq 0 && "$current_content" =~ [[:alnum:]] ]]; then
                                # No think tags but we have content - show it directly
                                printf "\r\033[2K"
                                printf "\033[A\033[2K"  # Clear the "Examining..." line
                                printf "\033[32m▶\033[0m %s" "${current_content%%$'\n'*}"
                                think_displayed=2  # Skip think display
                                suggested_command="${current_content%%$'\n'*}"
                            fi
                        fi
                    fi
                    
                    last_size=$current_size
                fi
            fi
            sleep 0.01  # Faster refresh for smoother streaming
        done
    fi
    
    # Wait for completion
    wait $python_pid 2>/dev/null
    local exit_code=$?
    
    # Log raw model response if debug is enabled
    if [[ $LLM_DEBUGGER_DEBUG -eq 1 && -f "$stream_file" ]]; then
        llm_debugger_debug "=== RAW MODEL RESPONSE START (debug mode) ==="
        cat "$stream_file" >> "$LLM_DEBUGGER_LOG_FILE"
        llm_debugger_debug "=== RAW MODEL RESPONSE END ==="
    fi
    
    # If we didn't extract a command during streaming, try from the final output
    if [[ -z "$suggested_command" && -f "$stream_file" ]]; then
        local full_content=$(cat "$stream_file")
        # Remove think tags
        full_content="${full_content#*</think>}"
        # Try to extract command
        if [[ "$full_content" == *'`'*'`'* ]]; then
            suggested_command="${full_content#*\`}"
            suggested_command="${suggested_command%%\`*}"
        else
            suggested_command=$(echo "$full_content" | grep -v '^[[:space:]]*$' | head -1)
        fi
    fi
    
    # Clean up the command
    suggested_command="${suggested_command## }"      # Remove leading spaces
    suggested_command="${suggested_command%% }"      # Remove trailing spaces
    suggested_command="${suggested_command%%$'\n'*}" # Keep only first line

    # Clear the line
    printf "\r\033[2K"

    # Read the result and set up inline suggestion
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
        printf "\033[91mNo suggestion generated\033[0m\n"
        llm_debugger_debug "Failed to generate suggestion - exit code: $exit_code"
    fi

    # Clean up temp files
    cleanup_temps

    # Redraw
    zle redisplay
}

# Synchronous function for ?? mode (works within zle widget)
llm_debugger_generate_command_interactive_sync() {
    local prompt="$1"
    llm_debugger_debug " Generating command synchronously from prompt: $prompt"

    # Use a simple file for communication
    local result_file="/tmp/llm_debugger_generate_result"
    local temp_prompt="/tmp/llm_debugger_$$_prompt_sync"
    local stream_file="/tmp/llm_debugger_$$_stream_sync"
    echo "$prompt" >"$temp_prompt"

    # Clean up any existing result file
    rm -f "$result_file" "$stream_file"

    # Reset state completely - this is critical
    llm_debugger_suggestion=""
    llm_debugger_has_suggestion=0
    llm_debugger_original_buffer=""
    llm_debugger_original_cursor=""
    region_highlight=()

    # Clear buffer and show loading message
    BUFFER=""
    CURSOR=0

    # Terminal width for formatting
    local term_width=$(tput cols)
    local box_width=$((term_width > 80 ? 80 : term_width - 4))
    
    # Show initial status
    printf "\n\033[32m▶\033[0m Generating command..."

    # Temporarily disable job control messages
    local old_monitor
    if [[ -o monitor ]]; then
        old_monitor=1
        setopt NO_MONITOR
    else
        old_monitor=0
    fi

    # Run the Python script with output prefix for separate files
    local output_prefix="/tmp/llm_debugger_$$_generate_output"
    local thinking_file="${output_prefix}_thinking"
    local text_file="${output_prefix}_text"
    
    # Clean up any existing files
    rm -f "$thinking_file" "$text_file"
    
    # Start the command in background and immediately disown it
    "${plugin_dir}/run_ollama_debugger.sh" "GENERATE_MODE" "$temp_prompt" "None" "generate" "stream" "--output-prefix=$output_prefix" >"$stream_file" 2>/dev/null &
    local python_pid=$!
    disown  # This prevents job control messages
    
    # Restore monitor option if it was set
    if [[ $old_monitor -eq 1 ]]; then
        setopt MONITOR
    fi
    
    # Monitor the separate output files
    local thinking_last_size=0
    local text_last_size=0
    local think_displayed=0
    local generated_command=""
    local box_started=0
    
    llm_debugger_debug "Starting to monitor files: thinking=$thinking_file, text=$text_file"
    
    while kill -0 "$python_pid" 2>/dev/null; do
        # Check thinking file for updates
        if [[ -f "$thinking_file" ]]; then
            local thinking_size=$(wc -c <"$thinking_file" 2>/dev/null || echo "0")
            if [[ $thinking_size -gt $thinking_last_size ]]; then
                # Read FULL thinking content to avoid fragments
                local full_thinking=$(cat "$thinking_file" 2>/dev/null)
                
                if [[ $box_started -eq 0 ]]; then
                    # Clear the "Generating command..." line
                    printf "\r\033[2K"
                    box_started=1
                else
                    # Clear previous box (move up 11 lines: header + 10 content lines)
                    for ((i=0; i<11; i++)); do
                        printf "\033[A\033[2K"
                    done
                fi
                
                # Show box header with dynamic width
                local header_dashes=$((box_width - 14))  # 15 chars for "╭─ 💭 Thinking " + 1 for "╮"
                local dashes=$(printf '─%.0s' $(seq 1 $header_dashes))
                printf "\033[36m╭─ 💭 Thinking %s╮\033[0m\n" "$dashes"
                
                # Get last 10 lines of thinking content
                local lines=()
                while IFS= read -r line; do
                    lines+=("$line")
                done <<< "$full_thinking"
                
                # Process all lines and wrap long ones, then show last 10 display lines
                local display_lines=()
                local start_idx=$((${#lines[@]} > 10 ? ${#lines[@]} - 10 : 0))
                for ((i=start_idx; i<${#lines[@]}; i++)); do
                    local line="${lines[i]}"
                    # Wrap long lines
                    while [[ ${#line} -gt $((box_width - 4)) ]]; do
                        # Find a good break point (space) within the allowed width
                        local break_point=$((box_width - 4))
                        local j=$break_point
                        while [[ $j -gt 0 && "${line:$j:1}" != " " ]]; do
                            ((j--))
                        done
                        # If no space found, break at max width
                        [[ $j -eq 0 ]] && j=$break_point
                        
                        display_lines+=("${line:0:$j}")
                        line="${line:$((j + 1))}"  # Skip the space
                    done
                    # Add remaining part of line
                    [[ -n "$line" ]] && display_lines+=("$line")
                done
                
                # Show last 10 display lines
                local display_start=$((${#display_lines[@]} > 10 ? ${#display_lines[@]} - 10 : 0))
                for ((i=display_start; i<${#display_lines[@]}; i++)); do
                    printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "${display_lines[i]}"
                done
                
                # Fill remaining lines with empty space to maintain 10-line box
                local displayed_lines=$((${#display_lines[@]} > 10 ? 10 : ${#display_lines[@]}))
                for ((i=displayed_lines; i<10; i++)); do
                    printf "\033[36m│\033[0m %-*s \033[36m│\033[0m\n" $((box_width - 4)) ""
                done
                
                thinking_last_size=$thinking_size
            fi
        fi
        
        # Check text file for command updates
        if [[ -f "$text_file" ]]; then
            local text_size=$(wc -c <"$text_file" 2>/dev/null || echo "0")
            if [[ $text_size -gt $text_last_size ]]; then
                # Check if thinking is done (no more updates for a bit)
                if [[ $box_started -eq 1 && $think_displayed -eq 0 && $(wc -c <"$thinking_file" 2>/dev/null || echo "0") -eq $thinking_last_size ]]; then
                    # Close thinking box
                    local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
                    printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
                    printf "\033[32m▶\033[0m "
                    think_displayed=1
                fi
                
                # Read new text content
                local new_text=$(tail -c +$((text_last_size + 1)) "$text_file" 2>/dev/null)
                
                # Extract command from markdown
                if [[ "$new_text" == *'```'* ]]; then
                    local in_code_block="${new_text#*\`\`\`}"
                    # Skip language identifier
                    if [[ "${in_code_block:0:4}" == "bash" ]]; then
                        in_code_block="${in_code_block:4}"
                    fi
                    in_code_block="${in_code_block#$'\n'}"
                    if [[ "$in_code_block" == *'```'* ]]; then
                        generated_command="${in_code_block%%\`\`\`*}"
                        generated_command="${generated_command%$'\n'}"
                        # Update display
                        printf "\r\033[2K\033[32m▶\033[0m %s" "$generated_command"
                    fi
                fi
                
                text_last_size=$text_size
            fi
        fi
        sleep 0.01  # Faster refresh for smoother streaming
    done
    
    # Wait for completion
    llm_debugger_debug "Waiting for Python process $python_pid to complete (sync generate)"
    wait $python_pid 2>/dev/null
    local exit_code=$?
    llm_debugger_debug "Python process completed with exit code: $exit_code (sync generate)"

    # Ensure thinking box is closed
    if [[ $box_started -eq 1 && $think_displayed -eq 0 ]]; then
        local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
        printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
    fi

    # Log raw model response if debug is enabled
    if [[ $LLM_DEBUGGER_DEBUG -eq 1 ]]; then
        if [[ -f "$thinking_file" ]]; then
            llm_debugger_debug "=== THINKING CONTENT START (generate mode) ==="
            cat "$thinking_file" >> "$LLM_DEBUGGER_LOG_FILE"
            llm_debugger_debug "=== THINKING CONTENT END ==="
        fi
        if [[ -f "$text_file" ]]; then
            llm_debugger_debug "=== TEXT CONTENT START (generate mode) ==="
            cat "$text_file" >> "$LLM_DEBUGGER_LOG_FILE"
            llm_debugger_debug "=== TEXT CONTENT END ==="
        fi
    fi

    # Check file status after Python completion
    llm_debugger_debug "After Python completion - thinking file exists: $([[ -f "$thinking_file" ]] && echo "yes ($(wc -c <"$thinking_file" 2>/dev/null) bytes)" || echo "no")"
    llm_debugger_debug "After Python completion - text file exists: $([[ -f "$text_file" ]] && echo "yes ($(wc -c <"$text_file" 2>/dev/null) bytes)" || echo "no")"
    
    # If we didn't extract a command during streaming, try from the final text file
    if [[ -z "$generated_command" && -f "$text_file" ]]; then
        local full_content=$(cat "$text_file")
        llm_debugger_debug "Text file content length: ${#full_content}"
        llm_debugger_debug "Text file content: ${full_content:0:200}..."
        # Extract from markdown code block
        if [[ "$full_content" == *'```'* ]]; then
            local in_code_block="${full_content#*\`\`\`}"
            # Skip language identifier
            if [[ "${in_code_block:0:4}" == "bash" ]]; then
                in_code_block="${in_code_block:4}"
            fi
            in_code_block="${in_code_block#$'\n'}"
            if [[ "$in_code_block" == *'```'* ]]; then
                generated_command="${in_code_block%%\`\`\`*}"
                generated_command="${generated_command%$'\n'}"
                llm_debugger_debug "Extracted command from markdown: '$generated_command'"
            fi
        else
            llm_debugger_debug "No markdown code block found in text file"
        fi
    else
        llm_debugger_debug "Text file doesn't exist or generated_command already set: generated_command='$generated_command', text_file exists: $([[ -f "$text_file" ]] && echo "yes" || echo "no")"
    fi
    
    # Clean up the command
    generated_command="${generated_command## }"
    generated_command="${generated_command%% }"
    llm_debugger_debug "Final cleaned command: '$generated_command'"
    
    # Clear the line
    printf "\r\033[2K"

    # Read the result and set up inline suggestion
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
        printf "\033[91mNo command generated\033[0m\n"
        llm_debugger_debug "Generated command was empty or exit code was non-zero"
    fi

    # Clean up temp files
    rm -f "$temp_prompt" "$result_file" "$stream_file" "$thinking_file" "$text_file"

    # Redraw
    zle redisplay
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

    # Create streaming output file and separate files
    local stream_file="/tmp/llm_debugger_$$_stream"
    local output_prefix="/tmp/llm_debugger_$$_func_output"
    local thinking_file="${output_prefix}_thinking"
    local text_file="${output_prefix}_text"
    
    # Clean up any existing files
    rm -f "$stream_file" "$thinking_file" "$text_file"

    # Start the Python script in streaming mode with output prefix
    # Suppress job control messages before starting background process
    llm_debugger_suppress_jobs
    
    # Temporarily disable monitor to prevent job control messages
    local old_monitor
    if [[ -o monitor ]]; then
        old_monitor=1
        setopt NO_MONITOR
    else
        old_monitor=0
    fi
    
    "${plugin_dir}/run_ollama_debugger.sh" "GENERATE_MODE" "$temp_prompt" "None" "generate" "stream" "--output-prefix=$output_prefix" >"$stream_file" 2>/dev/null &
    local python_pid=$!
    disown  # This prevents job control messages
    
    # Restore monitor option if it was set
    if [[ $old_monitor -eq 1 ]]; then
        setopt MONITOR
    fi
    
    llm_debugger_debug "Started ollama_debugger.py in streaming mode with PID $python_pid"

    # Monitor the separate output files
    local thinking_last_size=0
    local text_last_size=0
    local think_displayed=0
    local final_command=""
    local box_started=0

    # Terminal width for formatting
    local term_width=$(tput cols)
    local box_width=$((term_width > 80 ? 80 : term_width - 4))
    
    # Show initial status
    printf "\n\033[32m▶\033[0m Generating command..."

    while kill -0 "$python_pid" 2>/dev/null; do
        # Check thinking file for updates
        if [[ -f "$thinking_file" ]]; then
            local thinking_size=$(wc -c <"$thinking_file" 2>/dev/null || echo "0")
            if [[ $thinking_size -gt $thinking_last_size ]]; then
                # Read FULL thinking content to avoid fragments
                local full_thinking=$(cat "$thinking_file" 2>/dev/null)
                
                if [[ $box_started -eq 0 ]]; then
                    # Clear the "Generating command..." line
                    printf "\r\033[2K"
                    box_started=1
                else
                    # Clear previous box (move up 11 lines: header + 10 content lines)
                    for ((i=0; i<11; i++)); do
                        printf "\033[A\033[2K"
                    done
                fi
                
                # Show box header
                # Show box header with dynamic width
                local header_dashes=$((box_width - 13))  # 15 chars for "╭─ 💭 Thinking " + 1 for "╮"
                local dashes=$(printf '─%.0s' $(seq 1 $header_dashes))
                printf "\033[36m╭─ 💭 Thinking %s╮\033[0m\n" "$dashes"
                
                # Get last 10 lines of thinking content
                local lines=()
                while IFS= read -r line; do
                    lines+=("$line")
                done <<< "$full_thinking"
                
                # Show last 10 lines (or fewer if less content)
                local start_idx=$((${#lines[@]} > 10 ? ${#lines[@]} - 10 : 0))
                for ((i=start_idx; i<${#lines[@]}; i++)); do
                    local line="${lines[i]}"
                    if [[ ${#line} -gt $((box_width - 4)) ]]; then
                        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "${line:0:$((box_width - 7))}..."
                    else
                        printf "\033[36m│\033[0m \033[90m%-*s\033[0m \033[36m│\033[0m\n" $((box_width - 2)) "$line"
                    fi
                done
                
                # Fill remaining lines with empty space to maintain 10-line box
                local displayed_lines=$((${#lines[@]} > 10 ? 10 : ${#lines[@]}))
                for ((i=displayed_lines; i<10; i++)); do
                    printf "\033[36m│\033[0m %-*s \033[36m│\033[0m\n" $((box_width - 4)) ""
                done
                
                thinking_last_size=$thinking_size
            fi
        fi
        
        # Check text file for command updates
        if [[ -f "$text_file" ]]; then
            local text_size=$(wc -c <"$text_file" 2>/dev/null || echo "0")
            if [[ $text_size -gt $text_last_size ]]; then
                # Check if thinking is done (no more updates for a bit)
                if [[ $box_started -eq 1 && $think_displayed -eq 0 && $(wc -c <"$thinking_file" 2>/dev/null || echo "0") -eq $thinking_last_size ]]; then
                    # Close thinking box
                    local footer_dashes=$(printf '─%.0s' $(seq 1 $((box_width))))
                    printf "\033[36m╰%s╯\033[0m\n\n" "$footer_dashes"
                    printf "\033[32m▶\033[0m "
                    think_displayed=1
                fi
                
                # Read new text content
                local new_text=$(tail -c +$((text_last_size + 1)) "$text_file" 2>/dev/null)
                
                # Extract command from markdown
                if [[ "$new_text" == *'```'* ]]; then
                    local in_code_block="${new_text#*\`\`\`}"
                    # Skip language identifier
                    if [[ "${in_code_block:0:4}" == "bash" ]]; then
                        in_code_block="${in_code_block:4}"
                    fi
                    in_code_block="${in_code_block#$'\n'}"
                    if [[ "$in_code_block" == *'```'* ]]; then
                        final_command="${in_code_block%%\`\`\`*}"
                        final_command="${final_command%$'\n'}"
                        # Update display
                        printf "\r\033[2K\033[32m▶\033[0m %s" "$final_command"
                    fi
                fi
                
                text_last_size=$text_size
            fi
        fi
        
        sleep 0.01  # Faster refresh for smoother streaming
    done

    # Ensure thinking box is closed
    if [[ $box_started -eq 1 && $think_displayed -eq 0 ]]; then
        printf "\033[36m╰────────────────────────────────────────────────╯\033[0m\n\n"
    fi

    # Wait for completion and read final result
    wait $python_pid 2>/dev/null

    # Log raw model response if debug is enabled
    if [[ $LLM_DEBUGGER_DEBUG -eq 1 ]]; then
        if [[ -f "$thinking_file" ]]; then
            llm_debugger_debug "=== THINKING CONTENT START (generate_command) ==="
            cat "$thinking_file" >> "$LLM_DEBUGGER_LOG_FILE"
            llm_debugger_debug "=== THINKING CONTENT END ==="
        fi
        if [[ -f "$text_file" ]]; then
            llm_debugger_debug "=== TEXT CONTENT START (generate_command) ==="
            cat "$text_file" >> "$LLM_DEBUGGER_LOG_FILE"
            llm_debugger_debug "=== TEXT CONTENT END ==="
        fi
    fi

    # Extract final command if not already done
    if [[ -z "$final_command" && -f "$text_file" ]]; then
        local full_content=$(cat "$text_file")
        # Extract from markdown code block
        if [[ "$full_content" == *'```'* ]]; then
            local in_code_block="${full_content#*\`\`\`}"
            # Skip language identifier
            if [[ "${in_code_block:0:4}" == "bash" ]]; then
                in_code_block="${in_code_block:4}"
            fi
            in_code_block="${in_code_block#$'\n'}"
            if [[ "$in_code_block" == *'```'* ]]; then
                final_command="${in_code_block%%\`\`\`*}"
                final_command="${final_command%$'\n'}"
            fi
        fi
    fi
    
    # Clean and save the final command
    final_command="${final_command## }"
    final_command="${final_command%% }"
    if [[ -n "$final_command" ]]; then
        echo "$final_command" >"$result_file"
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
    rm -f "$temp_prompt" "$result_file" "$stream_file" "$thinking_file" "$text_file"

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
        llm_debugger_original_buffer=""
        llm_debugger_original_cursor=""
        llm_debugger_debug "Accepted suggestion via Enter: $BUFFER"

        # Execute the accepted command
        LLM_DEBUGGER_WIDGET_ACTIVE=0
        zle accept-line-orig
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

# Convenience function to view debug log
llm_debugger_show_log() {
    if [[ -f "$LLM_DEBUGGER_LOG_FILE" ]]; then
        echo "Debug log: $LLM_DEBUGGER_LOG_FILE"
        echo "---"
        tail -n 50 "$LLM_DEBUGGER_LOG_FILE"
    else
        echo "No debug log found at $LLM_DEBUGGER_LOG_FILE"
    fi
}

# Convenience function to tail debug log
llm_debugger_tail_log() {
    if [[ -f "$LLM_DEBUGGER_LOG_FILE" ]]; then
        echo "Tailing debug log: $LLM_DEBUGGER_LOG_FILE (Ctrl+C to stop)"
        tail -f "$LLM_DEBUGGER_LOG_FILE"
    else
        echo "No debug log found at $LLM_DEBUGGER_LOG_FILE"
    fi
}

# Convenience function to clear debug log
llm_debugger_clear_log() {
    if [[ -f "$LLM_DEBUGGER_LOG_FILE" ]]; then
        echo "Clearing debug log: $LLM_DEBUGGER_LOG_FILE"
        > "$LLM_DEBUGGER_LOG_FILE"
        echo "Debug log cleared"
    else
        echo "No debug log found at $LLM_DEBUGGER_LOG_FILE"
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
