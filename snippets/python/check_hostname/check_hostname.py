import socket

hostname = socket.gethostname()

if hostname == "L590":
    print("good!")
else:
    raise RuntimeError(f"unkownd hostname: {hostname}")
