# KFS

A minimalistic kernel written in Zig.

- [x] kfs-1
- [x] kfs-2
- [x] kfs-3
- [x] kfs-4
- [ ] kfs-5
- [ ] kfs-6
- [ ] kfs-7
- [ ] kfs-8
- [ ] kfs-9
- [ ] kfs-x

## Overview

KFS is a small, experimental kernel written in the [Zig](https://ziglang.org/) programming language. It is designed to run on x86 architectures and features fundamental low-level components required for an operating system.

### Features

- **x86 Support** - Runs on x86 architecture.
- **Global Descriptor Table (GDT)** - Proper segmentation setup.
- **Shell** - Basic interactive shell support.
- **Memory Management** - Custom memory management implementation ([Details](./Memory.md#overview)).

## Building KFS

### Prerequisites

To build and run KFS, you need the following:

- **Zig Compiler** (latest version)
- **GRUB** (for creating bootable ISOs)
- **QEMU** (for testing the kernel)
- **Make**

### Build Instructions

You can build the project using `make`:

#### Building the Kernel and ISO:
```sh
make
```

This will:
1. Compile the kernel using `zig build`.
2. Copy the kernel binary to `iso/boot/`.
3. Generate `kfs.iso` using `grub-mkrescue`.

### Cleaning the Build

To remove compiled files, use:
```sh
make clean
```

## Running KFS in QEMU

### Standard Execution
Run the kernel in QEMU using:
```sh
make qemu
```

### Debug session
For starting gdb session, use:
```sh
make debug
```

## Project Structure

```
kfs/
│── src/          # Source code
│── iso/          # Bootable ISO-related files
│── build.zig     # Zig build script
│── linker.ld     # Linker script
│── Makefile      # Makefile for building ISO
│── README.md     # Project documentation
│── Memory.md     # Details on memory management
│── .gitignore    # Git ignore file
```

## Contributing

Contributions are welcome! If you want to contribute:

1. Fork the repository.
2. Create a new branch.
3. Make your changes and test them.
4. Open a pull request with a clear description of your changes.

## License

This project is licensed under [MIT License](LICENSE).

## Resources

- https://wiki.osdev.org/
- https://github.com/dreamportdev/Osdev-Notes
- http://www.osdever.net/tutorials/
- https://operating-system-in-1000-lines.vercel.app/en/
- http://www.brokenthorn.com/Resources/OSDevIndex.html
- https://web.archive.org/web/20221206224127/http://www.jamesmolloy.co.uk/tutorial_html/1.-Environment%20setup.html
- https://jsandler18.github.io/
- https://samypesse.gitbook.io/how-to-create-an-operating-system/
- https://github.com/cfenollosa/os-tutorial/blob/master/README.md
- https://os.phil-opp.com/
- https://littleosbook.github.io/
- https://litux.nl/mirror/kerneldevelopment/0672327201/toc.html
- https://linux-kernel-labs.github.io/refs/heads/master/index.html
- https://pdos.csail.mit.edu/6.828/2024/schedule.html
- https://kbd-project.org/index.html#documentation
- https://www.gingerbill.org/series/memory-allocation-strategies/
- https://krinkinmu.github.io/
- https://0xax.gitbooks.io/linux-insides/content/
- https://pages.cs.wisc.edu/~remzi/OSTEP/
- https://greenteapress.com/thinkos/html/index.html
- https://osblog.stephenmarz.com/index.html
- https://www.bottomupcs.com/
- https://www.singlix.com/trdos/archive/

## Acknowledgments

- The [Zig programming language](https://ziglang.org).
- [OSDev](https://wiki.osdev.org).
