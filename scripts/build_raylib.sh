#!/usr/bin/env bash
set -euo pipefail

# Resolve the repository root from this script's location.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

THIRD_PARTY="$REPO/third_party"
RAYLIB_DIR="$THIRD_PARTY/raylib"
RAYLIB_SRC="$RAYLIB_DIR/src"

mkdir -p "$THIRD_PARTY"

# Clone raylib if it doesn't exist yet.
if [[ ! -d "$RAYLIB_DIR/.git" ]]; then
    if [[ -e "$RAYLIB_DIR" ]]; then
        echo "Error: $RAYLIB_DIR exists but is not a Git repository." >&2
        exit 1
    fi

    echo "Cloning raylib..."
    git clone --depth 1 https://github.com/raysan5/raylib.git "$RAYLIB_DIR"
else
    echo "Using existing raylib checkout."
fi

# Build raylib.
echo "Building raylib..."
make -C "$RAYLIB_SRC" clean
make -C "$RAYLIB_SRC" PLATFORM=PLATFORM_DESKTOP

# Copy build artifacts into the locations expected by build.zig.
echo "Installing raylib artifacts..."

mkdir -p "$RAYLIB_DIR/lib" "$RAYLIB_DIR/include"

cp "$RAYLIB_SRC/libraylib.a" "$RAYLIB_DIR/lib/"
cp "$RAYLIB_SRC"/*.h "$RAYLIB_DIR/include/"

echo "raylib build completed successfully."
echo "Library: $RAYLIB_DIR/lib/libraylib.a"
echo "Headers: $RAYLIB_DIR/include/"
