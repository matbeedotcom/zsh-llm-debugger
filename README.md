# ZSH LLM Debugger

An intelligent Zsh plugin that uses AI to debug failed commands and generate shell commands from natural language descriptions. Get instant, context-aware fixes for command-line errors directly in your terminal.

![Demo](https://github.com/acidhax/zsh-llm-debugger/assets/demo.gif)

## Features

- **🔧 Automatic Error Analysis**: Prefix any command with `?` to get AI-powered debugging if it fails
- **💬 Natural Language Commands**: Use `??` to generate shell commands from descriptions
- **⚡ Real-time Streaming**: See AI responses character-by-character as they're generated
- **💭 Inline Suggestions**: Accept or reject fixes with simple keyboard shortcuts
- **🔍 Context-Aware**: AI can inspect files, directories, and processes to provide accurate solutions
- **🚀 Fast Local Inference**: Uses lightweight Ollama models for quick responses
- **🌐 OpenAI Support**: Optional GPT-4o integration for more complex debugging
- **📦 Isolated Environment**: Uses a Python virtual environment to avoid conflicts

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/acidhax/zsh-llm-debugger.git
cd zsh-llm-debugger

# Run the install script
./install.sh
```

### Manual Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/acidhax/zsh-llm-debugger.git ~/.zsh-llm-debugger
   ```

2. **Install Python dependencies** (the install script creates a virtual environment):
   ```bash
   cd ~/.zsh-llm-debugger
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   deactivate
   ```

3. **Install Ollama** (for local inference):
   ```bash
   # macOS/Linux
   curl -fsSL https://ollama.com/install.sh | sh
   
   # Pull the model
   ollama pull qwen2.5:1.5b
   ```

4. **Add to your `.zshrc`**:
   ```bash
   source ~/.zsh-llm-debugger/zsh-llm-debugger.plugin.zsh
   ```

5. **Reload your shell**:
   ```bash
   source ~/.zshrc
   ```

### OpenAI Setup (Optional)

To use GPT-4o instead of local models:

```bash
export OPENAI_API_KEY="your-api-key-here"
```

## Usage

### Debug Failed Commands

Prefix any command with `?` to automatically analyze errors:

```bash
? git push
# If the push fails, AI will analyze the error and suggest a fix
```

### Generate Commands

Use `??` to create commands from natural language:

```bash
?? find all Python files modified in the last week
# Generates: find . -name "*.py" -mtime -7
```

### Keyboard Shortcuts

When a suggestion appears:
- **Tab** / **→** / **End**: Accept the suggestion
- **Esc** / **←**: Reject and keep original command
- **Ctrl+C**: Cancel everything

### Function Interface

You can also use the functions directly:

```bash
# Debug a command
debug_command "git push origin main"

# Generate a command
generate_command "list all docker containers with their sizes"

# Force OpenAI backend
debug_command_openai "npm install"
```

## Configuration

### Environment Variables

```bash
# Enable debug logging
export LLM_DEBUGGER_DEBUG=1

# Set OpenAI API key (optional)
export OPENAI_API_KEY="sk-..."

# Change the Ollama model (default: qwen2.5:1.5b)
export OLLAMA_MODEL="llama3.2:3b"
```

### Log Files

- Zsh plugin log: `~/.llm_debugger_zsh.log`
- Ollama backend log: `shell_debugger.log`
- OpenAI backend log: `~/.openai_debugger.log`

## How It Works

1. **Command Interception**: The plugin overrides Zsh's `accept-line` widget to catch `?` and `??` prefixes
2. **Error Capture**: Failed commands are executed with full terminal context captured
3. **AI Analysis**: The error output, environment, and context are sent to the AI model
4. **Tool Usage**: AI can inspect files, directories, and processes to understand the issue
5. **Suggestion Display**: Fixes appear inline as gray text, similar to zsh-autosuggestions
6. **Easy Application**: Accept suggestions with Tab to execute the fixed command

## Examples

### Git Errors
```bash
? git push
# Error: failed to push some refs to 'origin'
# AI suggests: git pull --rebase origin main && git push
```

### Permission Issues
```bash
? npm install -g typescript
# Error: EACCES: permission denied
# AI suggests: sudo npm install -g typescript
```

### File Not Found
```bash
? python script.py
# Error: No such file or directory
# AI suggests: python3 scripts/script.py
```

### Complex Commands
```bash
?? compress all images in current directory to 50% quality
# Generates: for img in *.{jpg,jpeg,png}; do convert "$img" -quality 50 "compressed_$img"; done
```

## Troubleshooting

### "Command not found: ollama"
Install Ollama following the installation instructions above.

### No suggestions appearing
1. Check if the Python script is executable: `chmod +x ~/.zsh-llm-debugger/*.py`
2. Enable debug mode: `export LLM_DEBUGGER_DEBUG=1`
3. Check logs: `tail -f ~/.llm_debugger_zsh.log`

### Slow responses
- Ensure Ollama is using GPU acceleration: `ollama list`
- Try a smaller model: `export OLLAMA_MODEL="qwen2.5:0.5b"`
- Use OpenAI for faster responses (requires API key)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

Created by [acidhax](https://github.com/acidhax)

Inspired by the need for intelligent command-line assistance and the amazing capabilities of modern LLMs.