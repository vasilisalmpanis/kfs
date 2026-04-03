## Run the image with QEMU

Download either `kfs-min.img` or `kfs-full.img` from this release, then run:

```sh
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G
```

On Linux with KVM enabled, use acceleration:

```sh
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G -enable-kvm
```

## Serial logging and TTYs

Use `-serial stdio` for serial logs in your terminal.

You can allocate PTY-backed serial devices with `-serial pty` (up to two additional serial TTYs in the current image). QEMU prints paths like `char device redirected to /dev/pts/<N>`.

Connect to a PTY using `screen`:

```sh
screen /dev/pts/<N>
```

In the current setup:
- 1st serial device: logs
- 2nd and 3rd serial devices: TTYs

Example setups:

```sh
# 1) Logs to file, TTY in current terminal
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G -enable-kvm -serial file:kfs.log -serial stdio

# 2) Logs in current terminal, TTY on PTY
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G -enable-kvm -serial stdio -serial pty

# 3) No logs, TTY in current terminal
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G -enable-kvm -serial null -serial stdio

# 4) Logs in current terminal, two PTY TTYs
qemu-system-i386 -drive file=kfs-min.img,format=raw -m 4G -enable-kvm -serial stdio -serial pty -serial pty
```

## Default login

- Username: `root`
- Password: `admin`
