# Think Tags Implementation

## Overview
The zsh-llm-debugger now displays beautiful, boxed UI for LLM thinking process using `<think>` tags. This provides users with insight into the LLM's reasoning before it suggests a command fix or generates a new command.

## What Changed

### Python Script (ollama_debugger.py)
1. **Updated System Prompts**: Both debug mode and generate mode now instruct the LLM to wrap its reasoning in `<think>` tags before providing the command.
2. **Streaming Output**: The script streams the full response including think tags to the Zsh plugin for real-time parsing and display.

### Zsh Plugin (zsh-llm-debugger.plugin.zsh)
1. **Beautiful Boxed UI**: Think tags are rendered in a cyan-colored box with the thinking emoji (💭)
2. **Real-time Streaming**: The plugin parses the streaming output character by character to detect think tags and display them progressively
3. **Word Wrapping**: Long lines in the thinking process are automatically wrapped to fit within the box
4. **Consistent Experience**: Both `?` (debug) and `??` (generate) modes now have the same beautiful UI

## How It Works

### For Debug Mode (? command)
```bash
? ls /nonexistent
```
Displays:
```
╭─ 💭 Analyzing Error ───────────────────────╮
│ Examining the error output...               │
│ The error shows that /nonexistent doesn't   │
│ exist. Let me check the current directory...│
│ The solution is to list an existing path... │
╰────────────────────────────────────────────╯

▶ Suggested fix: ls .
```

### For Generate Mode (?? command)
```bash
?? list all python files recursively
```
Displays:
```
╭─ 💭 Thinking ──────────────────────────────╮
│ Analyzing your request...                   │
│ You want to find Python files recursively. │
│ The best tool for this is the find command │
│ with the -name option for .py extension... │
╰────────────────────────────────────────────╯

▶ Generating command: find . -name "*.py"
```

### For debug_command Function
```bash
debug_command find /invalid -name '*.txt'
```
Shows the same beautiful boxed UI as the `?` mode.

## Technical Details

### Streaming Parse Logic
The Zsh plugin monitors the Python script's output stream and:
1. Detects `<think>` opening tags to start capturing thinking content
2. Captures all content until `</think>` closing tag
3. Displays the content line-by-line with proper formatting
4. Extracts the final command after the think section

### Box Drawing
- Uses Unicode box-drawing characters (╭ ─ ╮ │ ╰ ╯)
- Cyan color (ANSI code 36) for the box
- Gray color (ANSI code 90) for the thinking content
- Automatic width calculation (max 80 chars or terminal width - 4)

### Fallback Behavior
If the LLM doesn't include think tags (older models), the plugin shows a generic thinking message and still extracts the command properly.

## Benefits
1. **Transparency**: Users can see the LLM's reasoning process
2. **Trust**: Understanding why a command is suggested builds confidence
3. **Learning**: Users can learn from the LLM's problem-solving approach
4. **Consistency**: Same beautiful UI across all modes of operation

## Updates and Fixes

### Streaming Timing Fix (Latest)
Fixed an issue where the thinking box would display generic messages ("Analyzing your request...") before the actual think content arrived from the LLM. The plugin now:

1. Shows "Generating command..." initially while waiting for the stream
2. Only creates the thinking box when it detects the actual `<think>` tag
3. Displays thinking content progressively as it streams in
4. Falls back to generic messages only if substantial content (>500 bytes) arrives without think tags

This ensures users see the actual LLM reasoning instead of placeholder text.

### Duplicate Content Fix
Fixed an issue where the LLM would output duplicate think content, causing multiple thinking boxes to appear. The plugin now:

1. Tracks whether a thinking box has already been created with `think_box_started` flag
2. Only displays content updates if they differ significantly from what's already shown
3. Updates content in-place by clearing previous lines before redrawing
4. Suppresses background job control messages by wrapping commands in `{ }` blocks
5. Uses proper state tracking (`think_displayed=2`) to ensure the box is only closed once

This provides a clean, single thinking box that updates smoothly as content streams in. 