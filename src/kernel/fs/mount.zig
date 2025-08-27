const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const mutex = @import("../sched/mutex.zig");
const krn = @import("../main.zig");
const fs = @import("fs.zig");

pub var mountpoints: ?*Mount = null;

// Root fs is passed as a parameter from the boot loader.
// This will be mountpoint '/'. All others are children
// of this.

pub var mnt_lock = mutex.Mutex.init();

// TODO: mount cache for faster lookup.

pub const Mount = struct {
    sb: *fs.SuperBlock,
    root: *fs.DEntry,
    tree: tree.TreeNode,

    pub fn mount(
        source: []const u8, // device
        target: []const u8, // directory
        fs_type: *fs.FileSystem) !*Mount {
        // For device
        // 1. Check that device exists
        // 2. Check that its a block device
        // 3. Take device major and retrieve fops from driver
        //
        // For directory
        // 1. resolve to inode and check if its a directory
        // 2. Check if we can mount (?)
        var curr: fs.path.Path = undefined;
        const sb: *fs.SuperBlock = try fs_type.ops.getSB(fs_type, source);
        errdefer sb.ref.unref();
        if (mountpoints != null) {
            const point = fs.path.remove_trailing_slashes(target);
            curr = try fs.path.resolve(point);
        } else {
            curr.dentry = fs.DEntry.alloc(target, sb, sb.root.inode) catch {
                return error.OutOfMemory;
            };
            errdefer curr.release();
        }
        if (krn.mm.kmalloc(Mount)) |mnt| {
            mnt.root = curr.dentry;
            mnt.sb = sb;
            mnt.tree.setup();
            mnt_lock.lock();
            defer mnt_lock.unlock();
            if (mountpoints == null) {
                mountpoints = mnt;
            } else {
                curr.mnt.tree.addChild(&mnt.tree);
            }
            return mnt;
        } else {
            sb.ref.unref(); // later maybe something else
            return error.OutOfMemory;
        }
    }

    pub fn checkChildMount(self: *Mount, dentry: *fs.DEntry) ?*Mount {
        if (self.tree.hasChildren()) {
            var it = self.tree.child.?.siblingsIterator();
            while (it.next()) |i| {
                const m = i.curr.entry(Mount, "tree");
                if (m.root == dentry) {
                    return m;
                }
            }
        }
        return null;
    }
};
