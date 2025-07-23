#!/bin/bash

# Test script to verify improved word wrapping

echo "Testing word wrapping improvements..."

# Create a test prompt that should generate a longer thinking response
echo "explain how to find and delete duplicate files in a directory tree efficiently" > /tmp/test_wrap_prompt.txt

echo "Running test with debug enabled..."
export LLM_DEBUGGER_DEBUG=1

# Activate virtual environment and run
source venv/bin/activate
./run_ollama_debugger.sh GENERATE_MODE /tmp/test_wrap_prompt.txt None generate stream --output-prefix=/tmp/wrap_test

echo ""
echo "=== Debug log excerpt ==="
if [ -f ~/.llm_debugger_zsh.log ]; then
    tail -10 ~/.llm_debugger_zsh.log
else
    echo "No debug log found"
fi

echo ""
echo "=== Thinking file content ==="
if [ -f /tmp/wrap_test_thinking ]; then
    echo "Size: $(wc -c < /tmp/wrap_test_thinking) bytes"
    cat /tmp/wrap_test_thinking
else
    echo "No thinking file found"
fi

# Cleanup
rm -f /tmp/test_wrap_prompt.txt /tmp/wrap_test_*

echo ""
echo "Test complete!" 