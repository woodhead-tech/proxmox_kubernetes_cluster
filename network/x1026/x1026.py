#!/usr/bin/env python3
"""
x1026 — management utility for the Dell Networking X1026 1Gb managed switch.

The X1026 is a Cisco-Small-Business-derived (RASTUTE) switch. Two quirks make a
plain `ssh` painful, both handled here:

  1. Legacy crypto only. Modern OpenSSH disables the KEX/host-key/cipher
     algorithms this firmware (SW 3.0.1.9) speaks, so the right -o flags are
     baked in below. Without them you get "no matching key exchange method".
  2. One admin session at a time. The switch refuses a second login with
     "A client is already connected". The USB serial console counts as a
     session — log out of it before using SSH.
  3. After the SSH transport authenticates, the CLI itself presents a
     "User Name:" / "Password:" login. This script drives that automatically.

No third-party deps — pure stdlib (pty/os/select), because tc1 (the management
host) has neither expect, sshpass, nor paramiko.

Credentials are NEVER stored in this repo. The password is read from, in order:
  --password-file FILE   (file containing the password on its own line)
  $X1026_PASSWORD        (environment variable)
  /etc/x1026.env         (shell-style: X1026_PASSWORD=...)

Usage:
  x1026.py                       # interactive CLI shell
  x1026.py run "show version"    # run one command, print output, exit
  x1026.py run "show running-config"
  x1026.py -H 192.168.86.210 -u admin run "show system"
"""
import argparse
import os
import pty
import re
import select
import sys
import termios
import time
import tty

DEFAULT_HOST = "192.168.86.210"   # DHCP lease on the LAN; see README for static plan
DEFAULT_USER = "admin"

# Legacy algorithms required by the X1026 SSH server (SW 3.0.1.9 / RASTUTE).
SSH_OPTS = [
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o", "Ciphers=+aes128-cbc,aes256-cbc,3des-cbc",
    "-o", "MACs=+hmac-sha1",
    "-o", "ConnectTimeout=10",
    "-o", "NumberOfPasswordPrompts=3",
]

PROMPT_RE = re.compile(rb"[\w.()-]+[#>]\s*$")
MORE_RE = re.compile(rb"More:", re.IGNORECASE)


def load_password(args):
    if args.password_file:
        with open(args.password_file) as f:
            return f.readline().strip()
    if os.environ.get("X1026_PASSWORD"):
        return os.environ["X1026_PASSWORD"]
    for path in ("/etc/x1026.env", os.path.expanduser("~/.x1026.env")):
        if os.path.exists(path):
            for line in open(path):
                line = line.strip()
                if line.startswith("X1026_PASSWORD="):
                    return line.split("=", 1)[1].strip().strip("'\"")
    sys.exit("error: no password found (use --password-file, $X1026_PASSWORD, or /etc/x1026.env)")


def spawn_ssh(host, user):
    pid, fd = pty.fork()
    if pid == 0:  # child
        os.execvp("ssh", ["ssh", *SSH_OPTS, f"{user}@{host}"])
        os._exit(127)
    return pid, fd


def read_available(fd, timeout):
    r, _, _ = select.select([fd], [], [], timeout)
    if fd in r:
        try:
            return os.read(fd, 65536)
        except OSError:
            return b""
    return b""


def do_login(fd, user, password, debug=False):
    """Drive SSH-transport auth + the CLI User Name/Password login. Returns once
    a CLI prompt (ending in # or >) is seen."""
    buf = b""
    sent_user = sent_pass_cli = 0
    deadline = time.time() + 30
    while time.time() < deadline:
        chunk = read_available(fd, 1.0)
        if chunk:
            buf += chunk
            if debug:
                sys.stderr.buffer.write(chunk)
                sys.stderr.buffer.flush()
            tail = buf[-200:]
            low = tail.lower()
            if b"are you sure you want to continue" in low:
                os.write(fd, b"yes\n"); buf = b""; continue
            if b"user name:" in low:
                os.write(fd, (user + "\n").encode()); sent_user += 1
                buf = b""; time.sleep(0.3); continue
            # CLI "Password:" or SSH-transport "password:" — same credential
            if b"password:" in low:
                os.write(fd, (password + "\n").encode()); sent_pass_cli += 1
                buf = b""; time.sleep(0.3); continue
            if b"authentication failed" in low:
                raise SystemExit("error: authentication failed (check password)")
            if b"a client is already connected" in low:
                raise SystemExit("error: switch busy — another admin session is open "
                                 "(log out of the USB serial console first)")
            if PROMPT_RE.search(tail.rstrip()):
                return
    raise SystemExit("error: timed out waiting for CLI prompt during login")


def run_command(fd, command, debug=False):
    """Send one command, auto-advance any pager, capture until prompt."""
    os.write(fd, (command + "\n").encode())
    out = b""
    idle = 0.0
    while True:
        chunk = read_available(fd, 0.5)
        if chunk:
            out += chunk
            idle = 0.0
            if MORE_RE.search(out[-80:]):
                os.write(fd, b" ")  # advance pager
                time.sleep(1.5)    # switch takes >0.5s to clear prompt and send next page
                continue
            if PROMPT_RE.search(out.rstrip()[-120:]):
                break
        else:
            idle += 0.5
            if idle >= 4.0:
                break
    text = out.decode("latin-1")
    # strip the echoed command (first line) and trailing prompt line
    lines = text.splitlines()
    if lines and command in lines[0]:
        lines = lines[1:]
    if lines and PROMPT_RE.search(lines[-1].encode()):
        lines = lines[:-1]
    # strip pager prompt lines (\x1b[0mMore: ...) and the blank erasure lines after them
    lines = [l for l in lines if not MORE_RE.search(l.encode()) and l.strip()]
    return "\n".join(lines).replace("\x1b[K", "").replace("\x1b[0m", "").strip("\r\n")


def interactive(fd):
    """Hand the local terminal to the switch CLI."""
    old = termios.tcgetattr(sys.stdin)
    try:
        tty.setraw(sys.stdin.fileno())
        while True:
            r, _, _ = select.select([sys.stdin, fd], [], [])
            if sys.stdin in r:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data:
                    break
                os.write(fd, data)
            if fd in r:
                data = os.read(fd, 65536)
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old)


def main():
    ap = argparse.ArgumentParser(description="Dell X1026 management utility")
    ap.add_argument("-H", "--host", default=DEFAULT_HOST)
    ap.add_argument("-u", "--user", default=DEFAULT_USER)
    ap.add_argument("--password-file")
    ap.add_argument("--debug", action="store_true", help="print login transcript to stderr")
    sub = ap.add_subparsers(dest="cmd")
    runp = sub.add_parser("run", help="run a command and exit")
    runp.add_argument("command", nargs="+")
    args = ap.parse_args()

    password = load_password(args)
    pid, fd = spawn_ssh(args.host, args.user)
    try:
        do_login(fd, args.user, password, debug=args.debug)
        if args.cmd == "run":
            print(run_command(fd, " ".join(args.command)))
            os.write(fd, b"exit\n")
            time.sleep(0.5)
        else:
            sys.stderr.write("[connected to X1026 — type 'exit' or Ctrl-] to leave]\n")
            interactive(fd)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass


if __name__ == "__main__":
    main()
