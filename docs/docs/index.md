# Welcome to KFS

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
