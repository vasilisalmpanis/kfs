const containerOf = @import("./list.zig").containerOf;

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

    pub fn hasChildren(self: *TreeNode) bool {
        return self.child != self;
    }

    pub fn hasSiblings(self: *TreeNode) bool {
        return self.next != self;
    }

    pub fn addSibling(self: *TreeNode, new: *TreeNode) void {
        new.next = self;
        new.prev = self.prev;

        self.prev.?.next = new;
        self.prev = new;
        new.parent = self.parent;
    }

    pub fn addChild(self: *TreeNode, new: *TreeNode) void {
        if (self.hasChildren()) {
            self.child.?.addSibling(new);
        } else {
            self.child = new;
        }
        new.parent = self;
    }

    pub fn setParent(self: *TreeNode, parent: *TreeNode) void {
        var it = self.siblingsIterator();
        while (it.next()) |i| {
            i.curr.parent = parent;
        }
    }

    pub fn addChildren(self: *TreeNode, new: *TreeNode) void {
        new.setParent(self);
        if (self.hasChildren()) {
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
        if (self.hasSiblings()) {
            if (self.parent.?.child == self) {
                self.parent.?.child = self.next;
            }
            self.prev.?.next = self.next;
            self.next.?.prev = self.prev;
        } else {
            self.parent.?.child = self.parent;
        }
        if (self.hasChildren()) {
            self.parent.?.addChildren(self.child.?);
        }
    }

    pub fn siblingsIterator(self: *TreeNode) Iterator {
        return Iterator.init(self);
    }

    pub fn entry(self: *TreeNode, comptime T: type, comptime member: []const u8) *T {
        return containerOf(T, @intFromPtr(self), member);
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

    pub fn isLast(self: *Iterator) bool {
        return self.curr.next == self.head;
    }
};
