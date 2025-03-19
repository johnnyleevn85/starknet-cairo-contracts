#!/bin/bash
pushd $(dirname $0)/..

set -e  # Exit immediately if a command fails

# Define the ASDF installation directory (Default: $HOME/.asdf)
ASDF_DIR="$HOME/.asdf"

# Clone asdf repository if not already installed
if [ ! -d "$ASDF_DIR" ]; then
    echo "Installing asdf..."
    git clone https://github.com/asdf-vm/asdf.git "$ASDF_DIR" --branch v0.14.0
else
    echo "asdf is already installed at $ASDF_DIR"
fi

export PATH="$ASDF_DIR/bin:$PATH"
export ASDF_DIR="$ASDF_DIR"
source "$ASDF_DIR/asdf.sh"
source "$ASDF_DIR/completions/asdf.bash"

# Verify asdf is available
if command -v asdf >/dev/null; then
    echo "asdf successfully installed and available!"
else
    echo "asdf installation failed!" >&2
    exit 1
fi

popd
