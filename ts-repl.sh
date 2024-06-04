#!/bin/bash
# 1. No arguments: Creates a repl in the terminal
# 2. (open) Open special ts-node playground file in a new VS Code window
# 3. (.) Current file path: Execute ts-node on index.ts file with nodemon
# 4. (<filename>.ts) Current file: Execute ts-node on the specified file with nodemon

playground_dir="$HOME/Documents/Coding/Sandbox/Repl/tsRepl/index.ts"

# Help Function
function show_help() {
    echo "Usage: ts-repl [OPTION] [FILE]"
    echo ""
    echo "Options:"
    echo "  --help     Display this help message"
    echo "  open       Open ts-repl playground in VS Code"
    echo "  .          Run ts-repl on index.ts in the current directory"
    echo "  <file>.ts  Run ts-repl on the specified TypeScript file"
}


if [[ "$1" == "--help" ]]; then
    show_help
    exit 0  # Exit successfully after showing help
elif [ -z "$1" ]; then
    # Create REPL in the terminal
    echo "Starting ts-repl in terminal"
    ts-node
elif [ "$1" == "open" ]; then
    # Open playground in VS Code
    echo "Opening ts-repl playground"
    code $playground_dir
elif [[ "$1" == "." ]]; then
    # Run ts-repl on index.ts in current directory
    if [[ ! -f "index.ts" ]]; then
        echo "Error: index.ts not found in $(pwd)"
        exit 1  # Exit with an error
    fi
    echo "Running ts-repl on index.ts in $(pwd)"
    nodemon -q --exec ts-node index.ts
elif [[ -f "$1" && "$1" == *.ts ]]; then
    echo "Running ts-repl on $(pwd)/$1"
    nodemon -q --exec ts-node $(pwd)/$1
else
    echo "Invalid argument"
     exit 1
fi

