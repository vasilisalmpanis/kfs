# Welcome to KFS

KFS (Kernel From Scratch) is a long-term educational project developed
at 42 Wolfsburg that explores the foundations of operating system design
by building a kernel step by step, starting from nothing. Rather than
relying on existing kernels or high-level abstractions, this project
focuses on understanding how things actually work at the lowest level
of a computer system.

The project is divided into multiple stages (**kfs-1** to **kfs-x**), each
introducing new core concepts such as booting, memory management, interrupts,
multitasking, and hardware interaction. Every stage builds upon the previous
one, gradually transforming a minimal bootable binary into a functional and
extensible kernel.

KFS currently features:

- [x] GDT setup
- [x] Framebuffer output
- [x] Paging
- [x] Preemptive multitasking
- [x] Reentrancy
- [x] ATA disk support
- [x] FPU (Lazy context switching)
- [x] VFS
- [x] Ext2 filesystem support
- [x] Device files
- [x] Procfs, Sysfs
- [x] Userspace programs
- [x] TTY subsystem
- [x] VT Parsing
- [x] Kernel modules
- [x] Standard POSIX Signals
- [x] IPC with socketpairs and Unix pipes.

## Commands

* `make` - Compile the project
* `make qemu` - Compile and run the project
* `make clean` - Remove the kernel binary.
* `make fclean` - Remove the kernel binary, iso and all other compilation generated files.

## Project layout

    docs/ # Documentation
        kfs/
            docs
    iso # ISO configuration files
        boot/
            grub/
    src/ # Source code
        arch/
            x86/
                boot/
                mm/
                system/
        debug/
        drivers/
        kernel/
            irq/
            mm/
            sched/
            syscalls/
            time/
            userspace/
            utils/
        mm/
        userspace/
    userspace # Zig userspace programs
        src
    zig-out # Kernel binary output directory
        bin
