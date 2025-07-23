#!/bin/bash

# ZSH LLM Debugger Installation Script
# This script installs the zsh-llm-debugger plugin and its dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Installation directory (where to copy files to)
INSTALL_DIR="${HOME}/.zsh-llm-debugger"

echo -e "${GREEN}=== ZSH LLM Debugger Installation ===${NC}"
echo

# Check if zsh is installed
if ! command -v zsh &> /dev/null; then
    echo -e "${RED}Error: Zsh is not installed. Please install Zsh first.${NC}"
    exit 1
fi

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

# Check if pip is installed
if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
    echo -e "${RED}Error: pip is not installed. Please install pip3.${NC}"
    exit 1
fi

# Determine pip command
if command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
else
    PIP_CMD="pip"
fi

# Copy files to installation directory
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}Removing existing installation...${NC}"
        rm -rf "$INSTALL_DIR"
    fi
    echo -e "${GREEN}Copying files to $INSTALL_DIR...${NC}"
    mkdir -p "$INSTALL_DIR"
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
else
    echo -e "${GREEN}Installing from $INSTALL_DIR...${NC}"
fi

# Create virtual environment
echo -e "${GREEN}Creating Python virtual environment...${NC}"
cd "$INSTALL_DIR"
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip in virtual environment
pip install --upgrade pip

# Install Python dependencies
echo -e "${GREEN}Installing Python dependencies in virtual environment...${NC}"
pip install -r requirements.txt

# Deactivate virtual environment
deactivate

# Make Python scripts executable
chmod +x "$INSTALL_DIR"/*.py

# Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}Ollama is not installed. Would you like to install it now? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Installing Ollama...${NC}"
        curl -fsSL https://ollama.com/install.sh | sh
        
        # Pull the default model
        echo -e "${GREEN}Pulling qwen2.5:1.5b model...${NC}"
        ollama pull qwen2.5:1.5b
    else
        echo -e "${YELLOW}Skipping Ollama installation. You can install it later with:${NC}"
        echo "curl -fsSL https://ollama.com/install.sh | sh"
        echo "ollama pull qwen2.5:1.5b"
    fi
else
    # Check if the model is already pulled
    if ! ollama list | grep -q "qwen2.5:1.5b"; then
        echo -e "${GREEN}Pulling qwen2.5:1.5b model...${NC}"
        ollama pull qwen2.5:1.5b
    fi
fi

# Check if .zshrc exists
if [ ! -f "$HOME/.zshrc" ]; then
    echo -e "${YELLOW}Creating .zshrc file...${NC}"
    touch "$HOME/.zshrc"
fi

# Add to .zshrc if not already present
if ! grep -q "zsh-llm-debugger.plugin.zsh" "$HOME/.zshrc"; then
    echo -e "${GREEN}Adding plugin to .zshrc...${NC}"
    echo "" >> "$HOME/.zshrc"
    echo "# ZSH LLM Debugger" >> "$HOME/.zshrc"
    echo "source $INSTALL_DIR/zsh-llm-debugger.plugin.zsh" >> "$HOME/.zshrc"
else
    echo -e "${YELLOW}Plugin already in .zshrc${NC}"
fi

# OpenAI setup (optional)
echo
echo -e "${YELLOW}=== OpenAI Setup (Optional) ===${NC}"
echo "If you want to use GPT-4o instead of local Ollama models,"
echo "you'll need to set your OpenAI API key:"
echo
echo "export OPENAI_API_KEY='your-api-key-here'"
echo
echo "You can add this to your .zshrc file to make it permanent."
echo

# Final instructions
echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo
echo "To start using zsh-llm-debugger, either:"
echo "  1. Start a new terminal session, or"
echo "  2. Run: source ~/.zshrc"
echo
echo "Usage:"
echo "  ? <command>     - Debug a failed command"
echo "  ?? <description> - Generate a command from natural language"
echo
echo "Examples:"
echo "  ? git push"
echo "  ?? find all Python files modified today"
echo
echo -e "${GREEN}Happy debugging!${NC}"

# Test the installation
echo
echo -e "${YELLOW}Would you like to test the installation? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    # Source the plugin in a new zsh instance and run a test
    echo -e "${GREEN}Testing command generation...${NC}"
    zsh -c "source $INSTALL_DIR/zsh-llm-debugger.plugin.zsh && generate_command 'show current directory'"
fi