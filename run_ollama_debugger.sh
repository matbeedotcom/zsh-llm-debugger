#!/bin/bash
# Wrapper script to run ollama_debugger.py with virtual environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Activate virtual environment
source "$SCRIPT_DIR/venv/bin/activate"

# Run the Python script with all arguments
python3 "$SCRIPT_DIR/ollama_debugger.py" "$@"

# Exit with the same code as the Python script
exit $?