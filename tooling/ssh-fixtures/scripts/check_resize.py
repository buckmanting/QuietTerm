#!/usr/bin/env python3
import argparse
import fcntl
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

SIZE_PATTERN = re.compile(r"^\s*(\d+)\s+(\d+)\s*$")


def set_winsize(fd: int, rows: int, cols: int) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SSH PTY resize propagation")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--user", required=True)
    parser.add_argument("--private-key", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--rows", required=True, type=int)
    parser.add_argument("--cols", required=True, type=int)
    parser.add_argument("--timeout", type=float, default=25.0)
    parser.add_argument("--artifact", required=True)
    args = parser.parse_args()

    command = [
        "ssh",
        "-tt",
        "-i",
        args.private_key,
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f"UserKnownHostsFile={args.known_hosts}",
        "-o",
        "PreferredAuthentications=publickey",
        "-o",
        "PubkeyAuthentication=yes",
        "-o",
        "PasswordAuthentication=no",
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-p",
        str(args.port),
        f"{args.user}@{args.host}",
        "sh -lc 'stty size; read -r _; stty size'",
    ]

    master_fd, slave_fd = os.openpty()
    os.makedirs(args.artifact, exist_ok=True)
    transcript_path = os.path.join(args.artifact, "resize.transcript.log")
    sizes_path = os.path.join(args.artifact, "resize.sizes.txt")

    try:
        set_winsize(master_fd, 24, 80)

        process = subprocess.Popen(
            command,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            text=False,
            close_fds=True,
        )
    finally:
        os.close(slave_fd)

    resize_sent = False
    sizes = []
    buffer = b""
    deadline = time.time() + args.timeout

    with open(transcript_path, "wb") as transcript:
        while time.time() < deadline:
            ready, _, _ = select.select([master_fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    chunk = b""

                if not chunk:
                    if process.poll() is not None:
                        break
                    continue

                transcript.write(chunk)
                transcript.flush()
                buffer += chunk

                decoded = buffer.decode("utf-8", errors="ignore")
                lines = decoded.replace("\r", "\n").split("\n")
                if decoded and not decoded.endswith(("\n", "\r")):
                    # Keep unfinished trailing bytes for the next read.
                    buffer = lines[-1].encode("utf-8", errors="ignore")
                    lines = lines[:-1]
                else:
                    buffer = b""

                for line in lines:
                    match = SIZE_PATTERN.match(line)
                    if not match:
                        continue

                    rows = int(match.group(1))
                    cols = int(match.group(2))
                    sizes.append((rows, cols))

                    if len(sizes) == 1 and not resize_sent:
                        set_winsize(master_fd, args.rows, args.cols)
                        process.send_signal(signal.SIGWINCH)
                        os.write(master_fd, b"\n")
                        resize_sent = True

                    if len(sizes) >= 2:
                        break

            if len(sizes) >= 2 and process.poll() is not None:
                break

        if process.poll() is None:
            process.terminate()

        try:
            exit_code = process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            exit_code = process.wait(timeout=2)

    os.close(master_fd)

    with open(sizes_path, "w", encoding="utf-8") as size_file:
        for index, (rows, cols) in enumerate(sizes):
            size_file.write(f"sample{index + 1}={rows} {cols}\n")

    if len(sizes) < 2:
        print(f"Expected two stty size snapshots, got {len(sizes)}", file=sys.stderr)
        return 11

    initial_rows, initial_cols = sizes[0]
    resized_rows, resized_cols = sizes[1]

    if (resized_rows, resized_cols) != (args.rows, args.cols):
        print(
            f"Unexpected resized dimensions: expected {args.rows} {args.cols}, got {resized_rows} {resized_cols}",
            file=sys.stderr,
        )
        return 12

    if (initial_rows, initial_cols) == (resized_rows, resized_cols):
        print("Resize did not change remote PTY dimensions", file=sys.stderr)
        return 13

    if exit_code != 0:
        print(f"SSH process exited with status {exit_code}", file=sys.stderr)
        return 14

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
