#!/usr/bin/env bash
# Generate a Table of Contents from README.md headings.
# Inserts/updates the ToC between <!-- toc --> and <!-- /toc --> markers.
#
# Usage: generate-toc.sh [README.md]
set -euo pipefail

README="${1:-README.md}"

if [ ! -f "$README" ]; then
  echo "Error: $README not found" >&2
  exit 1
fi

# Extract headings (## and deeper), skip the title (first H1)
# and skip everything inside the existing ToC block.
toc_lines=()
in_toc=0
while IFS= read -r line; do
  if [[ "$line" == "<!-- toc -->"* ]]; then
    in_toc=1
    continue
  fi
  if [[ "$line" == "<!-- /toc -->"* ]]; then
    in_toc=0
    continue
  fi
  if [ "$in_toc" -eq 1 ]; then
    continue
  fi

  if [[ "$line" =~ ^(#{2,})\ (.+) ]]; then
    hashes="${BASH_REMATCH[1]}"
    title="${BASH_REMATCH[2]}"

    level=${#hashes}
    indent=$(( (level - 2) * 2 ))
    spaces=""
    for ((i = 0; i < indent; i++)); do
      spaces+=" "
    done

    # Generate anchor: lowercase, spaces to hyphens,
    # strip non-alphanumeric (except hyphens), collapse hyphens.
    anchor=$(echo "$title" \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/ /-/g' \
      | sed 's/[^a-z0-9-]//g' \
      | sed 's/--*/-/g' \
      | sed 's/-$//')

    toc_lines+=("${spaces}- [${title}](#${anchor})")
  fi
done < "$README"

if [ ${#toc_lines[@]} -eq 0 ]; then
  echo "No headings found in $README" >&2
  exit 0
fi

# Write the ToC block to a temp file
toc_file="$(mktemp)"
trap 'rm -f "$toc_file"' EXIT

{
  echo "<!-- toc -->"
  echo ""
  echo "## Table of Contents"
  echo ""
  for entry in "${toc_lines[@]}"; do
    echo "$entry"
  done
  echo ""
  echo "<!-- /toc -->"
} > "$toc_file"

# Build the new README
out_file="$(mktemp)"
trap 'rm -f "$toc_file" "$out_file"' EXIT

has_markers=0
if grep -q '<!-- toc -->' "$README" \
    && grep -q '<!-- /toc -->' "$README"; then
  has_markers=1
fi

if [ "$has_markers" -eq 1 ]; then
  # Replace content between markers (inclusive)
  skip=0
  while IFS= read -r line; do
    if [[ "$line" == "<!-- toc -->"* ]]; then
      cat "$toc_file" >> "$out_file"
      skip=1
      continue
    fi
    if [[ "$line" == "<!-- /toc -->"* ]]; then
      skip=0
      continue
    fi
    if [ "$skip" -eq 0 ]; then
      echo "$line" >> "$out_file"
    fi
  done < "$README"
else
  # Insert after the first H1 line
  inserted=0
  while IFS= read -r line; do
    echo "$line" >> "$out_file"
    if [ "$inserted" -eq 0 ] && [[ "$line" =~ ^#\  ]]; then
      echo "" >> "$out_file"
      cat "$toc_file" >> "$out_file"
      inserted=1
    fi
  done < "$README"
fi

mv "$out_file" "$README"
echo "ToC updated in $README"
