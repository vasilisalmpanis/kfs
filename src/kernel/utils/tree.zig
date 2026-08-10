
pub const TreeNode = struct {
    parent: ?*TreeNode  = null,
    child: ?*TreeNode   = null,
    next: ?*TreeNode    = null,
    prev: ?*TreeNode    = null,

    pub fn init() TreeNode {
        return .{};
    }

    pub fn setup(self: *TreeNode) void {
        self.parent = null;
        self.child = null;
        self.next = self;
        self.prev = self;
    }

    pub fn hasChildren(self: *TreeNode) bool {
        return self.child != null;
    }

    pub fn childrenCount(self: *TreeNode) u32 {
        var count: u32 = 0;
        if (self.child) |ch| {
            var it = ch.siblingsIterator();
            while (it.next()) |_| {
                count += 1;
            }
        }
        return count;
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
        } else if (self.parent) |prnt| {
            prnt.child = null;
        }
        if (self.hasChildren()) {
            if (self.parent) |prnt| {
                prnt.addChildren(self.child.?);
            }
        }
        self.setup();
    }

    pub fn siblingsIterator(self: *TreeNode) Iterator {
        return Iterator.init(self);
    }

    pub fn treeIterator(self: *TreeNode) TreeIterator {
        return TreeIterator.init(self);
    }

    pub fn entry(self: *TreeNode, comptime T: type, comptime member: []const u8) *T {
        return @alignCast(@fieldParentPtr(member, self));
    }
};

pub const TreeIterator = struct {
    root: *TreeNode,
    next_node: ?*TreeNode,

    pub fn init(root: *TreeNode) TreeIterator {
        return .{
            .root = root,
            .next_node = root.child,
        };
    }

    pub fn next(self: *TreeIterator) ?*TreeNode {
        const current = self.next_node orelse
            return null;

        if (current.child) |child| {
            self.next_node = child;
            return current;
        }

        var node = current;
        self.next_node = null;
        while (node != self.root) {
            const parent = node.parent.?;
            if (node.next.? != parent.child.?) {
                self.next_node = node.next;
                break;
            }
            node = parent;
        }
        return current;
    }
};

pub const Iterator = struct {
    curr: *TreeNode,
    head: ?*TreeNode,
    used: bool = false,

    pub fn init(head: *TreeNode) Iterator {
        return .{
            .curr = head,
            .head = head,
        };
    }

    pub fn next(self: *Iterator) ?*Iterator {
        if (self.head) |head| {
            if (self.curr == head and !self.used) {
                self.used = true;
                return self;
            }
            if (self.curr.next == null)
                return null;
            self.curr = self.curr.next.?;
            if (self.curr == head)
                return null;
            return self;
        }
        return null;
    }

    pub fn isLast(self: *Iterator) bool {
        return self.head == null or self.curr.next == self.head.?;
    }

    pub fn reset(self: *Iterator, removed: *TreeNode) void {
        if (self.head == null)
            return;
        if (self.head.? == removed) {
            if (self.head.?.hasSiblings()) {
                const new_head = self.head.?.next.?;
                self.head = new_head;
                self.curr = new_head;
                self.used = false;
            } else {
                self.head = null;
            }
        }
    }
};

test "descendants iterator traverses depth first" {
    const testing = @import("std").testing;

    var nodes: [6]TreeNode = .{TreeNode.init()} ** 6;
    for (&nodes) |*node| {
        node.setup();
    }

    nodes[0].addChild(&nodes[1]);
    nodes[0].addChild(&nodes[2]);
    nodes[1].addChild(&nodes[3]);
    nodes[1].addChild(&nodes[4]);
    nodes[2].addChild(&nodes[5]);

    const expected = [_]*TreeNode{
        &nodes[1],
        &nodes[3],
        &nodes[4],
        &nodes[2],
        &nodes[5],
    };
    var index: usize = 0;
    var it = nodes[0].treeIterator();
    while (it.next()) |node| : (index += 1) {
        try testing.expect(index < expected.len);
        try testing.expectEqual(expected[index], node);
    }
    try testing.expectEqual(expected.len, index);
}
