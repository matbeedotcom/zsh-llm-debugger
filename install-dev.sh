#!/bin/bash

# ZSH LLM Debugger Development Setup Script
# This script sets up the development environment for working on zsh-llm-debugger

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located (project root)
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}=== ZSH LLM Debugger Development Setup ===${NC}"
echo -e "${GREEN}Project directory: $PROJECT_DIR${NC}"
echo

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed. Please install Python 3.8 or later.${NC}"
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
REQUIRED_VERSION="3.8"
if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo -e "${RED}Error: Python $PYTHON_VERSION is too old. Please install Python 3.8 or later.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Python $PYTHON_VERSION found${NC}"

# Check if we're in the right directory
if [ ! -f "$PROJECT_DIR/zsh-llm-debugger.plugin.zsh" ]; then
    echo -e "${RED}Error: This doesn't appear to be the zsh-llm-debugger project directory.${NC}"
    echo -e "${RED}Expected to find zsh-llm-debugger.plugin.zsh in the current directory.${NC}"
    exit 1
fi

# Check if virtual environment already exists
if [ -d "$PROJECT_DIR/venv" ]; then
    echo -e "${YELLOW}Virtual environment already exists.${NC}"
    echo -e "${YELLOW}Would you like to recreate it? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Removing existing virtual environment...${NC}"
        rm -rf "$PROJECT_DIR/venv"
    else
        echo -e "${GREEN}Using existing virtual environment...${NC}"
    fi
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$PROJECT_DIR/venv" ]; then
    echo -e "${GREEN}Creating Python virtual environment...${NC}"
    python3 -m venv venv
fi

# Activate virtual environment
echo -e "${GREEN}Activating virtual environment...${NC}"
source "$PROJECT_DIR/venv/bin/activate"

# Upgrade pip in virtual environment
echo -e "${GREEN}Upgrading pip...${NC}"
pip install --upgrade pip

# Install Python dependencies
echo -e "${GREEN}Installing Python dependencies...${NC}"
pip install -r "$PROJECT_DIR/requirements.txt"

# Install development dependencies if they exist
if [ -f "$PROJECT_DIR/requirements-dev.txt" ]; then
    echo -e "${GREEN}Installing development dependencies...${NC}"
    pip install -r "$PROJECT_DIR/requirements-dev.txt"
fi

# Make Python scripts executable
echo -e "${GREEN}Making Python scripts executable...${NC}"
chmod +x "$PROJECT_DIR"/*.py

# Check for Ollama (optional)
echo
if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}Ollama is not installed.${NC}"
    echo -e "${YELLOW}For testing with Ollama, install it with:${NC}"
    echo "curl -fsSL https://ollama.com/install.sh | sh"
    echo "ollama pull qwen2.5:1.5b"
else
    echo -e "${GREEN}✓ Ollama is installed${NC}"
    # Check if the model is already pulled
    if ! ollama list 2>/dev/null | grep -q "qwen2.5:1.5b"; then
        echo -e "${YELLOW}The default model (qwen2.5:1.5b) is not installed.${NC}"
        echo -e "${YELLOW}Pull it with: ollama pull qwen2.5:1.5b${NC}"
    else
        echo -e "${GREEN}✓ Default model (qwen2.5:1.5b) is available${NC}"
    fi
fi

# Create a development activation script
echo -e "${GREEN}Creating development activation script...${NC}"
cat > "$PROJECT_DIR/activate-dev.sh" << 'EOF'
#!/bin/bash
# Source this file to activate the development environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Activate Python virtual environment
source "$SCRIPT_DIR/venv/bin/activate"

# Add project directory to PATH for easy access to scripts
export PATH="$SCRIPT_DIR:$PATH"

# Source the plugin for testing
source "$SCRIPT_DIR/zsh-llm-debugger.plugin.zsh"

echo "Development environment activated!"
echo "Python venv: $VIRTUAL_ENV"
echo "Commands available: ?, ??"
EOF

chmod +x "$PROJECT_DIR/activate-dev.sh"

# Deactivate virtual environment
deactivate

echo
echo -e "${GREEN}=== Development Setup Complete! ===${NC}"
echo
echo -e "${BLUE}To start developing:${NC}"
echo "  1. Activate the environment: ${GREEN}source activate-dev.sh${NC}"
echo "  2. This will:"
echo "     - Activate the Python virtual environment"
echo "     - Add the project directory to PATH"
echo "     - Source the plugin for testing"
echo
echo -e "${BLUE}For manual testing without activation script:${NC}"
echo "  1. Activate venv: ${GREEN}source venv/bin/activate${NC}"
echo "  2. Source plugin: ${GREEN}source zsh-llm-debugger.plugin.zsh${NC}"
echo
echo -e "${BLUE}Testing commands:${NC}"
echo "  ${GREEN}? git push${NC}              # Debug a failed command"
echo "  ${GREEN}?? list all files${NC}       # Generate a command"
echo
echo -e "${BLUE}Running scripts directly:${NC}"
echo "  ${GREEN}./venv/bin/python ollama_debugger.py ...${NC}"
echo "  ${GREEN}./venv/bin/python openai_debugger.py ...${NC}"
echo
echo -e "${BLUE}Environment variables for testing:${NC}"
echo "  ${GREEN}export LLM_DEBUGGER_BACKEND=ollama${NC}  # or 'openai'"
echo "  ${GREEN}export LLM_DEBUGGER_MODEL=qwen2.5:1.5b${NC}"
echo "  ${GREEN}export OPENAI_API_KEY=your-key${NC}       # for OpenAI backend"
echo
echo -e "${GREEN}Happy developing!${NC}" 