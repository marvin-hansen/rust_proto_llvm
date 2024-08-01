#!/bin/bash
set -eu

# Function to update the version of a given library
update_version() {
    name="$1"
    version="$2"
    # check if valid name or contains spaces
    if [[ "$name" == *" "* ]]; then
        echo "Invalid library name: $name"
        return
    fi
    # Special handling for the "torch" library to ensure proper installation
    if [ "$name" == "torch" ]; then
        name="-f https://download.pytorch.org/whl/torch_stable.html\ntorch"
        version="$version+cpu"
    fi
    # Loop through existing library names to update the version if it exists
    for i in "${!library_names[@]}"; do
        if [ "${library_names[$i]}" = "$name" ]; then
            if [ "$(printf '%s\n' "$version" "${library_versions[$i]}")" = "$version" ]; then
                library_versions[$i]="$version"
            fi
            return
        fi
    done
    # If the library name does not exist, add it to the list
    library_names+=("$name")
    library_versions+=("$version")
}

# Initialize empty arrays for library names and versions
library_names=()
library_versions=()

# The first argument is the output file path
output_file="$1"
# Shift the arguments so we can iterate over the remaining ones as file paths
shift

# DEBT: this might pick up invalid library names (such as OS version) [LIN:MED-641]
# Iterate over each file path provided as an argument
for path in "$@"; do
    # Continue to the next file if the current file does not exist
    if [ ! -f "$path" ]; then
        continue
    fi
    name=""
    version=""
    # Read each line of the file
    while IFS= read -r line; do
        case $line in
        Name:*)
            # Extract the name, removing any carriage return or newline characters
            name="${line#Name: }"
            name="$(echo "$name" | tr -d '\r' | tr -d '\n')"
            ;;
        Version:*)
            # Extract the version, removing any carriage return or newline characters
            version="${line#Version: }"
            version="$(echo "$version" | tr -d '\r' | tr -d '\n')"
            ;;
        esac
        # If both name and version are set, update the version for this library
        if [ -n "$name" ] && [ -n "$version" ]; then
            update_version "$name" "$version"
            name=""
            version=""
        fi
    done <"$path"
done

# Create or overwrite the output file
touch "$output_file"
{
    # Write each library name and version to the output file
    for i in "${!library_names[@]}"; do
        echo "${library_names[$i]}==${library_versions[$i]}"
    done
} >"$output_file"
