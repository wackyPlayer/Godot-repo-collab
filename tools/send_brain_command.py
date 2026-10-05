"""Send a brain signal to the game, the way the headset detector does: a
short UDP text message. Use it to test the hook-up without the headset.

    python tools/send_brain_command.py BLINK
    python tools/send_brain_command.py MOUTH 1000 192.168.1.20

Default words: BLINK (turn), MOUTH (go / stop), EYES (run). Arguments: the
word, then optionally the port (default 1000) and the game computer's IP
(default this computer). Turn on the brain interface in Settings first.
"""
import socket
import sys

word = sys.argv[1] if len(sys.argv) > 1 else "BLINK"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
host = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"
socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(word.encode("utf-8"), (host, port))
print(f"Sent {word!r} to {host}:{port}")
