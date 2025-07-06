import json
import ollama
import asyncio
import os
import subprocess
import shlex
import shutil
import logging
import sys
import platform
from typing import Any, Dict, List
from datetime import datetime

# Configure logging for verbose output
logging.basicConfig(
    level=logging.DEBUG,  # Set to DEBUG for verbose logging
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("shell_debugger.log")  # Log to a file only
    ]
)

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
        cwd = os.getcwd()
        logging.debug(f"Current working directory: {cwd}")
        return cwd
    except Exception as e:
        logging.exception("Error getting current working directory")
        return f"Error getting current working directory: {str(e)}"

def list_processes(options: List[str] = []) -> str:
    logging.debug(f"Entering list_processes with options: {options}")
    try:
        # Determine the operating system
        system = platform.system()
        logging.debug(f"Operating System detected: {system}")
        if system == "Windows":
            cmd = ['tasklist'] + options
            shell = True
            logging.debug(f"Constructed command for Windows: {' '.join(cmd)}")
        else:
            cmd = ['ps'] + options
            shell = False
            logging.debug(f"Constructed command for Unix: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, shell=shell)
        logging.debug(f"Command output:\n{result.stdout}")
        return result.stdout
    except subprocess.CalledProcessError as e:
        logging.error(f"Error listing processes: {e.stderr}")
        return f"Error listing processes: {e.stderr}"
    except Exception as e:
        logging.exception("Unexpected error in list_processes")
        return f"Unexpected error: {str(e)}"

def display_file_contents(file_path: str) -> str:
    logging.debug(f"Entering display_file_contents with file_path: {file_path}")
    try:
        with open(file_path, 'r') as file:
            contents = file.read()
        logging.debug(f"Contents of {file_path}:\n{contents}")
        return contents
    except FileNotFoundError:
        logging.error(f"File not found: {file_path}")
        return f"File not found: {file_path}"
    except Exception as e:
        logging.exception(f"Error reading file: {file_path}")
        return f"Error reading file: {str(e)}"

def execute_shell_command(command: str, env=os.environ) -> (str, str, int):
    """
    Executes a shell command and captures its output and exit status.
    """
    logging.debug(f"Executing shell command: {command}")
    try:
        result = subprocess.run(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            executable='/bin/zsh',  # Ensure using ZSH
            env=env
        )
        logging.debug(f"Command executed with exit status: {result.returncode}")
        logging.debug(f"STDOUT:\n{result.stdout}")
        logging.debug(f"STDERR:\n{result.stderr}")
        return result.stdout, result.stderr, result.returncode
    except Exception as e:
        logging.exception("Error executing shell command")
        return '', str(e), 1

def gather_error_details_from_files(command: str, output_file: str, timing_file: str = None, capture_method: str = "traditional") -> Dict[str, Any]:
    """
    Gathers detailed error information from script output files.
    """
    logging.debug(f"Gathering error details from files: output={output_file}, timing={timing_file}, method={capture_method}")
    
    try:
        # Read the output file
        script_output = ""
        if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
            with open(output_file, 'r') as f:
                script_output = f.read()
        
        # Read timing information if available
        timing_info = ""
        if timing_file and timing_file != "None" and os.path.exists(timing_file) and os.path.getsize(timing_file) > 0:
            with open(timing_file, 'r') as f:
                timing_info = f.read()
        
        # Default to failure exit status
        exit_status = 1
        
        details = {
            "timestamp": datetime.now().isoformat(),
            "command": command,
            "exit_status": exit_status,
            "stdout": "",  # script combines output
            "stderr": script_output,  # Put everything in stderr since command failed
            "working_directory": os.getcwd(),
            "shell": os.getenv('SHELL', ''),
            "PATH": os.getenv('PATH', ''),
            "system_information": subprocess.getoutput('uname -a') if shutil.which('uname') else "System information not available",
            "os_release": subprocess.getoutput('cat /etc/os-release') if os.path.exists('/etc/os-release') else "OS release information not available",
            "command_binary_details": subprocess.getoutput(f'which {shlex.split(command)[0]}') if shutil.which(shlex.split(command)[0]) else "Command not found in PATH",
            "command_version": subprocess.getoutput(f'{shlex.split(command)[0]} --version') if shutil.which(shlex.split(command)[0]) else "Version information not available",
            "environment_variables": dict(os.environ),
            "timing_info": timing_info,
            "capture_method": capture_method
        }
        
        logging.debug(f"Error details gathered: {details}")
        return details
        
    except Exception as e:
        logging.exception("Error gathering error details from files")
        return {
            "timestamp": datetime.now().isoformat(),
            "command": command,
            "exit_status": 1,
            "stdout": "",
            "stderr": f"Error gathering error details: {str(e)}",
            "capture_method": capture_method,
            "error": f"Error gathering error details: {str(e)}"
        }

def gather_error_details(command: str, exit_status: int, stdout: str, stderr: str) -> Dict[str, Any]:
    """
    Gathers detailed error information, including system and environment details.
    """
    logging.debug("Gathering error details")
    try:
        details = {
            "timestamp": datetime.now().isoformat(),
            "command": command,
            "exit_status": exit_status,
            "stdout": stdout,
            "stderr": stderr,
            "working_directory": os.getcwd(),
            "shell": os.getenv('SHELL', ''),
            "PATH": os.getenv('PATH', ''),
            "system_information": subprocess.getoutput('uname -a') if shutil.which('uname') else "System information not available",
            "os_release": subprocess.getoutput('cat /etc/os-release') if os.path.exists('/etc/os-release') else "OS release information not available",
            "command_binary_details": subprocess.getoutput(f'which {shlex.split(command)[0]}') if shutil.which(shlex.split(command)[0]) else "Command not found in PATH",
            "command_version": subprocess.getoutput(f'{shlex.split(command)[0]} --version') if shutil.which(shlex.split(command)[0]) else "Version information not available",
            "environment_variables": dict(os.environ)
        }
        logging.debug(f"Error details gathered: {details}")
        return details
    except Exception as e:
        logging.exception("Error gathering error details")
        return {
            "timestamp": datetime.now().isoformat(),
            "command": command,
            "exit_status": exit_status,
            "stdout": stdout,
            "stderr": stderr,
            "error": f"Error gathering error details: {str(e)}"
        }

# ALLOWED_FUNCTIONS Dictionary

ALLOWED_FUNCTIONS: Dict[str, Dict[str, Any]] = {
    "list_directory": {
        "name": "list_directory",
        "description": "List files and directories in a specified path.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "The directory path to list."
                },
                "options": {
                    "type": "array",
                    "items": {
                        "type": "string",
                        "enum": ["-la", "--help"]
                    },
                    "description": "Options to modify the behavior of the ls command."
                }
            },
            "required": ["path"]
        }
    },
    "print_working_directory": {
        "name": "print_working_directory",
        "description": "Print the current working directory.",
        "parameters": {
            "type": "object",
            "properties": {}
        }
    },
    "list_processes": {
        "name": "list_processes",
        "description": "List currently running processes.",
        "parameters": {
            "type": "object",
            "properties": {
                "options": {
                    "type": "array",
                    "items": {
                        "type": "string",
                        "enum": ["aux", "--help"]
                    },
                    "description": "Options to modify the behavior of the ps command."
                }
            }
        }
    },
    "display_file_contents": {
        "name": "display_file_contents",
        "description": "Display the contents of a specified file.",
        "parameters": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "The path to the file to display."
                }
            },
            "required": ["file_path"]
        }
    }
}

# Mapping of function names to actual Python functions
AVAILABLE_FUNCTIONS: Dict[str, Any] = {
    "list_directory": list_directory,
    "print_working_directory": print_working_directory,
    "list_processes": list_processes,
    "display_file_contents": display_file_contents,
}

# Helper function to extract command from ```sh code blocks
def extract_command_from_codeblock(content: str) -> str:
    """Extract command from ```sh code blocks, fallback to original content if no blocks found."""
    # Look for ```sh code blocks
    import re
    
    # Pattern to match ```sh\ncommand\n```
    pattern = r'```sh\s*\n(.*?)\n```'
    matches = re.findall(pattern, content, re.DOTALL)
    
    if matches:
        # Return the first command found, stripped of whitespace
        return matches[0].strip()
    
    # Pattern to match just ``` code blocks (fallback)
    pattern = r'```\s*\n(.*?)\n```'
    matches = re.findall(pattern, content, re.DOTALL)
    
    if matches:
        # Return the first command found, stripped of whitespace
        return matches[0].strip()
    
    # If no code blocks found, return original content
    return content.strip()

# Async Function to Interact with the Model

async def generate_command_from_prompt(model: str, prompt: str, stream: bool = False):
    """
    Generate a CLI command from a text prompt using the LLM.
    """
    logging.debug(f"Generating command from prompt: {prompt}, streaming: {stream}")
    
    # Initialize Ollama client
    client = ollama.AsyncClient()
    
    # Define the system prompt for command generation
    system_prompt = {
        'role': 'system',
        'content': (
            "You are an expert CLI command generator. Your task is to generate a single, "
            "executable command based on the user's natural language description. "
            "You may think through the problem first using <think> tags, then provide "
            "the final command wrapped in ```sh code blocks.\n\n"
            "Format your response like this:\n"
            "<think>\nLet me analyze what the user wants...\n</think>\n\n"
            "```sh\ncommand-here\n```\n\n"
            "Examples:\n"
            "User: 'list all files with details'\n"
            "Assistant: <think>\nUser wants to see all files with detailed information like permissions, size, date.\n"
            "The ls command with -la flags will show all files including hidden ones with detailed info.\n"
            "</think>\n\n```sh\nls -la\n```\n\n"
            "User: 'find all python files'\n"
            "Assistant: <think>\n"
            "User wants to locate all Python files. The find command can search for files by name pattern.\n"
            "Using -name '*.py' will match all files ending in .py\n"
            "</think>\n\n```sh\nfind . -name '*.py'\n```\n\n"
            "Focus on common, safe commands. Prefer widely available tools."
        )
    }
    
    # Create the user message
    user_message = {
        'role': 'user',
        'content': prompt
    }
    
    # Initialize conversation
    messages = [system_prompt, user_message]
    
    try:
        logging.debug("Sending API call to generate command")
        
        if stream:
            # Streaming mode - output chunks as they arrive
            collected_content = ""
            in_think_tag = False
            think_content = ""
            final_command = ""
            
            async for chunk in await client.chat(
                model=model,
                messages=messages,
                stream=True
            ):
                if chunk['message']['content']:
                    content = chunk['message']['content']
                    
                    # Process content and handle think tags
                    for char in content:
                        collected_content += char
                        
                        # Check for think tag start
                        if collected_content.endswith('<think>'):
                            in_think_tag = True
                            # Output special marker for think tag start
                            sys.stdout.write('[THINK_START]')
                            sys.stdout.flush()
                            continue
                        
                        if in_think_tag:
                            think_content += char
                            if think_content.endswith('</think>'):
                                # Output special marker for think tag end
                                sys.stdout.write('[THINK_END]')
                                sys.stdout.flush()
                                in_think_tag = False
                                think_content = ""
                                continue
                            else:
                                # Output think content
                                sys.stdout.write(char)
                                sys.stdout.flush()
                        else:
                            # Regular content - stream directly
                            if not collected_content.endswith('<think>'):
                                final_command += char
                                sys.stdout.write(char)
                                sys.stdout.flush()
            
            # Ensure we have a final command
            if not final_command.strip():
                # Extract command from collected content
                final_command = collected_content
                if '<think>' in final_command and '</think>' in final_command:
                    # Extract content after </think>
                    final_command = final_command.split('</think>')[-1].strip()
            
            # Extract command from ```sh code blocks if present
            final_command = extract_command_from_codeblock(final_command)
            logging.debug(f"Generated command (streaming): {final_command}")
            
        else:
            # Non-streaming mode - original behavior
            response = await client.chat(
                model=model,
                messages=messages,
            )
            
            generated_command = response['message']['content'].strip()
            logging.debug(f"Generated command: {generated_command}")
            
            # Clean up the command - remove any extra formatting or thinking tags
            if '<think>' in generated_command:
                # Extract content between </think> and end, or use the last line
                if '</think>' in generated_command:
                    generated_command = generated_command.split('</think>')[-1].strip()
                else:
                    lines = generated_command.split('\n')
                    for line in reversed(lines):
                        line = line.strip()
                        if line and not line.startswith('<') and not line.endswith('>'):
                            generated_command = line
                            break
            
            # Extract command from ```sh code blocks if present
            generated_command = extract_command_from_codeblock(generated_command)
            
            # Print the cleaned command to stdout (will be redirected to result file)
            print(generated_command)
        
    except Exception as e:
        logging.exception("Error generating command")
        # Print error message to stdout
        print(f"Error generating command: {str(e)}")

async def run(model: str, error_details: Dict[str, Any]):
    logging.debug("Starting interaction with the Ollama model")
    client = ollama.AsyncClient()

    # Define the system prompt for shell debugging
    capture_method = error_details.get('capture_method', 'traditional')
    system_prompt = {
        'role': 'system',
        'content': (
            "You are a shell debugger. Analyze the following failed shell command and provide a corrected command. "
            "Respond with the corrected shell command wrapped in ```sh code blocks, or by using a tool provided. "
            "You may not ask clarifying questions. You are expected to use the provided tools to answer the question. "
            f"The command output was captured using: {capture_method} method."
        )
    }

    # Define six multi-turn few-shot examples
    few_shot_examples = [
        # Example 1
        {
            'role': 'user',
            'content': (
                "```sh\ncd /nonexistent_dir\n```\n"
                "Error Output:\n```\nbash: cd: /nonexistent_dir: No such file or directory\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'list_directory',
                        'arguments': {
                            'path': '/',
                            'options': ['-la']
                        }
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "drwxr-xr-x  5 root root  4096 Apr 10 10:00 existing_dir\n..."
        },
        {
            'role': 'assistant',
            'content': "```sh\ncd /existing_dir\n```"
        },

        # Example 2
        {
            'role': 'user',
            'content': (
                "```sh\ngrep 'pattern'\n```\n"
                "Error Output:\n```\ngrep: missing file operand\nTry 'grep --help' for more information.\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'list_directory',
                        'arguments': {
                            'path': '.',
                            'options': ['-la']
                        }
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "file1.txt\nfile2.log\nscript.sh\n"
        },
        {
            'role': 'assistant',
            'content': "```sh\ngrep 'pattern' file1.txt\n```"
        },

        # Example 3
        {
            'role': 'user',
            'content': (
                "```sh\ncat /etc/hostsh\n```\n"
                "Error Output:\n```\nbash: cat: /etc/hostsh: No such file or directory\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'list_directory',
                        'arguments': {
                            'path': '/etc',
                            'options': []
                        }
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "hosts\nhostname\nresolv.conf\n"
        },
        {
            'role': 'assistant',
            'content': "```sh\ncat /etc/hosts\n```"
        },

        # Example 4
        {
            'role': 'user',
            'content': (
                "```sh\npython script.py\n```\n"
                "Error Output:\n```\npython: command not found\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'list_processes',
                        'arguments': {
                            'options': ['aux']
                        }
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND\n..."
        },
        {
            'role': 'assistant',
            'content': "```sh\npython3 script.py\n```"
        },

        # Example 5
        {
            'role': 'user',
            'content': (
                "```sh\nmkdir new_folder\n```\n"
                "Error Output:\n```\nmkdir: cannot create directory 'new_folder': Permission denied\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'print_working_directory',
                        'arguments': {}
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "/home/user/projects"
        },
        {
            'role': 'assistant',
            'content': "```sh\nsudo mkdir new_folder\n```"
        },

        # Example 6
        {
            'role': 'user',
            'content': (
                "```sh\nrm *.txt\n```\n"
                "Error Output:\n```\nrm: missing operand after '*.txt'\nTry 'rm --help' for more information.\n```"
            )
        },
        {
            'role': 'assistant',
            'content': "",
            'tool_calls': [
                {
                    'function': {
                        'name': 'list_directory',
                        'arguments': {
                            'path': '.',
                            'options': ['-la']
                        }
                    }
                }
            ]
        },
        {
            'role': 'tool',
            'content': "file1.txt\nfile2.txt\nREADME.md\n"
        },
        {
            'role': 'assistant',
            'content': "```sh\nrm *.txt\n```"
        },
    ]

    # Construct the user message as per the interaction pattern
    stderr_content = error_details.get('stderr', '')
    if isinstance(stderr_content, list):
        stderr_content = '\n'.join(stderr_content)
    
    user_message = {
        'role': 'user',
        'content': (
            f"```sh\n{error_details['command']}\n```\n"
            f"Error Output:\n```\n{stderr_content}\n```"
        )
    }

    # Initialize conversation with system prompt and few-shot examples
    messages = [system_prompt] + few_shot_examples + [user_message]

    logging.debug("Conversation initialized with system prompt, few-shot examples, and user message")

    # First API call: Send the messages and function descriptions to the model
    try:
        logging.debug("Sending first API call to the model with messages and tools")
        response = await client.chat(
            model=model,
            messages=messages,
            tools=list(ALLOWED_FUNCTIONS.values()),
        )
        logging.debug("Received response from the model")
    except Exception as e:
        logging.exception("Error during the first API call to the model")
        print(f"Error communicating with the model: {str(e)}", file=sys.stderr)
        return

    # Add the model's response to the conversation history
    messages.append(response['message'])

    # Check if the model decided to use any provided function
    if not response['message'].get('tool_calls'):
        logging.debug("The model didn't use any function")
        # Extract command from ```sh code blocks if present
        command_response = extract_command_from_codeblock(response['message']['content'])
        print(command_response)
        return

    # Process function calls made by the model
    if response['message'].get('tool_calls'):
        for tool in response['message']['tool_calls']:
            function_name = tool['function']['name']
            function_args = tool['function']['arguments']
            logging.debug(f"Processing tool call: {function_name} with arguments: {function_args}")

            if function_name in AVAILABLE_FUNCTIONS:
                function_to_call = AVAILABLE_FUNCTIONS[function_name]
                try:
                    if function_name == "list_directory":
                        path = function_args['path']
                        options = function_args.get('options', [])
                        logging.debug(f"Calling list_directory with path: {path}, options: {options}")
                        function_response = function_to_call(path, options)
                    elif function_name == "print_working_directory":
                        logging.debug("Calling print_working_directory")
                        function_response = function_to_call()
                    elif function_name == "list_processes":
                        options = function_args.get('options', [])
                        logging.debug(f"Calling list_processes with options: {options}")
                        function_response = function_to_call(options)
                    elif function_name == "display_file_contents":
                        file_path = function_args['file_path']
                        logging.debug(f"Calling display_file_contents with file_path: {file_path}")
                        function_response = function_to_call(file_path)
                    else:
                        logging.warning(f"Function '{function_name}' is not implemented")
                        function_response = f"Function '{function_name}' is not implemented."
                except Exception as e:
                    logging.exception(f"Error executing function '{function_name}'")
                    function_response = f"Error executing function '{function_name}': {str(e)}"

                # Add function response to the conversation
                messages.append(
                    {
                        'role': 'tool',
                        'content': function_response,
                    }
                )
                logging.debug(f"Function '{function_name}' executed successfully")
            else:
                logging.warning(f"Function '{function_name}' is not allowed")
                function_response = f"Function '{function_name}' is not allowed."
                messages.append(
                    {
                        'role': 'tool',
                        'content': function_response,
                    }
                )

    # Second API call: Get final response from the model
    try:
        logging.debug("Sending second API call to the model with updated messages")
        final_response = await client.chat(model=model, messages=messages)
        logging.debug("Received final response from the model")
        # Extract command from ```sh code blocks if present
        final_command_response = extract_command_from_codeblock(final_response['message']['content'])
        print(final_command_response)
    except Exception as e:
        logging.exception("Error during the second API call to the model")
        print(f"Error communicating with the model: {str(e)}", file=sys.stderr)

# Main Execution Flow

def main():
    logging.debug("Starting main execution flow")

    # Handle different argument patterns
    if len(sys.argv) == 2:
        # Original usage: python script.py <json_file>
        error_details_file = sys.argv[1]
        if not os.path.exists(error_details_file):
            logging.error(f"Error details file not found: {error_details_file}")
            print(f"Error details file not found: {error_details_file}", file=sys.stderr)
            sys.exit(1)

        try:
            with open(error_details_file, 'r') as f:
                error_details = json.loads(f.read())
            logging.debug(f"Loaded error details: {error_details}")
        except json.JSONDecodeError as e:
            logging.exception(f"JSON decoding failed for file: {error_details_file}")
            print(f"JSON decoding failed: {str(e)}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            logging.exception(f"Error reading error details file: {error_details_file}")
            print(f"Error reading error details file: {str(e)}", file=sys.stderr)
            sys.exit(1)

        # Run the async function to interact with the model for debugging
        asyncio.run(run('Qwen3:1.7b', error_details))

    elif len(sys.argv) >= 5:
        # Check if first argument is GENERATE_MODE
        if sys.argv[1] == "GENERATE_MODE":
            # Generate mode: python script.py GENERATE_MODE <prompt_file> <ignored> <ignored> [stream]
            prompt_file = sys.argv[2]
            stream_mode = len(sys.argv) > 5 and sys.argv[5] == "stream"
            
            if not os.path.exists(prompt_file):
                logging.error(f"Prompt file not found: {prompt_file}")
                print(f"Prompt file not found: {prompt_file}", file=sys.stderr)
                sys.exit(1)
            
            try:
                with open(prompt_file, 'r') as f:
                    prompt = f.read().strip()
                logging.debug(f"Loaded prompt: {prompt}")
                
                # Run the async function to generate command
                asyncio.run(generate_command_from_prompt('Qwen3:1.7b', prompt, stream_mode))
                
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
            asyncio.run(run('Qwen3:1.7b', error_details))

    else:
        logging.error("Invalid arguments")
        print("Usage: python ollama_debugger.py <error_details_json_file>")
        print("   or: python ollama_debugger.py <command> <output_file> <timing_file> <capture_method>")
        print("   or: python ollama_debugger.py GENERATE_MODE <prompt_file> <ignored> <ignored> [stream]")
        sys.exit(1)

# Run the main function
if __name__ == "__main__":
    main()
