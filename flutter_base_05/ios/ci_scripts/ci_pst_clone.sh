#!/bin/bash
set -euo pipefail

# Compatibility shim for an older typoed Xcode Cloud script path.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/ci_post_clone.sh"
