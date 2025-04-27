#!/bin/bash

echo "Hello! This is a placeholder for init commands on th host at the beginning of the devcontainer launch process."

# Performing this action in a script instead of directly from the devcontainer.json avoids creating a literal '{.aws,.ssh,...}' directory.
mkdir -p ~/{.aws,.ssh,.azure}
