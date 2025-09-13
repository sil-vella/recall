#!/bin/bash

# Build script for Recall Game Rust library

echo "Building Recall Game Rust library..."

# Check if cargo is installed
if ! command -v cargo &> /dev/null; then
    echo "Error: Cargo is not installed. Please install Rust first."
    echo "Visit: https://rustup.rs/"
    exit 1
fi

# Build the library
echo "Compiling Rust library..."
cargo build --release

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "✅ Rust library built successfully!"
    echo "Library location: target/release/"
    
    # List the generated library files
    echo "Generated files:"
    ls -la target/release/librecall_game.* 2>/dev/null || echo "No library files found"
    
    # Copy to expected locations for Python bridge
    echo "Copying library to expected locations..."
    
    # Copy to current directory
    cp target/release/librecall_game.* . 2>/dev/null || true
    
    # Copy to parent directories
    cp target/release/librecall_game.* ../ 2>/dev/null || true
    cp target/release/librecall_game.* ../../ 2>/dev/null || true
    
    echo "✅ Library copied to expected locations"
else
    echo "❌ Build failed!"
    exit 1
fi
