#!/bin/bash

# Save the original directory
original_dir=$(pwd)

# Change to the directory containing the Python script
cd /Users/rioedwards/Documents/Coding/tools/contentful-readme-generator/

# Activate the virtual environment
source /Users/rioedwards/.local/share/virtualenvs/contentful-readme-generator-_WfmV84p/bin/activate

# Run the Python script with the argument passed to the shell script
python main.py --cwd "$original_dir" --proj_id "$1"
deactivate
