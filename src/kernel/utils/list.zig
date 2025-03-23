
pub const Iterator = struct {
    curr: *ListHead,
    head: *ListHead,
    used: bool = false,

    pub fn init(head: *ListHead) Iterator {
        return .{
            .curr = head,
            .head = head,
        };
    }

    pub fn next(self: *Iterator) ?*Iterator {
        if (self.curr == self.head and !self.used) {
            self.used = true;
            return self;
        }
        if (self.curr.next == null)
            return null;
        self.curr = self.curr.next.?;
        if (self.curr == self.head)
            return null;
        return self;
    }

    pub fn is_last(self: *Iterator) bool {
        return self.curr.next == self.head;
    }
};

pub const ListHead = packed struct {
    next: ?*ListHead,
    prev: ?*ListHead,

    pub fn init() ListHead {
        return .{
            .next = null,
            .prev = null,
        };
    }

    pub fn setup(self: *ListHead) void {
        self.next = self;
        self.prev = self;
    }

    pub fn iterator(self: *ListHead) Iterator {
        return Iterator.init(self);
    }

    pub fn entry(self: *ListHead, comptime T: type, comptime member: []const u8) *T {
        return container_of(T, @intFromPtr(self), member);
    }

    pub fn add(self: *ListHead, new: *ListHead) void {
        const next = self.next;
        self.next = new;
        new.prev = self;
        new.next = next;
        if (next) |nxt| {
            nxt.prev = new;
        }
    }

    pub fn add_tail(self: *ListHead, new: *ListHead) void {
        if (self.prev == null) {
            new.next = self;
            self.prev = new;
            new.prev = null;
        } else {
            self.prev.?.add(new);
        }
    }

    pub fn del(self: *ListHead) void {
        if (self.prev == null and self.next == null) {
            return;
        } else if (self.prev == null) {
            self.next.?.prev = null;
            return ;
        } else if (self.next == null) {
            self.prev.?.next = null;
            return ;
        }
        self.prev.?.next = self.next;
        self.next.?.prev = self.prev;
    }

    pub fn is_single(self: *ListHead) bool {
        return self.next == self;
    }
};

pub fn container_of(comptime T: type, ptr: u32, comptime member: []const u8) *T {
    const offset = @offsetOf(T, member);
    const result: *T = @ptrFromInt(ptr - offset);
    return result;
}

pub fn list_map(
    comptime T: type,
    head: *ListHead, f: fn (arg: *T) void,
    comptime member: [] const u8
) void {
    var buf: ?*ListHead = head;
    while (buf != null) : (buf = buf.?.next) {
        f(container_of(T, @intFromPtr(buf.?), member));
    }
}
