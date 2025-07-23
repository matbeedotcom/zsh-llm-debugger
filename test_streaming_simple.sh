#!/bin/bash

echo "=== Simple Streaming Test ==="
echo

# Create test content that mimics Python output
cat > /tmp/test_stream.txt << 'EOF'
<think>
This is line 1 of thinking content.
This is line 2 with more reasoning.
Here's line 3 explaining the approach.
</think>

```bash
ls -la
```
EOF

echo "Test content created in /tmp/test_stream.txt"
echo
echo "To test in zsh:"
echo "1. source zsh-llm-debugger.plugin.zsh"
echo "2. Run this command to simulate streaming:"
echo "   cat /tmp/test_stream.txt | while IFS= read -r line; do echo \"\$line\"; sleep 0.1; done"
echo
echo "Expected output:"
echo "- Thinking box with 3 lines of content"
echo "- Command: ls -la" 