const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const ext2_sb = @import("./super.zig");

// Special inode numbers
pub const EXT2_BAD_INO	          = 1; // Bad blocks inode
pub const EXT2_ROOT_INO	          = 2; // Root inode
pub const EXT2_BOOT_LOADER_INO      = 5; // Boot loader inode
pub const EXT2_UNDEL_DIR_INO        = 6; // Undelete directory inode


pub const Ext2Inode = struct {
    base: fs.Inode,
    buff: [50]u8,

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(Ext2Inode)) |inode| {
            inode.base.setup(sb);
            inode.base.ops = &ext2_inode_ops;
            inode.base.size = 50;
            inode.base.fops = &file.Ext2FileOps;
            inode.buff = .{0} ** 50;
            return &inode.base;
        }
        return error.OutOfMemory;
    }

    fn lookup(dir: *fs.Inode, name: []const u8) !*fs.DEntry {
        const key: fs.DentryHash = fs.DentryHash{
            .ino = dir.i_no,
            .name = name,
        };
        if (fs.dcache.get(key)) |entry| {
            return entry;
        }
        return error.InodeNotFound;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        const cash_key = fs.DentryHash{
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return error.Exists;
        }
        var new_inode = try Ext2Inode.new(base.sb);
        new_inode.mode = mode;
        errdefer kernel.mm.kfree(new_inode);
        var new_dentry = try fs.DEntry.alloc(name, base.sb, new_inode);
        errdefer kernel.mm.kfree(new_dentry);
        parent.tree.addChild(&new_dentry.tree);
        try fs.dcache.put(cash_key, new_dentry);
        return new_dentry;
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        if (base.mode.type != fs.S_IFDIR)
            return error.NotDirectory;
        if (!base.mode.isWriteable())
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(base, name) catch {
            const new_inode = try Ext2Inode.new(base.sb);
            errdefer kernel.mm.kfree(new_inode);
            new_inode.mode = mode;
            var dent = try parent.new(name, new_inode);
            dent.ref.ref();
            return dent;
        };
        return error.Exists;
    }

    pub fn iget(_: *Ext2Inode, sb: *ext2_sb.Ext2Super, i_no: u32) !void {
        if (
            (i_no != EXT2_ROOT_INO and i_no < sb.getFirstInodeIdx())
            or (i_no > sb.data.s_inodes_count)
        ) {
            return kernel.errors.PosixError.EINVAL;
        }
        const block_group = (i_no - 1) / sb.data.s_inodes_per_group;
        const gd = sb.bgdt[block_group];
        const rel_offset = ((i_no - 1) % sb.data.s_inodes_per_group) * sb.data.s_inode_size;

        const block_size: u32 = @as(u32, 1024) << @as(u5, @truncate(sb.data.s_log_block_size));
        const table_byte_off: u32 = gd.bg_inode_table * block_size;
        const abs_offset = table_byte_off + rel_offset;

        if (kernel.mm.kmallocArray(u8, sb.data.s_inode_size)) |raw_buff| {
            errdefer kernel.mm.kfree(raw_buff);
            @memset(raw_buff[0..sb.data.s_inode_size], 0);
            sb.base.dev_file.?.pos = abs_offset;
            _  = try sb.base.dev_file.?.ops.read(sb.base.dev_file.?, raw_buff, sb.data.s_inode_size);
            kernel.logger.INFO("inode: \n{any}", .{raw_buff[0..sb.data.s_inode_size]});
        }
    }
};

const ext2_inode_ops = fs.InodeOps {
    .create = Ext2Inode.create,
    .mknod = null,
    .lookup = Ext2Inode.lookup,
    .mkdir = Ext2Inode.mkdir,
};
