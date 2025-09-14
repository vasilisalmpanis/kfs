const std = @import("std");
const fs = @import("../fs.zig");
const kernel = fs.kernel;
const file = @import("file.zig");
const ext2_sb = @import("./super.zig");
const drv = @import("drivers");

// Special inode numbers
pub const EXT2_BAD_INO	          = 1; // Bad blocks inode
pub const EXT2_ROOT_INO	          = 2; // Root inode
pub const EXT2_BOOT_LOADER_INO      = 5; // Boot loader inode
pub const EXT2_UNDEL_DIR_INO        = 6; // Undelete directory inode
pub const EXT2_N_BLOCKS             = 15;

/// ext2 on-disk inode (little-endian fields). Classic 128-byte layout.
/// Use `le16/le32` helpers below if you need host-endian values.
///
///
pub const Ext2DirIterator = struct {
    current: *Ext2DirEntry = undefined,
    sum: u32 = 0,
    block_size: u32 = 0,

    pub fn init(start: *Ext2DirEntry, block_size: u32) Ext2DirIterator {
        return Ext2DirIterator{
            .current = start,
            .sum = 0,
            .block_size = block_size,
        };
    }

    pub inline fn isLast(self: *Ext2DirIterator) bool {
        if (self.sum >= self.block_size) return true;
        if (self.current.rec_len == 0) return true;
        return false;
    }

    pub fn next(self: *Ext2DirIterator) ?*Ext2DirEntry {
        if (self.isLast())
            return null;
        const current: *Ext2DirEntry = self.current;
        self.current = self.current.getNext();
        self.sum += current.rec_len;
        return current;
    }
};

pub const Ext2DirEntry = extern struct {
    inode: u32,       // inode number
    rec_len: u16,     // total size of this entry
    name_len: u8,     // length of name
    file_type: u8,    // (ext2 rev>=1)
                      //
                      //
    pub fn iterator(self: *Ext2DirEntry, block_size: u32) Ext2DirIterator{
        return Ext2DirIterator.init(self, block_size);
    }

    pub fn getName(self: *Ext2DirEntry) []u8 {
        const addr: u32 = @intFromPtr(self) + @sizeOf(Ext2DirEntry);
        const name: [*]u8 = @ptrFromInt(addr);
        return name[0..self.name_len];
    }


    // FIXME: incorrect alignment in some cases.
    pub fn getNext(self: *Ext2DirEntry) *Ext2DirEntry {
        const addr: u32 = @intFromPtr(self) + self.rec_len;
        if (addr % 4 != 0) {
            @panic("TODO: fix alignment with ext2\n");
        }
        return @ptrFromInt(addr);
    }
};

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

    pub fn new(sb: *fs.SuperBlock) !*fs.Inode {
        if (kernel.mm.kmalloc(Ext2Inode)) |inode| {
            inode.base.setup(sb);
            inode.base.ops = &ext2_inode_ops;
            inode.base.size = 50;
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.base.fops = &file.Ext2FileOps;
            return &inode.base;
        }
        return error.OutOfMemory;
    }

    fn lookup(dir: *fs.DEntry, name: []const u8) !*fs.DEntry {
        if (!dir.inode.mode.isDir()) {
            return kernel.errors.PosixError.ENOTDIR;
        }
        if (!dir.inode.mode.canExecute(
            dir.inode.uid,
            dir.inode.gid
        )) {
            return kernel.errors.PosixError.EACCES;
        }
        const key: fs.DentryHash = fs.DentryHash{
            .sb = @intFromPtr(dir.sb),
            .ino = dir.inode.i_no,
            .name = name,
        };
        if (fs.dcache.get(key)) |entry| {
            return entry;
        }
        // Get from disk
        const ext2_dir_inode = dir.inode.getImpl(Ext2Inode, "base");
        const ext2_super = dir.sb.getImpl(ext2_sb.Ext2Super, "base");
        for (0..ext2_dir_inode.data.i_blocks) |idx| {
            const block: u32 = ext2_dir_inode.data.i_block[idx];
            // TODO: read dir entries of other blocks too.
            const block_slice: []u8 = try ext2_super.readBlocks(block, 1);
            defer kernel.mm.kfree(block_slice.ptr);
            const ext_dir: ?*Ext2DirEntry = @ptrCast(@alignCast(block_slice.ptr));
            if (ext_dir) |first| {
                var it = first.iterator(ext2_super.base.block_size);
                while (it.next()) |curr_dir| {
                    const curr_name = curr_dir.getName();
                    if (std.mem.eql(u8, name, curr_name)) {
                        const new_inode = (try Ext2Inode.new(dir.sb)).getImpl(Ext2Inode, "base");
                        errdefer kernel.mm.kfree(new_inode);
                        try new_inode.iget(ext2_super, curr_dir.inode);
                        new_inode.base.i_no = curr_dir.inode;
                        return try dir.new(name, &new_inode.base);
                    }
                }
            }
        }
        return error.InodeNotFound;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        _ = base;
        _ = parent;
        _ = mode;
        kernel.logger.ERROR("Ext2 mkdir: not implemented! Unable to create {s}!", .{name});
        return kernel.errors.PosixError.ENONET;
    }

    pub fn create(base: *fs.Inode, name: []const u8, _: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        if (!base.mode.isDir())
            return error.NotDirectory;
        if (!base.mode.canWrite(base.uid, base.gid))
            return error.Access;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch {
            return kernel.errors.PosixError.EINVAL;
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


        const raw_buff: []u8 = try sb.readBlocks(block, 1);
        rel_offset &= (sb.base.block_size - 1);
        const raw_inode: *Ext2InodeData = @ptrCast(@alignCast(&raw_buff[rel_offset]));
        inode.data = raw_inode.*;
        inode.base.size = inode.data.i_size;
        inode.base.size = raw_inode.i_size;
        inode.base.setCreds(
            raw_inode.i_uid | (@as(u32, raw_inode.osd2.linux2.l_i_uid_high) << 16),
            raw_inode.i_gid | (@as(u32, raw_inode.osd2.linux2.l_i_gid_high) << 16),
            raw_inode.i_mode,
        );
        kernel.mm.kfree(raw_buff.ptr);
    }

    pub fn getLink(base: *fs.Inode, resulting_link: *[]u8) !void {
        const sb = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        const ext2_inode = base.getImpl(Ext2Inode, "base");
        const ext2_s = sb.getImpl(ext2_sb.Ext2Super, "base");
        if (ext2_inode.data.i_blocks > 0) {
            const lbn = try ext2_s.resolveLbn(ext2_inode, 0);
            const block = try ext2_s.readBlocks(lbn, 1);
            const span: []u8 = std.mem.span(@as([*:0]u8, @ptrCast(block.ptr)));
            if (span.len > resulting_link.len)
                return kernel.errors.PosixError.EINVAL;
            @memcpy(resulting_link.*[0..span.len], span);
            resulting_link.len = span.len;
            return ;
        } else {
            const block: [*:0]u8 = @ptrCast(&ext2_inode.data.i_block);
            const span: []u8 = std.mem.span(block);
            if (span.len > resulting_link.len)
                return kernel.errors.PosixError.EINVAL;
            @memcpy(resulting_link.*[0..span.len], span);
            resulting_link.len = span.len;
            return ;
        }
    }
};

const ext2_inode_ops = fs.InodeOps {
    .create = Ext2Inode.create,
    .mknod = null,
    .lookup = Ext2Inode.lookup,
    .mkdir = Ext2Inode.mkdir,
    .get_link = Ext2Inode.getLink,
};
