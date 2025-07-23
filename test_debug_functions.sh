#!/bin/bash

echo "Testing zsh-llm-debugger debug functions..."
echo "=========================================="

# Source the plugin in a zsh shell
zsh -c '
# Source the plugin
source ./zsh-llm-debugger.plugin.zsh

echo "1. Testing debug mode setting..."
export LLM_DEBUGGER_DEBUG=1
echo "Debug mode: $LLM_DEBUGGER_DEBUG"

echo -e "\n2. Testing llm_debugger_clear_log..."
llm_debugger_clear_log

echo -e "\n3. Testing debug logging..."
llm_debugger_debug "Test debug message"

echo -e "\n4. Testing llm_debugger_show_log..."
llm_debugger_show_log

echo -e "\n5. Checking log file directly..."
if [[ -f "$LLM_DEBUGGER_LOG_FILE" ]]; then
    echo "Log file exists at: $LLM_DEBUGGER_LOG_FILE"
    echo "Contents:"
    cat "$LLM_DEBUGGER_LOG_FILE"
else
    echo "Log file not found!"
fi

echo -e "\n6. Testing with a simple command..."
# This will test if the debug logging captures output
debug_command ls /nonexistent_directory_test_12345
'

echo -e "\nTest complete!" 