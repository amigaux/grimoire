#!/bin/bash
# amishot.sh [--socket PATH] [outfile] -- capture an Amiberry's Amiga framebuffer to a
# PNG via Amiberry's IPC socket.  Works under Wayland/GNOME where grim/gnome-screenshot
# /Shell-DBus are all blocked, because it asks Amiberry itself to render the shot.
# Protocol (discovered from the amiberry binary): send "SCREENSHOT\t<abspath>\n"
# to the socket; reply "OK\t<path>" or "ERROR\t<msg>".
#
# The socket must be named, with --socket or AMIBERRY_SOCK; there is no default.
# Amiberry's first instance listens on $XDG_RUNTIME_DIR/amiberry.sock and later ones
# on amiberry_1.sock, amiberry_2.sock and so on, so with several running the
# default name belongs to whichever started first, and a shot could come from
# another emulator.  Exit status: 0 on OK, 1 on an error reply or no connection,
# 2 for a usage error.
SOCK="${AMIBERRY_SOCK:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --socket) [ $# -ge 2 ] || { echo "amishot: --socket needs a path" >&2; exit 2; }
                  SOCK="$2"; shift 2 ;;
        --socket=*) SOCK="${1#--socket=}"; shift ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --) shift; break ;;
        -*) echo "amishot: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ -z "$SOCK" ]; then
    echo "amishot: name the emulator's socket with --socket PATH or AMIBERRY_SOCK" >&2
    ls "${XDG_RUNTIME_DIR:-/tmp}"/amiberry*.sock 2>/dev/null | sed 's/^/  found: /' >&2
    exit 2
fi
[ -S "$SOCK" ] || { echo "amishot: not a socket: $SOCK" >&2; exit 1; }
F="${1:-$(pwd)/tmp/shots/shot.png}"
case "$F" in /*) ;; *) F="$(pwd)/$F";; esac
mkdir -p "$(dirname "$F")"
python3 - "$F" "$SOCK" <<'PY'
import socket, sys
f, sock = sys.argv[1], sys.argv[2]
try:
    s = socket.socket(socket.AF_UNIX); s.settimeout(3); s.connect(sock)
    s.sendall(('SCREENSHOT\t%s\n' % f).encode())
    reply = s.recv(256).decode().strip()
    s.close()
except Exception as e:
    print("ERR", e)
    sys.exit(1)
print(reply)
sys.exit(0 if reply.startswith('OK') else 1)
PY
