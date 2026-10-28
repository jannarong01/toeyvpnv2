#!/usr/bin/env python3
import socket
import threading
import select
import sys

LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 10015
DEFAULT_HOST = '127.0.0.1:22'
BUFLEN = 65536
TIMEOUT = 120
RESPONSE = b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'

class ConnectionHandler(threading.Thread):
    def __init__(self, client, addr):
        super().__init__(daemon=True)
        self.client = client
        self.addr = addr
        self.target = None

    def run(self):
        try:
            self.client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            data = self.client.recv(BUFLEN)
            if not data:
                return
            host, port = DEFAULT_HOST.split(':')
            self.target = socket.create_connection((host, int(port)), timeout=TIMEOUT)
            self.target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.client.sendall(RESPONSE)
            self.forward()
        except Exception:
            pass
        finally:
            self.cleanup()

    def forward(self):
        sockets = [self.client, self.target]
        while True:
            r, _, e = select.select(sockets, [], sockets, TIMEOUT)
            if e or not r:
                break
            for s in r:
                data = s.recv(BUFLEN)
                if not data:
                    return
                if s is self.client:
                    self.target.sendall(data)
                else:
                    self.client.sendall(data)

    def cleanup(self):
        for s in (self.target, self.client):
            if s:
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTENING_ADDR, LISTENING_PORT))
    server.listen(1024)
    print(f"ToeyVPN V2 WebSocket Proxy listening on {LISTENING_ADDR}:{LISTENING_PORT} -> {DEFAULT_HOST}")
    while True:
        try:
            client, addr = server.accept()
            ConnectionHandler(client, addr).start()
        except KeyboardInterrupt:
            break
        except Exception:
            continue

if __name__ == '__main__':
    main()
