fn syscall(num: u32, arg1: u32, arg2: u32, arg3: u32, arg4: u32) i32 {
    asm volatile(
        \\ int $0x80
        ::
            [_] "{eax}" (num),
            [_] "{ebx}" (arg1),
            [_] "{ecx}" (arg2),
            [_] "{edx}" (arg3),
            [_] "{esi}" (arg4),
    );
    return asm volatile("":[_] "={eax}" (-> i32));
}

fn fork() i32 {
    return syscall(57, 0, 0,0,0);
}

fn exit(code: u32) i32 {
    return syscall(60, code, 0,0,0);
}

fn wait(pid: i32) i32 {
    return syscall(61, @intCast(pid), 0,0,0);
}

fn kill(pid: u32, signal: u32) i32 {
    return syscall(62, pid, signal,0,0);
}

pub export fn _start() noreturn {
    const pid = fork();
    if (pid == 0) {
        _ = syscall(10, 0, 0, 0, 0);
    } else {
        const res = wait(pid);
        _ = res;
    }
    while (true) {}
}
