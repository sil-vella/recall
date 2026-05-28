#!/usr/bin/env bash
# Run Flutter with production dart-defines (.env.dart.defines.prod).
# Wrapper around run_flutter_app_to_global_log.sh — see that script for modes and logging.
#
# Usage:
#   ./run_flutter_app_to_global_log_prod.sh chrome
#   ./run_flutter_app_to_global_log_prod.sh android <adb_serial>
#   ./run_flutter_app_to_global_log_prod.sh ios <simulator_or_device_id>
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_flutter_app_to_global_log.sh" --prod "$@"
