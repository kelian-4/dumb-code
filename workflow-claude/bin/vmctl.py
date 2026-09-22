import socket, time, sys

def cmd(c, wait=3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("/tmp/vm-serial.sock")
    s.sendall(c.encode()+b"\n")
    time.sleep(wait)
    data = b""
    s.settimeout(1)
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk: break
            data += chunk
    except socket.timeout:
        pass
    s.close()
    return data.decode(errors='replace')

if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else ""
    w = float(sys.argv[2]) if len(sys.argv) > 2 else 3
    print(cmd(c, w))
