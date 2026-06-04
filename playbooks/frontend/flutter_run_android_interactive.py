#!/usr/bin/env python3
"""
Run `flutter run` on a PTY and relay the terminal.

Custom key (like Flutter's R = hot restart):
  V — toggle adb screenrecord on the target device (see android_screenrecord_toggle.sh)

All other keys are forwarded to Flutter (r, R, h, q, …).
"""
from __future__ import annotations

import argparse
import os
import pty
import select
import subprocess
import sys
import termios
import tty


def _toggle_record(script_dir: str, device: str) -> None:
    toggle = os.path.join(script_dir, "android_screenrecord_toggle.sh")
    subprocess.run(["/bin/bash", toggle, device], check=False)


def _relay(master_fd: int, device: str, script_dir: str) -> int:
    if not sys.stdin.isatty():
        # Non-TTY stdin: only pump flutter output (e.g. piped CI).
        while True:
            r, _, _ = select.select([master_fd], [], [], 0.2)
            if not r:
                continue
            try:
                chunk = os.read(master_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            os.write(sys.stdout.fileno(), chunk)
        return 0

    stdin_fd = sys.stdin.fileno()
    old = termios.tcgetattr(stdin_fd)
    try:
        tty.setraw(stdin_fd)
        while True:
            r, _, _ = select.select([master_fd, stdin_fd], [], [], 0.1)
            if master_fd in r:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                os.write(sys.stdout.fileno(), chunk)
            if stdin_fd in r:
                data = os.read(stdin_fd, 1)
                if not data:
                    break
                ch = data.decode("utf-8", errors="replace")
                if ch in ("V", "v"):
                    _toggle_record(script_dir, device)
                    continue
                os.write(master_fd, data)
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Flutter run with V = screen record toggle")
    parser.add_argument("--device", required=True, help="adb device serial")
    parser.add_argument(
        "--dart-define-from-file",
        required=True,
        help="JSON file for flutter --dart-define-from-file",
    )
    parser.add_argument(
        "--cwd",
        default=".",
        help="flutter project directory (flutter_base_05)",
    )
    args = parser.parse_args()
    script_dir = os.path.dirname(os.path.abspath(__file__))

    flutter_argv = [
        "flutter",
        "run",
        "-d",
        args.device,
        "--dart-define=DUTCH_DEV_LOG=1",
        f"--dart-define-from-file={args.dart_define_from_file}",
    ]

    print(
        "\n📱 Flutter interactive — V = toggle screen record (adb), "
        "r/R = reload/restart, h = help, q = quit\n",
        file=sys.stderr,
        flush=True,
    )

    pid, master_fd = pty.fork()
    if pid == 0:
        os.chdir(args.cwd)
        os.execvp("flutter", flutter_argv)
    try:
        return _relay(master_fd, args.device, script_dir)
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
