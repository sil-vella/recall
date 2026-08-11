# dash Stream script output over WebSocket via PTY
"""PTY-backed process runner for streaming terminal I/O over WebSocket."""

from __future__ import annotations

import asyncio
import fcntl
import os
import pty
import struct
import subprocess
import termios
from collections.abc import Awaitable, Callable
from typing import Any

OutputCallback = Callable[[bytes], Awaitable[None]]
ExitCallback = Callable[[int], Awaitable[None]]


class PtyRunner:
    def __init__(
        self,
        cmd: list[str],
        env: dict[str, str],
        cwd: str,
        cols: int = 80,
        rows: int = 24,
    ) -> None:
        self._cmd = cmd
        self._env = env
        self._cwd = cwd
        self._cols = cols
        self._rows = rows
        self._master_fd: int | None = None
        self._proc: subprocess.Popen[Any] | None = None
        self._read_task: asyncio.Task[None] | None = None
        self._wait_task: asyncio.Task[None] | None = None
        self._closed = False

    @property
    def running(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def start(
        self,
        on_output: OutputCallback,
        on_exit: ExitCallback,
    ) -> None:
        master_fd, slave_fd = pty.openpty()
        self._set_window_size(master_fd, self._cols, self._rows)
        self._master_fd = master_fd

        self._proc = subprocess.Popen(
            self._cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=self._env,
            cwd=self._cwd,
            preexec_fn=os.setsid,
            close_fds=True,
        )
        os.close(slave_fd)

        loop = asyncio.get_running_loop()
        self._read_task = loop.create_task(self._read_loop(on_output))
        self._wait_task = loop.create_task(self._wait_loop(on_exit))

    def resize(self, cols: int, rows: int) -> None:
        self._cols = cols
        self._rows = rows
        if self._master_fd is not None:
            self._set_window_size(self._master_fd, cols, rows)

    def write_input(self, data: bytes) -> None:
        if self._master_fd is None or self._closed:
            return
        os.write(self._master_fd, data)

    async def terminate(self) -> None:
        if self._closed:
            return
        self._closed = True

        proc = self._proc
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(os.getpgid(proc.pid), 15)
            except ProcessLookupError:
                pass
            try:
                await asyncio.wait_for(asyncio.to_thread(proc.wait), timeout=2.0)
            except TimeoutError:
                try:
                    os.killpg(os.getpgid(proc.pid), 9)
                except ProcessLookupError:
                    pass
                await asyncio.to_thread(proc.wait)

        for task in (self._read_task, self._wait_task):
            if task is not None:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        if self._master_fd is not None:
            try:
                os.close(self._master_fd)
            except OSError:
                pass
            self._master_fd = None

    async def _read_loop(self, on_output: OutputCallback) -> None:
        assert self._master_fd is not None
        loop = asyncio.get_running_loop()
        fd = self._master_fd

        while not self._closed:
            try:
                data = await loop.run_in_executor(None, os.read, fd, 4096)
            except OSError:
                break
            if not data:
                break
            await on_output(data)

    async def _wait_loop(self, on_exit: ExitCallback) -> None:
        proc = self._proc
        if proc is None:
            await on_exit(1)
            return
        code = await asyncio.to_thread(proc.wait)
        if not self._closed:
            await on_exit(code)

    @staticmethod
    def _set_window_size(master_fd: int, cols: int, rows: int) -> None:
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
