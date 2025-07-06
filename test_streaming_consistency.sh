#!/bin/bash

echo "=== Testing Streaming Consistency Across All Modes ==="
echo ""

# Load the plugin
source zsh-llm-debugger.plugin.zsh

echo "Loaded LLM Debugger Plugin"
echo ""

echo "=== Test 1: ?? Mode (Interactive Generation) ==="
echo "Type: ?? find all files bigger than 1MB"
echo "Expected: Streaming with 💭 Thinking... then gray suggestion"
echo "---"

echo "=== Test 2: generate_command Mode (Function Call) ==="
echo "Type: generate_command \"list all python files recursively\""
echo "Expected: Terminal streaming with 💭 Thinking... then ▶ command"
echo "---"

echo "=== Test 3: ? Mode (Debug Failed Command) ==="
echo "Type: ? ls /nonexistent"
echo "Expected: Terminal streaming with 💭 Analyzing error... then 🔧 suggestion"
echo "---"

echo ""
echo "🎯 Consistency Check:"
echo "1. All modes should show streaming content"
echo "2. All modes should display thinking process"
echo "3. All modes should use consistent visual indicators:"
echo "   - ?? mode: Command line buffer with gray suggestion"
echo "   - generate_command: Terminal output with ▶ prefix"
echo "   - ? mode: Terminal output with 🔧 prefix"
echo "4. All modes should properly clean up streaming files"

echo ""
echo "Ready for testing! Try the commands above..."
