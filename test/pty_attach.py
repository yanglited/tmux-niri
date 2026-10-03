import os, pty, fcntl, termios, struct, sys, time, select
S=sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ.setdefault('TERM', 'xterm-256color')   # CI runners have no TERM; tmux attach needs one
    os.execvp('tmux', ['tmux','-L',S,'attach','-t','t'])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 20, 100, 0, 0))
# drain output forever
while True:
    r,_,_ = select.select([fd],[],[],1)
    if r:
        try: os.read(fd, 65536)
        except OSError: break
