
pub const list_head = struct {
    next: ?*list_head,
    prev: ?*list_head,
};

// danger
pub fn container_of(comptime T: type, ptr: u32, comptime member: []const u8) *T {
    const offset = @offsetOf(T, member);
    const result: *T = @ptrFromInt(ptr - offset);
    return result;
}

pub fn list_add(new: *list_head, head: *list_head) void {
    const next = head.next;
    head.next = new;
    new.prev = head;
    new.next = next;
    if (next) |nxt| {
        nxt.prev = new;
    }
}

pub fn list_add_tail(new: *list_head, head: *list_head) void {
    if (head.prev == null) {
        new.next = head;
        head.prev = new;
        new.prev = null;
        return ;
    }
    list_add(new, head.prev.?);
}
pub fn list_del(entry: *list_head) void {
    if (entry.prev == null) {
        entry.next.?.prev = null;
        return ;
    }
    entry.prev.?.next = entry.next;
    entry.next.?.prev = entry.prev;
}

pub fn list_empty(list: *list_head) bool {
    return list.next == list;
}

pub fn list_map(
    comptime T: type,
    head: *list_head, f: fn (arg: *T) void,
    comptime member: [] const u8
) void {
    var buf: ?*list_head = head;
    while (buf != null) : (buf = buf.?.next) {
        f(container_of(T, @intFromPtr(buf.?), member));
    }
}

pub fn list_entry(comptime T: type, ptr: u32, comptime member: []const u8) *T {
    return container_of(T, ptr, member);
}
