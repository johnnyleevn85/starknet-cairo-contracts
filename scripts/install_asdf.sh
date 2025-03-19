#!/bin/bash

set -e  # Exit immediately if a command fails
set -o pipefail  # Catch piped command errors
set -u  # Treat unset variables as an error

# Define the ASDF installation directory (Default: $HOME/.asdf)
ASDF_DIR="$HOME/.asdf"

# Clone asdf repository if not already installed
if [ ! -d "$ASDF_DIR" ]; then
    echo "Installing asdf..."
    git clone https://github.com/asdf-vm/asdf.git "$ASDF_DIR" --branch v0.14.0
else
    echo "asdf is already installed at $ASDF_DIR"
fi

# Ensure asdf is sourced in the current shell
echo "Configuring asdf..."
echo ". $ASDF_DIR/asdf.sh" >> ~/.bashrc
echo ". $ASDF_DIR/completions/asdf.bash" >> ~/.bashrc

# Apply changes immediately for CI
source "$ASDF_DIR/asdf.sh"
source "$ASDF_DIR/completions/asdf.bash"

# Verify asdf is available
if command -v asdf >/dev/null; then
    echo "asdf successfully installed and available!"
else
    echo "asdf installation failed!" >&2
    exit 1
fi
