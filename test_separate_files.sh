#!/bin/bash

# Test script to verify separate thinking and text files functionality

echo "Testing separate files output..."

# Create a test prompt
echo "list all python files in the current directory" > /tmp/test_prompt.txt

# Run the Python script with output prefix
OUTPUT_PREFIX="/tmp/test_output"
echo "Running: python3 ollama_debugger.py GENERATE_MODE /tmp/test_prompt.txt None generate stream --output-prefix=$OUTPUT_PREFIX"

# Activate virtual environment if it exists
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi

# Run the command
python3 ollama_debugger.py GENERATE_MODE /tmp/test_prompt.txt None generate stream --output-prefix=$OUTPUT_PREFIX

echo ""
echo "=== RESULTS ==="

# Check if files were created
if [ -f "${OUTPUT_PREFIX}_thinking" ]; then
    echo "✓ Thinking file created: ${OUTPUT_PREFIX}_thinking"
    echo "Content:"
    echo "---"
    cat "${OUTPUT_PREFIX}_thinking"
    echo "---"
else
    echo "✗ Thinking file NOT created"
fi

echo ""

if [ -f "${OUTPUT_PREFIX}_text" ]; then
    echo "✓ Text file created: ${OUTPUT_PREFIX}_text"
    echo "Content:"
    echo "---"
    cat "${OUTPUT_PREFIX}_text"
    echo "---"
else
    echo "✗ Text file NOT created"
fi

# Cleanup
rm -f /tmp/test_prompt.txt "${OUTPUT_PREFIX}_thinking" "${OUTPUT_PREFIX}_text"

echo ""
echo "Test complete!" 