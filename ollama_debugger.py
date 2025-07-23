import json
import asyncio
import os
import subprocess
import shlex
import shutil
import logging
import sys
import platform
from typing import Any, Dict, List, Optional
from datetime import datetime
from openai import OpenAI

# Configure logging for verbose output
logging.basicConfig(
    level=logging.DEBUG,  # Set to DEBUG for verbose logging
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("shell_debugger.log")  # Log to a file only
    ]
)

# Configuration for OpenAI-compatible endpoint
# Default to Ollama's OpenAI-compatible endpoint
BASE_URL = os.getenv('LLM_DEBUGGER_BASE_URL', 'http://localhost:11434/v1')
API_KEY = os.getenv('LLM_DEBUGGER_API_KEY', 'ollama')  # Ollama doesn't require a real key
MODEL = os.getenv('LLM_DEBUGGER_MODEL', 'qwen2.5:1.5b')

# Initialize OpenAI client with custom base URL
client = OpenAI(
    base_url=BASE_URL,
    api_key=API_KEY
)

logging.info(f"Using OpenAI-compatible endpoint: {BASE_URL}")
logging.info(f"Using model: {MODEL}")

# Function Definitions

def list_directory(path: str, options: List[str] = []) -> str:
    logging.debug(f"Entering list_directory with path: {path}, options: {options}")
    try:
        # Determine the operating system
        system = platform.system()
        logging.debug(f"Operating System detected: {system}")
        if system == "Windows":
            cmd = ['dir', path] + options
            shell = True
            logging.debug(f"Constructed command for Windows: {' '.join(cmd)}")
        else:
            cmd = ['ls', path] + options
            shell = False
            logging.debug(f"Constructed command for Unix: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, shell=shell)
        logging.debug(f"Command output:\n{result.stdout}")
        return result.stdout
    except subprocess.CalledProcessError as e:
        logging.error(f"Error listing directory: {e.stderr}")
        return f"Error listing directory: {e.stderr}"
    except Exception as e:
        logging.exception("Unexpected error in list_directory")
        return f"Unexpected error: {str(e)}"

def print_working_directory() -> str:
    logging.debug("Entering print_working_directory")
    try:
        pwd = os.getcwd()
        logging.debug(f"Current working directory: {pwd}")
        return pwd
    except Exception as e:
        logging.exception("Unexpected error in print_working_directory")
        return f"Unexpected error: {str(e)}"

def list_processes(filter: str = None) -> str:
    logging.debug(f"Entering list_processes with filter: {filter}")
    try:
        # Determine the operating system
        system = platform.system()
        logging.debug(f"Operating System detected: {system}")
        if system == "Windows":
            cmd = ['tasklist']
            shell = True
            logging.debug(f"Constructed command for Windows: {' '.join(cmd)}")
        else:
            cmd = ['ps', 'aux']
            shell = False
            logging.debug(f"Constructed command for Unix: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, shell=shell)
        output = result.stdout
        if filter:
            lines = output.splitlines()
            filtered_lines = [line for line in lines if filter.lower() in line.lower()]
            output = '\n'.join(filtered_lines)
            logging.debug(f"Filtered output (filter: {filter}):\n{output}")
        else:
            logging.debug(f"Full process list:\n{output}")
        return output
    except subprocess.CalledProcessError as e:
        logging.error(f"Error listing processes: {e.stderr}")
        return f"Error listing processes: {e.stderr}"
    except Exception as e:
        logging.exception("Unexpected error in list_processes")
        return f"Unexpected error: {str(e)}"

def display_file_contents(file_path: str, start_line: int = None, end_line: int = None) -> str:
    logging.debug(f"Entering display_file_contents with file_path: {file_path}, start_line: {start_line}, end_line: {end_line}")
    try:
        with open(file_path, 'r') as file:
            lines = file.readlines()
            total_lines = len(lines)
            logging.debug(f"Total lines in file: {total_lines}")
            if start_line is None:
                start_line = 1
            if end_line is None:
                end_line = total_lines
            # Adjust for 0-indexed list
            start_line = max(1, start_line)
            end_line = min(total_lines, end_line)
            content = ''.join(lines[start_line-1:end_line])
            logging.debug(f"Displaying lines {start_line} to {end_line}")
            return content
    except FileNotFoundError:
        logging.error(f"File not found: {file_path}")
        return f"Error: File not found: {file_path}"
    except Exception as e:
        logging.exception("Unexpected error in display_file_contents")
        return f"Unexpected error: {str(e)}"

# Tool definitions for OpenAI function calling
tools = [
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List the contents of a directory",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "The path to the directory"
                    },
                    "options": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional flags like '-la' for detailed listing"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "print_working_directory",
            "description": "Print the current working directory",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "list_processes",
            "description": "List running processes",
            "parameters": {
                "type": "object",
                "properties": {
                    "filter": {
                        "type": "string",
                        "description": "Optional filter to search for specific processes"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "display_file_contents",
            "description": "Display the contents of a file",
            "parameters": {
                "type": "object",
                "properties": {
                    "file_path": {
                        "type": "string",
                        "description": "The path to the file"
                    },
                    "start_line": {
                        "type": "integer",
                        "description": "The starting line number (1-indexed)"
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "The ending line number (inclusive)"
                    }
                },
                "required": ["file_path"]
            }
        }
    }
]

def execute_function(function_name: str, arguments: dict) -> str:
    """Execute a function based on the function name and arguments"""
    logging.debug(f"Executing function: {function_name} with arguments: {arguments}")
    
    if function_name == "list_directory":
        return list_directory(arguments["path"], arguments.get("options", []))
    elif function_name == "print_working_directory":
        return print_working_directory()
    elif function_name == "list_processes":
        return list_processes(arguments.get("filter"))
    elif function_name == "display_file_contents":
        return display_file_contents(
            arguments["file_path"],
            arguments.get("start_line"),
            arguments.get("end_line")
        )
    else:
        return f"Unknown function: {function_name}"

async def run(model: str, error_details: Dict[str, Any]):
    """Run the debugging assistant using OpenAI-compatible API"""
    logging.debug("=== Starting debugging assistant ===")
    
    # System prompt
    system_prompt = f"""You are an expert command-line debugger assistant specialized in diagnosing and fixing shell command errors.

CRITICAL INSTRUCTION: You must analyze the error and provide ONLY the corrected command that will work. No explanations, no alternatives, just the single working command.

You have access to these tools to help diagnose issues:
- list_directory: List directory contents
- print_working_directory: Get current directory
- list_processes: List running processes
- display_file_contents: Read file contents

Current system information:
- Platform: {platform.system()} {platform.release()}
- Python: {sys.version.split()[0]}
- Shell: {os.environ.get('SHELL', 'unknown')}

Error context provided by user:
{json.dumps(error_details, indent=2)}

Remember: Output ONLY the corrected command, nothing else."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"Fix this command: {error_details['command']}"}
    ]
    
    # Allow up to 5 iterations for tool use
    for i in range(5):
        try:
            # Create chat completion with tools
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                tools=tools,
                tool_choice="auto",
                temperature=0.1,
                stream=True
            )
            
            # Process streaming response
            full_content = ""
            tool_calls = []
            current_tool_call = None
            
            for chunk in response:
                if chunk.choices[0].delta.content:
                    content = chunk.choices[0].delta.content
                    full_content += content
                    # Print each character as it arrives for streaming effect
                    print(content, end='', flush=True)
                
                # Handle tool calls
                if chunk.choices[0].delta.tool_calls:
                    for tool_call_chunk in chunk.choices[0].delta.tool_calls:
                        if tool_call_chunk.id:
                            # New tool call
                            if current_tool_call:
                                tool_calls.append(current_tool_call)
                            current_tool_call = {
                                "id": tool_call_chunk.id,
                                "type": "function",
                                "function": {
                                    "name": tool_call_chunk.function.name if tool_call_chunk.function.name else "",
                                    "arguments": tool_call_chunk.function.arguments if tool_call_chunk.function.arguments else ""
                                }
                            }
                        else:
                            # Continuing current tool call
                            if current_tool_call and tool_call_chunk.function:
                                if tool_call_chunk.function.name:
                                    current_tool_call["function"]["name"] += tool_call_chunk.function.name
                                if tool_call_chunk.function.arguments:
                                    current_tool_call["function"]["arguments"] += tool_call_chunk.function.arguments
            
            # Add final tool call if exists
            if current_tool_call:
                tool_calls.append(current_tool_call)
            
            # Add assistant's response to messages
            assistant_message = {"role": "assistant", "content": full_content}
            if tool_calls:
                assistant_message["tool_calls"] = tool_calls
            messages.append(assistant_message)
            
            # If there are tool calls, execute them
            if tool_calls:
                logging.debug(f"Executing {len(tool_calls)} tool calls")
                for tool_call in tool_calls:
                    function_name = tool_call["function"]["name"]
                    try:
                        arguments = json.loads(tool_call["function"]["arguments"])
                    except json.JSONDecodeError:
                        arguments = {}
                    
                    # Execute the function
                    result = execute_function(function_name, arguments)
                    
                    # Add tool response to messages
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call["id"],
                        "content": result
                    })
                
                # Continue the loop to get the next response
                continue
            else:
                # No tool calls, we're done
                if full_content:
                    print()  # Add newline after streaming
                break
                
        except Exception as e:
            logging.exception("Error in API call")
            print(f"cd {error_details.get('pwd', '.')}", flush=True)
            break

def extract_command_from_markdown(text: str) -> str:
    """Extract command from markdown code blocks, removing think tags"""
    import re
    logging.debug("Extracting command from markdown", text)
    # First, remove <think> tags and their content
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
    
    # Look for code blocks with bash/sh/zsh/shell language identifiers
    code_block_pattern = r'```(?:bash|sh|zsh|shell)\s*\n(.*?)\n```'
    matches = re.findall(code_block_pattern, text, re.DOTALL)
    
    if matches:
        # Return the first code block found
        return matches[0].strip()
    
    # If no code blocks found, look for any code blocks
    generic_pattern = r'```\s*\n(.*?)\n```'
    matches = re.findall(generic_pattern, text, re.DOTALL)
    
    if matches:
        return matches[0].strip()
    
    # If still no code blocks, return the original text stripped
    return text.strip()

async def generate_command_from_prompt(model: str, prompt: str, stream_mode: bool = False):
    """Generate a command from a natural language prompt"""
    logging.debug(f"=== Starting command generation (stream_mode={stream_mode}) ===")
    logging.debug(f"Prompt: {prompt}")
    
    # System prompt for command generation
    system_prompt = """You are a helpful command-line assistant that generates shell commands from natural language descriptions.

Your response should follow this exact format:
1. Start with your reasoning wrapped in <think> tags
2. Then provide the command in a markdown code block

Example response format:
<think>
[Your step-by-step reasoning here]
</think>

```bash
[Your command here]
```

Current system information:
- Platform: """ + platform.system() + " " + platform.release() + """
- Shell: """ + os.environ.get('SHELL', 'unknown') + """
- Current directory: """ + os.getcwd() + """

IMPORTANT: You MUST include the <think> section before the command. Think about:
- What the user is trying to accomplish
- Which commands and options to use
- Any potential issues or considerations"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": prompt}
    ]
    
    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=0.3,
            stream=True,
        )
        
        full_response = ""
        for chunk in response:
            if chunk.choices[0].delta.content:
                content = chunk.choices[0].delta.content
                full_response += content
                if stream_mode:
                    # In stream mode, print each character as it arrives
                    # The Zsh plugin will handle parsing and display
                    print(content, end='', flush=True)
        
        if stream_mode:
            # Ensure we end with a newline
            if not full_response.endswith('\n'):
                print(flush=True)
        else:
            # Non-stream mode: extract and print just the command
            command = extract_command_from_markdown(full_response)
            print(command, flush=True)
            
    except Exception as e:
        logging.exception("Error generating command")
        print("echo 'Error generating command'", flush=True)

def gather_error_details_from_files(command: str, output_file: str, timing_file: str, capture_method: str) -> Dict[str, Any]:
    """Gather error details from the provided files"""
    logging.debug(f"Gathering error details from files: command={command}, output_file={output_file}, timing_file={timing_file}, capture_method={capture_method}")
    
    error_details = {
        "command": command,
        "pwd": os.getcwd(),
        "timestamp": datetime.now().isoformat(),
        "env": dict(os.environ),
        "system_info": {
            "platform": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
            "processor": platform.processor(),
        },
        "capture_method": capture_method
    }
    
    # Read the output file
    try:
        with open(output_file, 'r') as f:
            output_content = f.read()
            # Try to parse as JSON first (for script capture method)
            if capture_method == "script":
                try:
                    output_data = json.loads(output_content)
                    error_details["output"] = output_data.get("output", "")
                    error_details["exit_code"] = output_data.get("exit_code", 1)
                    error_details["error"] = output_data.get("error", "")
                except json.JSONDecodeError:
                    # Fallback to raw content
                    error_details["output"] = output_content
                    error_details["exit_code"] = 1
            else:
                error_details["output"] = output_content
                error_details["exit_code"] = 1
    except Exception as e:
        logging.error(f"Error reading output file: {e}")
        error_details["output"] = f"Error reading output file: {str(e)}"
        error_details["exit_code"] = 1
    
    # Read timing file if provided
    if timing_file and timing_file != "None":
        try:
            with open(timing_file, 'r') as f:
                error_details["timing"] = f.read()
        except Exception as e:
            logging.error(f"Error reading timing file: {e}")
    
    # Add PATH information
    error_details["path"] = os.environ.get("PATH", "").split(os.pathsep)
    
    # Check if common commands exist
    common_commands = ["git", "npm", "python", "python3", "node", "docker", "kubectl"]
    error_details["available_commands"] = {}
    for cmd in common_commands:
        error_details["available_commands"][cmd] = shutil.which(cmd) is not None
    
    return error_details

# Main async function
if __name__ == "__main__":
    logging.debug("=== Script started ===")
    logging.debug(f"Arguments: {sys.argv}")
    
    if len(sys.argv) == 2:
        # Single argument mode - JSON file with error details
        error_details_file = sys.argv[1]
        logging.debug(f"Reading error details from file: {error_details_file}")
        try:
            with open(error_details_file, 'r') as f:
                content = f.read()
                logging.debug(f"File content: {content[:200]}...")  # Log first 200 chars
                error_details = json.loads(content)
                logging.debug(f"Parsed error details: {error_details}")
        except json.JSONDecodeError as e:
            logging.error(f"JSON decoding failed: {str(e)}")
            logging.error(f"File content that failed to parse: {content}")
            print(f"JSON decoding failed: {str(e)}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            logging.exception(f"Error reading error details file: {error_details_file}")
            print(f"Error reading error details file: {str(e)}", file=sys.stderr)
            sys.exit(1)

        # Run the async function to interact with the model for debugging
        asyncio.run(run(MODEL, error_details))

    elif len(sys.argv) >= 5:
        # Check if first argument is GENERATE_MODE
        if sys.argv[1] == "GENERATE_MODE":
            # Generate mode: python script.py GENERATE_MODE <prompt_file> <ignored> <ignored> [stream]
            prompt_file = sys.argv[2]
            stream_mode = len(sys.argv) > 5 and sys.argv[5] == "stream"
            
            if not os.path.exists(prompt_file):
                logging.error(f"Prompt file not found: {prompt_file}")
                print(f"Error: Prompt file not found: {prompt_file}", file=sys.stderr)
                sys.exit(1)
            
            try:
                with open(prompt_file, 'r') as f:
                    prompt = f.read().strip()
                logging.debug(f"Loaded prompt: {prompt}")
                
                # Run the async function to generate command
                asyncio.run(generate_command_from_prompt(MODEL, prompt, stream_mode))
                
            except Exception as e:
                logging.exception(f"Error reading prompt file: {prompt_file}")
                print(f"Error reading prompt file: {str(e)}", file=sys.stderr)
                sys.exit(1)
        else:
            # Debug mode: python script.py <command> <output_file> <timing_file> <capture_method>
            command = sys.argv[1]
            output_file = sys.argv[2]
            timing_file = sys.argv[3] if sys.argv[3] != "None" else None
            capture_method = sys.argv[4]
            
            error_details = gather_error_details_from_files(command, output_file, timing_file, capture_method)
            logging.debug(f"Generated error details: {error_details}")
            
            # Run the async function to interact with the model for debugging
            asyncio.run(run(MODEL, error_details))

    else:
        logging.error("Invalid arguments")
        print("Usage: python ollama_debugger.py <error_details_json_file>")
        print("   or: python ollama_debugger.py <command> <output_file> <timing_file> <capture_method>")
        print("   or: python ollama_debugger.py GENERATE_MODE <prompt_file> <ignored> <ignored> [stream]")
        sys.exit(1)