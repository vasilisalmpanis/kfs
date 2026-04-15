# vDSO (virtual Dynamic Shared Object)

The vDSO is a small shared library that the kernel maps into every userspace
process. It allows certain system calls — specifically time-related ones — to
be executed entirely in userspace without the cost of a context switch into
the kernel.

On x86, every `int $0x80` or `sysenter` transition involves saving registers,
switching privilege levels, and flushing pipeline state. For frequently called
functions like `clock_gettime`, this overhead dominates the actual work.
The vDSO eliminates it by placing both the data and the code to read it
directly in the process's address space.

## Architecture

The vDSO consists of two components mapped into every process:

| Component | Size | Permissions | Purpose |
|:----------|:-----|:------------|:--------|
| **vvar page** | 1 page (4 KiB) | User: read-only, Kernel: read-write | Shared time data updated by the kernel |
| **vDSO code page** | 1 page (4 KiB) | User: read-only | ELF shared library with `__vdso_clock_gettime` |

The vvar page holds a `VdsoData` struct that the kernel writes to on every
timer tick. The vDSO code page contains a position-independent ELF shared
library that reads from the vvar page to service time queries.

```
Process virtual address space (top):

  0xBFFE0000  ┌──────────────────┐
              │   User stack     │  30 pages, RW
              │   (grows down)   │
  0xBFFFE000  ├──────────────────┤
              │   vvar page      │  1 page, RO (shared physical page)
  0xBFFFF000  ├──────────────────┤
              │   vDSO code      │  1 page, RO (ELF with __vdso_clock_gettime)
  0xC0000000  └──────────────────┘
              │   Kernel space   │
```

### Why two separate pages?

The vvar and vDSO code live in separate pages for security:

- The **vvar page** is mapped read-only for userspace but the kernel holds a
  separate read-write mapping to the same physical page. This allows the kernel
  to update time data without giving userspace write access.
- The **vDSO code page** is read-only and contains executable code. Keeping data
  and code separate follows the W^X (write xor execute) principle.

## Shared Data: VdsoData

The vvar page contains a single `VdsoData` struct at offset 0:

```zig
pub const VdsoData = extern struct {
    seq: u32,            // seqlock counter
    monotonic_sec: i32,
    monotonic_nsec: i32,
    realtime_sec: i64,
    realtime_nsec: i32,
    _pad: i32,
};
```

The kernel writes to this struct from the timer interrupt handler on every tick.
Userspace reads from it without any syscall.

### Seqlock Protocol

The `seq` field implements a seqlock — a lightweight synchronization mechanism
optimized for the single-writer, multiple-reader pattern:

**Kernel (writer):**

1. Increment `seq` to an odd value (signals: update in progress)
2. Memory barrier
3. Write time data
4. Memory barrier
5. Increment `seq` to an even value (signals: update complete)

**Userspace (reader):**

1. Read `seq` — spin while odd (writer is active)
2. Memory barrier
3. Read time data
4. Memory barrier
5. Read `seq` again — if changed, data was torn, retry from step 1

This guarantees userspace always reads a consistent snapshot without any locks
or atomic operations beyond simple loads.

```zig
// Kernel side (timer interrupt)
vvar_data.seq +%= 1;           // odd: update started
asm volatile ("" ::: .{ .memory = true });
vvar_data.monotonic_sec = ...;
vvar_data.monotonic_nsec = ...;
asm volatile ("" ::: .{ .memory = true });
vvar_data.seq +%= 1;           // even: update complete
```

```zig
// Userspace side (vDSO code)
while (true) {
    var seq1 = vvar.seq;
    while (seq1 & 1 != 0) seq1 = vvar.seq;  // spin while odd
    // read time fields ...
    if (seq1 == vvar.seq) return 0;          // consistent read
}
```

## Build Pipeline

The vDSO is compiled as a separate ELF shared library and embedded into the
kernel binary at build time:

1. **Compile** `src/vdso/vdso_time.zig` as a PIC shared library targeting
   `x86-linux-none` with `ReleaseSmall` optimization
2. **Link** with `src/vdso/vdso.ld` which strips unnecessary sections (`.got`,
   `.bss`, `.eh_frame`) to minimize size
3. **Embed** the resulting `vdso.so` into the kernel module via a generated
   Zig wrapper that uses `@embedFile`
4. At runtime the kernel copies the embedded ELF bytes into userspace pages

The vDSO ELF is typically under 1 KiB and fits in a single page.

### Position Independence

The vDSO code must work at any virtual address since the mapping location can
vary. On x86-32 there is no RIP-relative addressing, so the vDSO uses a
classic `call/pop` idiom to determine its own program counter at runtime:

```zig
inline fn getVvarData() *const volatile VdsoData {
    const pc = asm volatile (
        \\call 1f
        \\1: pop %[ret]
        : [ret] "=r" (-> u32),
    );
    const vvar_addr = (pc & 0xFFFFF000) - 0x1000;
    return @ptrFromInt(vvar_addr);
}
```

This avoids any GOT (Global Offset Table) dependency. The vvar page is always
one page before the vDSO code page, so the address is computed by page-aligning
the current PC and subtracting `0x1000`.

!!! note "Why not use an extern symbol?"
    x86-32 PIC code routes extern symbol accesses through the GOT,
    which requires relocation processing by a dynamic linker.
    Since the kernel maps the vDSO by raw `@memcpy` without applying
    relocations, GOT entries remain uninitialized (zero), causing null pointer
    dereferences. The PC-relative approach eliminates this entirely.

## Kernel Integration

### Initialization

During boot, `vdso.init()` is called after memory management is set up:

1. Allocate one physical page for the vvar data
2. Map it into kernel virtual address space as read-write
3. Zero the page
4. allocated vdso.len / PAGE_SIZE pages, and copy the content of the vdso
   libray to those pages, padding the rest with 0.

After CMOS initialization, `cmos.ready` is set to true to enable
realtime clock updates in the vvar data.

### Timer Update

On every timer interrupt, `vdso.update()` writes the current
monotonic and realtime timestamps to the vvar page using the seqlock protocol.

### Process Mapping

When a new process is created via `execve`, `prepareBinary()` maps both the
vvar and vDSO code pages into the process address space:

1. **vvar page**: A new VMA is created and the shared physical page is mapped
   user-read-only. All processes share the same physical page so they all
   see the same time data.
2. **vDSO code page**: A new physical page is allocated, the embedded ELF is
   copied in, and the page is then made read-only.
3. **Auxiliary vector**: `AT_SYSINFO_EHDR` (value 33) is added pointing to
   the vDSO ELF header address.

### Fork Behavior

On `fork()`, the vvar VMA is duplicated like any other shared mapping —
`dupArea` maps the underlying physical frame to the vvar, vdso address.

## Userspace Discovery

C libraries (musl, glibc) automatically discover and use the vDSO:

1. During `_start`, the C runtime walks the auxiliary vector on the stack
2. It reads `AT_SYSINFO_EHDR` to find the vDSO ELF header
3. It parses the ELF dynamic section to find `DT_SYMTAB`, `DT_STRTAB`, and
   `DT_HASH`
4. It looks up `__vdso_clock_gettime` in the symbol table
5. If found, `clock_gettime()` calls the vDSO function directly instead of
   issuing a syscall

This is transparent to application code — calling `clock_gettime()` in C
automatically uses the vDSO path when available.

## Supported Clocks

| Clock ID | Constant | Description |
|:---------|:---------|:------------|
| 0 | `CLOCK_REALTIME` | Wall clock time from CMOS |
| 1 | `CLOCK_MONOTONIC` | Time since kernel boot |
