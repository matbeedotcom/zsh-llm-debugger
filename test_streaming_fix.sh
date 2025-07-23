#!/bin/bash

# Test script for zsh-llm-debugger streaming fixes

echo "=== Testing zsh-llm-debugger Streaming Fixes ==="
echo

# Test 1: Test ?? command multiple times
echo "Test 1: Testing ?? command can be used multiple times"
echo "Please run the following commands in your zsh shell:"
echo
echo "1. ?? find all Python files"
echo "   (wait for suggestion, then press Tab or Enter to accept)"
echo
echo "2. ?? list files sorted by size" 
echo "   (wait for suggestion, then press Tab or Enter to accept)"
echo
echo "3. ?? show disk usage of current directory"
echo "   (wait for suggestion, then press Tab or Enter to accept)"
echo
echo "Expected: Each ?? command should:"
echo "- Show real-time streaming of think content in a box"
echo "- Display the command generation progress"
echo "- Show an inline suggestion that can be accepted"
echo "- Work correctly each time without errors"
echo

echo "Test 2: Testing ? command with streaming output"
echo "Please run the following command in your zsh shell:"
echo
echo "? find /nonexistent -name '*.py'"
echo
echo "Expected:"
echo "- Command executes and shows error"
echo "- Real-time streaming of think content in a box"
echo "- Display suggested fix as it's generated"
echo "- Show inline suggestion for the fix"
echo

echo "Test 3: Verify debug log"
echo "Run: tail -f ~/.llm_debugger_zsh.log"
echo "to monitor debug output during testing"
echo

echo "Press Enter to continue when ready to test..."
read
