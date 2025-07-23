#!/bin/bash

echo "=== Testing Thinking Content Display ==="
echo
echo "This test will verify that thinking content is properly displayed."
echo
echo "Run these commands in your zsh shell:"
echo
echo "1. source zsh-llm-debugger.plugin.zsh"
echo "2. ?? count lines of code in all JavaScript files"
echo
echo "Expected output:"
echo "- Thinking box appears with borders"
echo "- Model's reasoning streams character by character inside the box"
echo "- Box closes when thinking completes" 
echo "- Final command appears after the box"
echo
echo "If thinking content is empty:"
echo "1. Enable debug: export LLM_DEBUGGER_DEBUG=1"
echo "2. Run the command again"
echo "3. Check logs: tail -100 ~/.llm_debugger_zsh.log | grep -E '(think|Think)'"
echo
echo "Direct test of Python script:"
echo "echo 'list all files' > /tmp/test.txt"
echo "./run_ollama_debugger.sh GENERATE_MODE /tmp/test.txt None generate stream" 