const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const ext2_sb = @import("./super.zig");

// Special inode numbers
pub const EXT2_BAD_INO	          = 1; // Bad blocks inode
pub const EXT2_ROOT_INO	          = 2; // Root inode
pub const EXT2_BOOT_LOADER_INO      = 5; // Boot loader inode
pub const EXT2_UNDEL_DIR_INO        = 6; // Undelete directory inode
pub const EXT2_N_BLOCKS             = 15;

/// ext2 on-disk inode (little-endian fields). Classic 128-byte layout.
/// Use `le16/le32` helpers below if you need host-endian values.
pub const Ext2InodeData = extern struct {
    i_mode:        fs.UMode,              // file mode
    i_uid:         u16,                   // low 16 bits of uid
    i_size:        u32,                   // size in bytes (low 32)
    i_atime:       u32,                   // atime (unix epoch)
    i_ctime:       u32,                   // ctime
    i_mtime:       u32,                   // mtime
    i_dtime:       u32,                   // deletion time
    i_gid:         u16,                   // low 16 bits of gid
    i_links_count: u16,                   // link count
    i_blocks:      u32,                   // 512-byte sectors, not fs blocks
    i_flags:       u32,                   // flags

    osd1: extern union {
        linux1: extern struct { l_i_reserved1: u32 },
        hurd1:  extern struct { h_i_translator: u32 },
        masix1: extern struct { m_i_reserved1: u32 },
    },

    i_block: [EXT2_N_BLOCKS]u32,          // 12 direct + 3 indirect (S, D, T)

    i_generation: u32,                    // file version (NFS)
    i_file_acl:   u32,                    // file ACL
    i_dir_acl:    u32,                    // dir ACL or high 32 bits of size
    i_faddr:      u32,                    // fragment address

    osd2: extern union {
        linux2: extern struct {
            l_i_frag:       u8,          // fragment number
            l_i_fsize:      u8,          // fragment size
            i_pad1:         u16,
            l_i_uid_high:   u16,         // high 16 bits of uid (rev>=1)
            l_i_gid_high:   u16,         // high 16 bits of gid (rev>=1)
            l_i_reserved2:  u32,
        },
        hurd2: extern struct {
            h_i_frag:       u8,
            h_i_fsize:      u8,
            h_i_mode_high:  u16,
            h_i_uid_high:   u16,
            h_i_gid_high:   u16,
            h_i_author:     u32,
        },
        masix2: extern struct {
            m_i_frag:       u8,
            m_i_fsize:      u8,
            m_pad1:         u16,
            m_i_reserved2:  [2]u32,
        },
    },
};

pub const Ext2Inode = struct {
    data: Ext2InodeData,
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
            .sb = @intFromPtr(dir.sb),
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
            .sb = @intFromPtr(parent.sb),
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

    pub fn iget(inode: *Ext2Inode, sb: *ext2_sb.Ext2Super, i_no: u32) !void {
        if (
            (i_no != EXT2_ROOT_INO and i_no < sb.getFirstInodeIdx())
            or (i_no > sb.data.s_inodes_count)
        ) {
            return kernel.errors.PosixError.EINVAL;
        }
        const block_group = (i_no - 1) / sb.data.s_inodes_per_group;
        const gd = sb.bgdt[block_group];
        var rel_offset = ((i_no - 1) % sb.data.s_inodes_per_group) * sb.data.s_inode_size;
        const block = gd.bg_inode_table + (rel_offset >> @as(u5, @truncate(sb.data.s_log_block_size + 10)));
        const block_size: u32 = @as(u32, 1024) << @as(u5, @truncate(sb.data.s_log_block_size));
        kernel.logger.INFO("Block size {d}\n", .{block_size});


        if (kernel.mm.kmallocArray(u8, block_size)) |raw_buff| {
            errdefer kernel.mm.kfree(raw_buff);
            @memset(raw_buff[0..block_size], 0);
            sb.base.dev_file.?.pos = block_size * block;
            _  = try sb.base.dev_file.?.ops.read(sb.base.dev_file.?, raw_buff, block_size);
            rel_offset &= (block_size - 1);
            const raw_inode: *Ext2InodeData = @ptrCast(@alignCast(&raw_buff[rel_offset]));
            inode.data = raw_inode.*;
            return ;
        } else {
            kernel.logger.INFO("Ext2: Allocate buffer: Out of Memory", .{});
        }
    }
};

const ext2_inode_ops = fs.InodeOps {
    .create = Ext2Inode.create,
    .mknod = null,
    .lookup = Ext2Inode.lookup,
    .mkdir = Ext2Inode.mkdir,
};
