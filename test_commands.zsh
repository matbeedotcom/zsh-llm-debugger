#!/bin/zsh

# Source the plugin
source ./zsh-llm-debugger.plugin.zsh

# Enable debug mode
export LLM_DEBUGGER_DEBUG=1

echo "=========================================="
echo "Testing zsh-llm-debugger core functions"
echo "=========================================="

echo -e "\n1. Testing debug_command with a failing command:"
echo "Running: debug_command find /nonexistent -name '*.py'"
debug_command find /nonexistent -name '*.py'

echo -e "\n\n2. Testing generate_command function:"
echo "Running: generate_command find all Python files modified today"
generate_command find all Python files modified today

echo -e "\n\n3. Showing debug log to see raw responses:"
echo "Last 30 lines of debug log:"
tail -n 30 ~/.llm_debugger_zsh.log || echo "No debug log found"

echo -e "\nTest complete!" 