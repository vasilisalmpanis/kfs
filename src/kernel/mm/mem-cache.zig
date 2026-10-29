const kernel = @import("../main.zig");
const std = @import("std");

// KmemCache keeps every page (Pool) of one object type on one of three lists:
//
//   KmemCache
//   -------------   ptr
//   | empty     | -----> Pool <---> Pool              if inuse == 0 we can free
//   | partial   | -----> Pool <---> Pool <---> Pool   if inuse > 0 and < per_pool we can allocate
//   | full      | -----> Pool                         if inuse == per_pool we don't touch
//   -------------
//
//   Each pool is one page in size. The header is in the beginning of the page so
//   cache can easily find it by zeroing bits 0xFFF in the address.
//
//   |                                      | 4096
//   ----------------------------------------
//   |  Pool  | obj 0 | obj 1 | obj 2 | pad |
//   ----------------------------------------
//
//   Lets assume obj 0 and 3 are taken. Free list only has obj2
//   When the whole object pool is in use, the cache allocates
//   another page.
//
//   IDEA: In the future we could link KmemCaches together using a linked
//   list, and use it for memory reclaim if necessary, to free empty
//   pools that are not freed yet.
//
//   https://en.wikipedia.org/wiki/Slab_allocation

// Reject very large objects for now.
const MAX_OBJ_SIZE: usize = kernel.mm.PAGE_SIZE / 8;

const FreeObj = struct {
    next: ?*FreeObj,
};

const Pool = struct {
    list: kernel.list.ListHead,
    cache: *KmemCache,
    free: *FreeObj,
    inuse: u16,
};

const KmemCache = struct {
    name: []const u8,
    obj_size: u32,
    obj_offset: u32,
    per_pool: u32,
    empty: kernel.list.ListHead,
    partial: kernel.list.ListHead,
    full: kernel.list.ListHead,
    lock: kernel.Spinlock,

    fn init(
        name: []const u8,
        comptime size: usize,
        comptime alignment: usize,
    ) KmemCache {
        const al = comptime @max(alignment, @alignOf(FreeObj));
        const obj_size = comptime std.mem.alignForward(usize, @max(size, @sizeOf(FreeObj)), al);
        if (obj_size > MAX_OBJ_SIZE)
            @compileError(std.fmt.comptimePrint(
                "KmemCache object of {d} bytes exceeds {d}",
                .{obj_size, MAX_OBJ_SIZE},
            ));
        const offset = std.mem.alignForward(usize, @sizeOf(Pool), al);
        return .{
            .name = name,
            .obj_size = @intCast(obj_size),
            .obj_offset = @intCast(offset),
            .per_pool = @intCast((kernel.mm.PAGE_SIZE - offset) / obj_size),
            .empty = kernel.list.ListHead.init(),
            .partial = kernel.list.ListHead.init(),
            .full = kernel.list.ListHead.init(),
            .lock = kernel.Spinlock.init(),
        };
    }

    fn setup(self: *KmemCache) void {
        self.empty.setup();
        self.partial.setup();
        self.full.setup();
    }
};

// Public API
//
// Example: var task_cache = Cache(krn.task.Task).init("task");

pub fn Cache(comptime T: type) type {
    return struct {
        inner: KmemCache,

        pub fn init(name: []const u8) @This() {
            return .{ .inner = KmemCache.init(name, @sizeOf(T), @alignOf(T)) };
        }

        pub fn setup(self: *@This()) void {
            self.inner.setup();
        }
    };
}
