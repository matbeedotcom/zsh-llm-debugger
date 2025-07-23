# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

zsh-llm-debugger is a Zsh plugin that integrates AI-powered debugging assistance directly into the command line. It intercepts failed commands and uses LLMs to analyze errors and suggest corrections in real-time.

## Commands

### Testing
```bash
# Run streaming consistency tests
./test_streaming_consistency.sh

# Interactive streaming demo
./demo_streaming.sh

# Additional streaming tests
./test_streaming_fix.sh
```

### Development
```bash
# Install Python dependencies
pip install -r requirements.txt

# Enable debug logging
export LLM_DEBUGGER_DEBUG=1

# Check logs
tail -f ~/.llm_debugger_zsh.log
tail -f shell_debugger.log  # Ollama backend
tail -f ~/.openai_debugger.log  # OpenAI backend
```

## Architecture

### Core Components

1. **zsh-llm-debugger.plugin.zsh**: Main Zsh plugin handling all shell integration
   - Custom `accept-line` widget to intercept `?` and `??` commands
   - Inline suggestion display using `region_highlight`
   - Streaming output processing with visual indicators
   - Key bindings for accepting/rejecting suggestions

2. **ollama_debugger.py**: Python backend using OpenAI-compatible API
   - Configurable endpoint via LLM_DEBUGGER_BASE_URL (defaults to Ollama)
   - Configurable model via LLM_DEBUGGER_MODEL
   - Works with any OpenAI-compatible endpoint (OpenAI, Anthropic, Ollama, etc.)
   - Implements tool calling (filesystem, process inspection)
   - Streaming output with `<think>` tag handling

3. **openai_debugger.py**: Alternative OpenAI backend
   - Uses GPT-4o with Assistant API
   - Similar tool calling functionality
   - FIFO-based communication with Zsh

### Key Implementation Details

**Streaming Architecture**: Python scripts output character-by-character for real-time display. Special markers `[THINK_START]` and `[THINK_END]` delimit AI reasoning that's hidden from the user.

**Suggestion UI**: Uses Zsh's `region_highlight` array to display gray text suggestions inline. Multiple key bindings (Tab, Right Arrow, End) for accepting suggestions.

**Error Capture**: Uses `script` command for proper TTY behavior when capturing command output, with fallback to standard subprocess capture.

### Important Files and Locations

- Log files: `~/.llm_debugger_zsh.log`, `shell_debugger.log`, `~/.openai_debugger.log`
- Config: `~/.openai_debugger_config.json` (OpenAI API key)
- Temp files: `/tmp/llm_debugger_*`

### Entry Points

- `? <command>`: Debug a command that fails
- `?? <description>`: Generate a command from natural language
- `debug_command` / `generate_command`: Function forms
- `debug_command_openai`: Force OpenAI backend

### Development Notes

- Avoid creating files unless necessary
- Careful handling of Zsh job control to prevent "job table full" errors
- All temporary files must be cleaned up on exit
- Debug mode available via `LLM_DEBUGGER_DEBUG=1`
- Python scripts handle both debugging and generation modes based on arguments