#!/bin/bash

# Define the directory to clean up
dir="/Users/rioedwards/Desktop/music-test"

echo "Cleaning up $dir"

# For each non-AIF file in the directory
for file in $(find "$dir" -type f ! -name '*.aif'); do
    # If there exists a file with the same name but with an .aif extension
    if [ -e "${file%.*}.aif" ]; then
        # Then delete the non-AIF file
        echo "Deleting $file"
        rm -i "$file"
    fi
done
