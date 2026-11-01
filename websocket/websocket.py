#!/usr/bin/env python3
"""
ToeyVPN v2 — Unified WebSocket Proxy
=====================================
Listens for incoming HTTP WebSocket upgrade requests and tunnels
the connection to a local SSH daemon via raw TCP forwarding.

Usage:
    python3 websocket.py [PORT]

Default listen address : 127.0.0.1:10015
Default forward target : 127.0.0.1:22 (SSH)

The proxy responds with HTTP/1.1 101 Switching Protocols and then
bidirectionally forwards data between the client and the SSH server
using non-blocking select() with a 120-second idle timeout.
"""

import socket
import threading
import select
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 10015
FORWARD_HOST = '127.0.0.1'
FORWARD_PORT = 22
BUFLEN = 16384          # 16 KB buffer for better throughput
TIMEOUT = 120           # 120 second idle timeout
BACKLOG = 128           # listen() backlog

# HTTP 101 response sent to the client after the upgrade request
RESPONSE = (
    b'HTTP/1.1 101 Switching Protocols\r\n'
    b'Upgrade: websocket\r\n'
    b'Connection: Upgrade\r\n'
    b'\r\n'
)


class ConnectionHandler(threading.Thread):
    """Handle a single client connection in its own daemon thread.

    1. Receive the initial HTTP upgrade request from the client.
    2. Open a TCP connection to the SSH server (FORWARD_HOST:FORWARD_PORT).
    3. Send the 101 Switching Protocols response to the client.
    4. Bidirectionally forward data until one side disconnects or times out.
    """

    def __init__(self, client_socket, client_addr):
        super().__init__(daemon=True)
        self.client = client_socket
        self.addr = client_addr
        self.target = None

    def run(self):
        try:
            # Read (and discard) the HTTP upgrade request
            data = self.client.recv(BUFLEN)
            if not data:
                return

            # Connect to the local SSH server
            self.target = socket.create_connection(
                (FORWARD_HOST, FORWARD_PORT),
                timeout=TIMEOUT,
            )

            # Confirm the upgrade to the client
            self.client.sendall(RESPONSE)

            # Bidirectional forwarding
            self._forward()
        except Exception:
            pass
        finally:
            self._close()

    def _forward(self):
        """Forward data between client and target using select()."""
        sockets = [self.client, self.target]
        while True:
            readable, _, exceptional = select.select(
                sockets, [], sockets, TIMEOUT,
            )
            if exceptional or not readable:
                break
            for sock in readable:
                data = sock.recv(BUFLEN)
                if not data:
                    return
                if sock is self.client:
                    self.target.sendall(data)
                else:
                    self.client.sendall(data)

    def _close(self):
        """Safely close both sockets."""
        for sock in (self.target, self.client):
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass


def main():
    """Start the WebSocket proxy server."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTENING_ADDR, LISTENING_PORT))
    server.listen(BACKLOG)
    print(f"ToeyVPN v2 WebSocket Proxy listening on {LISTENING_ADDR}:{LISTENING_PORT}")
    print(f"Forwarding to {FORWARD_HOST}:{FORWARD_PORT}")

    try:
        while True:
            try:
                client, addr = server.accept()
                ConnectionHandler(client, addr).start()
            except Exception:
                continue
    except KeyboardInterrupt:
        print("\nShutting down WebSocket proxy.")
    finally:
        server.close()


if __name__ == '__main__':
    main()
