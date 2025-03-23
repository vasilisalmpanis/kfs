const container_of = @import("./list.zig").container_of;

pub const TreeNode = struct {
    parent: ?*TreeNode  = null,
    child: ?*TreeNode   = null,
    next: ?*TreeNode    = null,
    prev: ?*TreeNode    = null,

    pub fn init() TreeNode {
        return .{};
    }
    
    pub fn setup(self: *TreeNode) void {
        self.parent = self;
        self.child = self;
        self.next = self;
        self.prev = self;
    }

    pub fn has_children(self: *TreeNode) bool {
        return self.child != self;
    }

    pub fn has_siblings(self: *TreeNode) bool {
        return self.next != self;
    }

    pub fn add_sibling(self: *TreeNode, new: *TreeNode) void {
        new.next = self;
        new.prev = self.prev;

        self.prev.?.next = new;
        self.prev = new;
        new.parent = self.parent;
    }

    pub fn add_child(self: *TreeNode, new: *TreeNode) void {
        if (self.has_children()) {
            self.child.?.add_sibling(new);
        } else {
            self.child = new;
        }
        new.parent = self;
    }

    pub fn set_parent(self: *TreeNode, parent: *TreeNode) void {
        var it = self.siblings_iterator();
        while (it.next()) |i| {
            i.curr.parent = parent;
        }
    }

    pub fn add_children(self: *TreeNode, new: *TreeNode) void {
        new.set_parent(self);
        if (self.has_children()) {
            const old_prev_child = self.child.?.prev;
            const new_prev_child = new.prev;
            new_prev_child.?.next = self.child;
            self.child.?.prev = new_prev_child;
            new.prev = old_prev_child;
            old_prev_child.?.next = new;
        } else {
            self.child = new;
        }
    }

    pub fn del(self: *TreeNode) void {
        if (self.has_siblings()) {
            if (self.parent.?.child == self) {
                self.parent.?.child = self.next;
            }
            self.prev.?.next = self.next;
            self.next.?.prev = self.prev;
        } else {
            self.parent.?.child = self.parent;
        }
        if (self.has_children()) {
            self.parent.?.add_children(self.child.?);
        }
    }

    pub fn siblings_iterator(self: *TreeNode) Iterator {
        return Iterator.init(self);
    }

    pub fn entry(self: *TreeNode, comptime T: type, comptime member: []const u8) *T {
        return container_of(T, @intFromPtr(self), member);
    }
};

pub const Iterator = struct {
    curr: *TreeNode,
    head: *TreeNode,
    used: bool = false,

    pub fn init(head: *TreeNode) Iterator {
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
