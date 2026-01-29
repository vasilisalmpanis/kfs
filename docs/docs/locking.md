# Locking

Locking primitives are essential for synchronizing access to shared resources in a
multi-tasking kernel environment.

## Mutex

A mutex (mutual exclusion) is a synchronization primitive used to protect shared
data from being simultaneously accessed by multiple tasks. In **KFS**, the mutex
implementation uses atomic operations to ensure thread-safe locking semantics.

### Structure

```zig
pub const Mutex = struct {
    locked: atomic.Value(bool) = atomic.Value(bool).init(false),
};
```

The mutex contains a single atomic boolean value that tracks the lock state:

- `false` — The mutex is unlocked and available
- `true` — The mutex is locked and owned by a task

### API

| Function | Description |
|:---------|:------------|
| `init()` | Creates a new unlocked mutex |
| `lock()` | Acquires the mutex, blocking until available |
| `trylock()` | Attempts to acquire the mutex without blocking |
| `unlock()` | Releases the mutex |

### Usage

#### Initialization

```zig
var my_mutex = Mutex.init();
```

Or using the default initialization:

```zig
var my_mutex: Mutex = .{};
```

#### Acquiring the Lock

```zig
my_mutex.lock();
// Critical section - access shared resource
my_mutex.unlock();
```

#### Non-blocking Acquisition

```zig
if (my_mutex.trylock()) {
    // Successfully acquired the lock
    // Critical section
    my_mutex.unlock();
} else {
    // Lock was not available
}
```

### Implementation Details

#### Lock Operation

The `lock()` function uses an atomic swap operation with **acquire** memory ordering
to atomically set the lock state to `true` while retrieving the previous value:

```zig
pub fn lock(self: *Mutex) void {
    while (self.locked.swap(true, .acquire)) {
        reschedule();
    }
}
```

If the previous value was `true` (already locked), the task yields execution by
calling `reschedule()`, allowing other tasks to run. This continues until the
lock is successfully acquired.

!!! note "Cooperative Yielding"
    Unlike traditional spinlocks that busy-wait, **KFS** mutexes cooperatively
    yield to the scheduler when contention is detected. This prevents CPU waste
    and ensures fair scheduling among tasks.

#### Try Lock Operation

The `trylock()` function attempts a single lock acquisition without blocking:

```zig
pub fn trylock(self: *Mutex) bool {
    return !self.locked.swap(true, .acquire);
}
```

Returns `true` if the lock was successfully acquired, `false` otherwise.

#### Unlock Operation

The `unlock()` function releases the mutex using **release** memory ordering:

```zig
pub fn unlock(self: *Mutex) void {
    self.locked.store(false, .release);
    reschedule();
}
```

After releasing the lock, the function calls `reschedule()` to give other waiting
tasks an opportunity to acquire the lock promptly.
