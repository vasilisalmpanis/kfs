const os = @import("std").os;
const std = @import("std");

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

pub export fn main() linksection(".text.main") noreturn {
    var status: u32 = undefined;
    const pid= os.linux.fork();
    if (pid == 0) {
        _ = os.linux.syscall0(os.linux.syscalls.X86.getpid);
        os.linux.exit(5);
    } else {
        _ = os.linux.waitpid(@intCast(pid), &status, 0);
        _ = os.linux.kill(@intCast(pid), 1);
        _ = os.linux.write(1, "hello from userspace\n", 21);
    }
    while (true) {}
}
