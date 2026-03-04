#!/bin/bash
# Fix all type inference issues in GDScript files

# Find all .gd files and fix type inference for math functions
find . -name "*.gd" -type f ! -path "*/__pycache__/*" -exec sed -i '' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := abs(/var \1: float = abs(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := minf(/var \1: float = minf(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := maxf(/var \1: float = maxf(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := mini(/var \1: int = mini(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := maxi(/var \1: int = maxi(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := sqrt(/var \1: float = sqrt(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := pow(/var \1: float = pow(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := ceil(/var \1: float = ceil(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := floor(/var \1: float = floor(/g' \
  -e 's/var \([a-zA-Z_][a-zA-Z0-9_]*\) := round(/var \1: float = round(/g' \
  {} \;

echo "Fixed type inference issues in all .gd files"
