#!/bin/zsh

# Source the plugin
source ./zsh-llm-debugger.plugin.zsh

# Enable debug mode
export LLM_DEBUGGER_DEBUG=1

echo "Testing debug functions..."

# Test debug logging
llm_debugger_debug "Test message from simple_test.sh"

# Test showing log
echo -e "\nShowing log:"
llm_debugger_show_log

# Test clearing log
echo -e "\nClearing log:"
llm_debugger_clear_log

# Verify it's cleared
echo -e "\nShowing log after clear:"
llm_debugger_show_log 