#!/bin/bash

# Enable nullglob
shopt -s nullglob

# Define the directory with AIF files
aif_dir="/Users/rioedwards/Documents/music_(aif_&_aiff)"

# Define the directory to clean up
music_dir="/Users/rioedwards/Documents/Music"

# For each AIFF and AIF file in the AIF directory
for aif_file in "$aif_dir"/*.{aif,aiff}; do
    # Extract the base name (without extension)
    base_name=$(basename "$aif_file" .aiff)
    base_name=$(basename "$base_name" .aif)

    # For each non-AIFF/AIF file in the music directory with the same base name
    for file in "$music_dir"/"$base_name".*; do
        # Exclude AIFF and AIF files, and ensure the file exists before attempting to delete
        if [[ "$file" != *.aiff && "$file" != *.aif && -e "$file" ]]; then
            # Get only the file name
            file_name=$(basename "$file")

            # Ask for confirmation before deleting the non-AIFF/AIF file
            echo "Deleting $file_name"
            rm "$file"
        fi
    done
done
