# zsh-llm-debugger Debug Mode

## Enabling Debug Mode

To enable debug mode and see raw model responses, set the environment variable:

```bash
export LLM_DEBUGGER_DEBUG=1
```

To disable debug mode:

```bash
export LLM_DEBUGGER_DEBUG=0
```

## Debug Log Location

The debug log is saved to: `~/.llm_debugger_zsh.log`

## Debug Functions

### View the last 50 lines of the debug log:
```bash
llm_debugger_show_log
```

### Tail the debug log in real-time:
```bash
llm_debugger_tail_log
```

### Clear the debug log:
```bash
llm_debugger_clear_log
```

## What's Logged

When debug mode is enabled, the following information is logged:

1. Function calls and their arguments
2. Command execution status
3. **Raw model responses** (complete with think tags and markdown)
4. Error messages and exit codes
5. Key variable states

## Example Usage

```bash
# Enable debug mode
export LLM_DEBUGGER_DEBUG=1

# Try a command that will fail
debug_command find all Python files modified today

# View the raw model response
llm_debugger_show_log

# Or tail the log to see updates in real-time
llm_debugger_tail_log
```

## Troubleshooting

If you're not seeing expected output:

1. Make sure debug mode is enabled: `echo $LLM_DEBUGGER_DEBUG` should show `1`
2. Check if the log file exists: `ls -la ~/.llm_debugger_zsh.log`
3. Clear the log and try again: `llm_debugger_clear_log` 