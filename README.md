# KFS

A minimalistic kernel written in Zig.

- [x] kfs-1
- [x] kfs-2
- [ ] kfs-3
- [ ] kfs-4
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

### Multi-Monitor Support
For multi-monitor testing, use:
```sh
make multimonitor
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

## Acknowledgments

- The [Zig programming language](https://ziglang.org).
- [OSDev](https://wiki.osdev.org).
