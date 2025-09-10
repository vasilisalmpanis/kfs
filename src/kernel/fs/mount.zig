const lst = @import("../utils/list.zig");
const tree = @import("../utils/tree.zig");
const mutex = @import("../sched/mutex.zig");
const krn = @import("../main.zig");
const fs = @import("fs.zig");
const device = @import("drivers").device;

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
    count: krn.task.RefCount,

    pub fn mount(
        source: []const u8, // device
        target: []const u8, // directory
        fs_type: *fs.FileSystem
    ) !*Mount {
        var blk_dev: ?*device.Device = null;
        var dummy_file: ?*fs.File = null;
        if (!fs_type.virtual) {
            // 1. Check that device exists
            const device_path = try fs.path.resolve(source);
            errdefer device_path.release();
            const device_inode: *fs.Inode = device_path.dentry.inode;
            // 2. Check that its a block device
            if (device_inode.mode.type & fs.S_IFBLK == 0) {
                return krn.errors.PosixError.ENOTBLK;
            }
            // 3. Retrieve fops from driver

            dummy_file = try fs.File.new(device_path);
            errdefer krn.mm.kfree(dummy_file.?);
            try device_inode.fops.open(dummy_file.?, device_inode);
            errdefer dummy_file.?.ops.close(dummy_file.?);
            blk_dev = device_inode.dev;
        }
        //
        // For directory
        // 1. resolve to inode and check if its a directory
        // 2. Check if we can mount (?)
        var curr: fs.path.Path = undefined;
        var sb: *fs.SuperBlock = undefined;
        if (mountpoints != null) {
            const point = fs.path.remove_trailing_slashes(target);
            curr = try fs.path.resolve(point);
            defer curr.release();
            sb = try fs_type.ops.getSB(fs_type, dummy_file);
            errdefer sb.ref.unref();
        } else {
            sb = try fs_type.ops.getSB(fs_type, dummy_file);
            errdefer sb.ref.unref();
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
            mnt.count = krn.task.RefCount.init();
            mnt.count.ref();
            defer mnt_lock.unlock();
            if (mountpoints == null) {
                mountpoints = mnt;
            } else {
                curr.mnt.count.ref();
                curr.mnt.tree.addChild(&mnt.tree);
            }
            return mnt;
        } else {
            sb.ref.unref(); // later maybe something else
            return error.OutOfMemory;
        }
    }

    pub fn remove(self: *Mount) void {
        mnt_lock.lock();
        defer mnt_lock.unlock();
        if (self == mountpoints) {
            mountpoints = null;
        }
        const parent = self.tree.parent;
        self.tree.del();
        if (parent) |_parent| {
            const parent_mount = _parent.entry(Mount, "tree");
            parent_mount.count.unref();
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

    pub fn isGlobalRoot(self: *Mount) bool {
        return self == krn.task.initial_task.fs.root.mnt;
    }
};
