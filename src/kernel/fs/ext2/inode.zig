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

// File types
pub const EXT2_FT_UNKNOWN       = 0;	// Unknown File Type
pub const EXT2_FT_REG_FILE      = 1;	// Regular File
pub const EXT2_FT_DIR           = 2;	// Directory File
pub const EXT2_FT_CHRDEV        = 3;	// Character Device
pub const EXT2_FT_BLKDEV        = 4;	// Block Device
pub const EXT2_FT_FIFO          = 5;	// Buffer File
pub const EXT2_FT_SOCK          = 6;	// Socket File
pub const EXT2_FT_SYMLINK       = 7;	// Symbolic Link

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

    pub fn iterator(self: *Ext2DirEntry, block_size: u32) Ext2DirIterator{
        return Ext2DirIterator.init(self, block_size);
    }

    pub fn getName(self: *Ext2DirEntry) []const u8 {
        const addr: u32 = @intFromPtr(self) + @sizeOf(Ext2DirEntry);
        const name: [*]const u8 = @ptrFromInt(addr);
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

    pub fn setFileType(self: *Ext2DirEntry, mode: fs.UMode) void {
        switch (mode.type & fs.S_IFMT) {
            fs.S_IFREG => self.file_type = EXT2_FT_REG_FILE,
            fs.S_IFDIR => self.file_type = EXT2_FT_DIR,
            fs.S_IFLNK => self.file_type = EXT2_FT_SYMLINK,
            fs.S_IFBLK => self.file_type = EXT2_FT_BLKDEV,
            fs.S_IFCHR => self.file_type = EXT2_FT_CHRDEV,
            fs.S_IFIFO => self.file_type = EXT2_FT_FIFO,
            fs.S_IFSOCK => self.file_type = EXT2_FT_SOCK,
            else => self.file_type = EXT2_FT_UNKNOWN,
        }
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
            inode.base.size = 0;
            inode.base.dev_id = drv.device.dev_t{
                .major = 0,
                .minor = 0,
            };
            inode.base.fops = &file.Ext2FileOps;
            return &inode.base;
        }
        return error.OutOfMemory;
    }

    pub inline fn maxBlockIdx(self: *const Ext2Inode) u32 {
        const sb = self.base.sb.?.getImpl(
            ext2_sb.Ext2Super,
            "base"
        );
        return (
            self.data.i_blocks 
            / (@as(u32, 2) << @as(u5, @truncate(sb.data.s_log_block_size)))
        );
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
        for (0..ext2_dir_inode.maxBlockIdx()) |idx| {
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
        return kernel.errors.PosixError.ENOENT;
    }

    fn mkdir(base: *fs.Inode, parent: *fs.DEntry, name: []const u8, mode: fs.UMode) !*fs.DEntry {
        if (base.sb == null)
            return kernel.errors.PosixError.ENOENT;
        const cash_key = fs.DentryHash{
            .sb = @intFromPtr(parent.sb),
            .ino = base.i_no,
            .name = name,
        };
        if (fs.dcache.get(cash_key)) |_| {
            return kernel.errors.PosixError.EEXIST;
        }
        const dentry: *fs.DEntry = try base.ops.create(base, name, mode, parent);
        const new_inode: *Ext2Inode = dentry.inode.getImpl(Ext2Inode, "base");
        try new_inode.insertDirent(new_inode.base.i_no, ".", mode);
        try new_inode.insertDirent(base.i_no, "..", base.mode);
        new_inode.data.i_links_count = 2;
        new_inode.base.links = 2;
        new_inode.data.i_size = base.sb.?.block_size;
        new_inode.base.size = new_inode.data.i_size;
        try new_inode.iput();

        return dentry;
    }

    pub fn create(base: *fs.Inode, name: []const u8, mode: fs.UMode, parent: *fs.DEntry) !*fs.DEntry {
        if (base.sb == null)
            return kernel.errors.PosixError.ENOENT;
        if (!base.mode.isDir())
            return kernel.errors.PosixError.ENOTDIR;
        if (!base.mode.canWrite(base.uid, base.gid))
            return kernel.errors.PosixError.EACCES;

        // Lookup if file already exists.
        _ = base.ops.lookup(parent, name) catch |err| {
            if (err == kernel.errors.PosixError.ENOENT) {
                const parent_inode = base.getImpl(Ext2Inode, "base");
                const sb = base.sb.?.getImpl(ext2_sb.Ext2Super, "base");

                // Find block group
                var bgdt_idx = (parent_inode.base.i_no - 1) / sb.data.s_inodes_per_group;
                if (sb.bgdt[bgdt_idx].bg_free_inodes_count == 0) {
                    bgdt_idx = 0;
                    while (bgdt_idx < sb.bgdt.len) {
                        if (sb.bgdt[bgdt_idx].bg_free_inodes_count != 0)
                            break ;
                        bgdt_idx += 1;
                    }
                }
                if (bgdt_idx >= sb.bgdt.len)
                    return kernel.errors.PosixError.ENOSPC;

                const bgdt_entry = &sb.bgdt[bgdt_idx];

                const inode_bitmap = try sb.readBlocks(bgdt_entry.bg_inode_bitmap, 1);
                defer kernel.mm.kfree(inode_bitmap.ptr);

                // Find and reserve free inode number in bgdt
                var inode_no = bgdt_idx * sb.data.s_inodes_per_group + 1;
                const max_ino_idx = inode_no + sb.data.s_inodes_per_group;
                if (inode_no < sb.getFirstInodeIdx())
                    inode_no = sb.getFirstInodeIdx() + 1;
                while (inode_no < max_ino_idx) {
                    const bit = (inode_no - 1) % sb.data.s_inodes_per_group;
                    const byte = bit >> 3;
                    const mask: u8 = @as(u8, 1) << @intCast(bit & 7);
                    if (inode_bitmap[byte] & mask == 0) {
                        inode_bitmap[byte] |= mask;
                        _ = try sb.writeBuff(
                            bgdt_entry.bg_inode_bitmap,
                            inode_bitmap.ptr,
                            sb.base.block_size
                        );
                        sb.data.s_free_inodes_count -|= 1;
                        bgdt_entry.bg_free_inodes_count -|= 1;
                        if (mode.isDir()) {
                            bgdt_entry.bg_used_dirs_count += 1;
                        }
                        break ;
                    }
                    inode_no += 1;
                }
                if (inode_no >= max_ino_idx) {
                    return kernel.errors.PosixError.ENOSPC;
                }

                // Construct ext2 inode data
                const curr_seconds: u32 = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
                const new_inode_data: Ext2InodeData = Ext2InodeData{
                    .i_atime = curr_seconds,
                    .i_ctime = curr_seconds,
                    .i_mtime = curr_seconds,
                    .i_dtime = 0,
                    .i_uid = kernel.task.current.uid,
                    .i_gid = kernel.task.current.gid,
                    .i_mode = @bitCast(mode),
                    .i_size = 0,
                    .i_links_count = 1,
                    .i_generation = 0,
                    .i_flags = parent_inode.data.i_flags,
                    .i_faddr = 0,
                    .i_dir_acl = 0,
                    .i_file_acl = 0,
                    .osd1 = .{
                        .linux1 = .{
                            .l_i_reserved1 = 0,
                        }
                    },
                    .osd2 = .{
                        .linux2 = .{
                            .i_pad1 = 0,
                            .l_i_frag = 0,
                            .l_i_fsize = 0,
                            .l_i_gid_high = 0,
                            .l_i_reserved2 = 0,
                            .l_i_uid_high = 0,
                        }
                    },
                    .i_blocks = 0,
                    .i_block = .{0} ** EXT2_N_BLOCKS,
                };

                const new_inode = (try Ext2Inode.new(&sb.base)).getImpl(Ext2Inode, "base");
                errdefer kernel.mm.kfree(new_inode);
                new_inode.base.setCreds(
                    kernel.task.current.uid,
                    kernel.task.current.gid,
                    mode
                );
                new_inode.data = new_inode_data;
                new_inode.base.atime = new_inode.data.i_atime;
                new_inode.base.ctime = new_inode.data.i_ctime;
                new_inode.base.mtime = new_inode.data.i_mtime;
                new_inode.base.i_no = inode_no;
                try new_inode.iput();

                try parent_inode.insertDirent(
                    inode_no,
                    name,
                    mode
                );
                if (mode.isDir()) {
                    parent_inode.data.i_links_count += 1;
                    parent_inode.base.links += 1;
                }
                parent_inode.data.i_mtime = curr_seconds;
                parent_inode.base.mtime = curr_seconds;
                _ = try parent_inode.iput();
                try sb.writeGDTEntry(bgdt_idx);
                try sb.writeSuper();

                return try parent.new(name, &new_inode.base);
            }
            return err;
        };
        return kernel.errors.PosixError.EEXIST;
    }

    pub fn iput(self: *const Ext2Inode) !void {
        if (self.base.sb == null)
            return kernel.errors.PosixError.ENOENT;
        const sb: *ext2_sb.Ext2Super = self.base.sb.?.getImpl(ext2_sb.Ext2Super, "base");
        const i_no: u32 = self.base.i_no;
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

        rel_offset = rel_offset % sb.base.block_size;
        const size = @sizeOf(Ext2InodeData);
        const src: [*]const u8 = @ptrCast(&self.data);
        _ = try sb.writeBuffAtOffset(
            block,
            src,
            size,
            rel_offset
        );
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
        rel_offset = rel_offset % sb.base.block_size;
        const raw_inode: *Ext2InodeData = @ptrCast(@alignCast(&raw_buff[rel_offset]));
        inode.data = raw_inode.*;
        inode.base.i_no = i_no;
        inode.base.size = inode.data.i_size;
        inode.base.atime = inode.data.i_atime;
        inode.base.ctime = inode.data.i_ctime;
        inode.base.mtime = inode.data.i_mtime;
        inode.base.links = inode.data.i_links_count;
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

    pub fn allocBlock(self: *Ext2Inode) !u32 {
        if (self.base.sb == null)
            return kernel.errors.PosixError.ENOENT;
        const sb = self.base.sb.?.getImpl(ext2_sb.Ext2Super, "base");

        // Find free block in i_block
        var blk_idx: u32 = 0;
        while (self.data.i_block[blk_idx] != 0) {
            blk_idx += 1;
            if (blk_idx > 11) {
                kernel.logger.ERROR("TODO: allocBlock(): implement indirect blocks", .{});
                return kernel.errors.PosixError.ENOSPC;
            }
            if (blk_idx >= EXT2_N_BLOCKS)
                return kernel.errors.PosixError.ENOSPC;
        }

        // Find block group
        var bgdt_idx = (self.base.i_no - 1) / sb.data.s_inodes_per_group;
        if (sb.bgdt[bgdt_idx].bg_free_blocks_count == 0) {
            bgdt_idx = 0;
            while (bgdt_idx < sb.bgdt.len) {
                if (sb.bgdt[bgdt_idx].bg_free_blocks_count != 0)
                    break ;
                bgdt_idx += 1;
            }
        }
        if (bgdt_idx >= sb.bgdt.len)
            return kernel.errors.PosixError.ENOSPC;

        const block = try sb.getFreeBlock(bgdt_idx);
        self.data.i_blocks += sb.base.block_size / 512;
        self.data.i_block[blk_idx] = block;
        const curr_seconds: u32 = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
        sb.data.s_wtime = curr_seconds;
        self.data.i_mtime = curr_seconds;
        self.base.mtime = curr_seconds;
        try self.iput();
        try sb.writeGDTEntry(bgdt_idx);
        try sb.writeSuper();
        return block;
    }

    pub fn insertDirent(
        self: *Ext2Inode,
        child_ino: u32,
        name: []const u8,
        mode: fs.UMode,
    ) !void {
        if (self.base.sb == null)
            return kernel.errors.PosixError.ENOENT;
        const sb = self.base.sb.?.getImpl(ext2_sb.Ext2Super, "base");
        if (name.len > 255)
            return kernel.errors.PosixError.EINVAL;
        var blk_idx: u32 = 0;
        while (blk_idx <= 11) {
            var pbn = self.data.i_block[blk_idx];
            if (pbn == 0) {
                pbn = try self.allocBlock();
                blk_idx = 11; // to exit loop
            }
            const blk = try sb.readBlocks(pbn, 1);
            defer kernel.mm.kfree(blk.ptr);

            var off: u32 = 0;
            var new_entry_size = @sizeOf(Ext2DirEntry) + name.len;
            if (new_entry_size % 4 != 0) {
                new_entry_size += 4 - (new_entry_size % 4);
            }
            while (off < sb.base.block_size) {
                var old_de: *Ext2DirEntry = @ptrFromInt(@intFromPtr(blk.ptr) + off);
                var spare: u32 = 0;
                var used_size: u32 = 0;
                if (old_de.rec_len == 0 and off != 0)
                    return kernel.errors.PosixError.EINVAL;
                if (old_de.rec_len == 0 and off == 0) {
                    spare = sb.base.block_size;
                    used_size = 0;
                } else {
                    if (old_de.inode == 0) {
                        used_size = 0;
                        spare = old_de.rec_len;
                    } else {
                        used_size = @sizeOf(Ext2DirEntry) + old_de.name_len;
                        if (used_size % 4 != 0)
                            used_size += 4 - (used_size % 4);
                        spare = @as(u32, old_de.rec_len) - used_size;
                    }
                }

                if (spare >= new_entry_size) {
                    // shrink current
                    if (used_size != 0)
                        old_de.rec_len = @intCast(used_size);
                    // new entry
                    var new_entry: *Ext2DirEntry = @ptrFromInt(@intFromPtr(old_de) + used_size);
                    new_entry.inode = child_ino;
                    new_entry.rec_len = @intCast(spare);
                    new_entry.name_len = @intCast(name.len);
                    new_entry.setFileType(mode);
                    const name_start: [*]u8 = @ptrFromInt(@intFromPtr(new_entry) + @sizeOf(Ext2DirEntry));
                    @memcpy(name_start[0..name.len], name);
                    _ = try sb.writeBuff(pbn, blk.ptr, sb.base.block_size);
                    return;
                }
                off += old_de.rec_len;
            }
            blk_idx += 1;
        }
    }

    pub fn removeDirent(self: *Ext2Inode, target_name: []const u8, child_ino: u32) !void {
        const sb: *fs.SuperBlock = if (self.base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        if (!self.base.mode.isDir()) {
            return kernel.errors.PosixError.ENOTDIR;
        }
        const ext2_super = sb.getImpl(ext2_sb.Ext2Super, "base");
        var prev_entry: ?*Ext2DirEntry = null;

        var limit: u32 =  self.maxBlockIdx();
        if (limit > 11)
            limit = 11;
        for (0..limit + 1) |idx| {
            const block: u32 = self.data.i_block[idx];
            // TODO: read dir entries of other blocks too.
            const block_slice: []u8 = try ext2_super.readBlocks(block, 1);
            defer kernel.mm.kfree(block_slice.ptr);
            const ext_dir: ?*Ext2DirEntry = @ptrCast(@alignCast(block_slice.ptr));
            if (ext_dir) |first| {
                var it = first.iterator(ext2_super.base.block_size);
                while (it.next()) |curr_dir| {
                    const name = curr_dir.getName();
                    if (curr_dir.inode == child_ino and std.mem.eql(u8, target_name, name)) {
                        if (prev_entry) |en| {
                            en.rec_len += curr_dir.rec_len;
                            curr_dir.inode = 0;
                            curr_dir.rec_len = 0;
                            curr_dir.file_type = 0;
                            const array: [*]u8 = @constCast(name.ptr);
                            @memset(array[0..name.len], 0);
                            curr_dir.name_len = 0;
                            _ = try ext2_super.writeBuff(block, block_slice.ptr, block_slice.len);
                            return ;
                        } else {
                            // TODO: Free this block
                            kernel.logger.ERROR("Removing . or .. from ext2 dir\n", .{});
                            return kernel.errors.PosixError.EIO;
                        }
                    }
                    prev_entry = curr_dir;
                }
            }
        }
        return kernel.errors.PosixError.ENOENT;
    }

    pub fn chmod(base: *fs.Inode, mode: fs.UMode) !void {
        const ext2_inode = base.getImpl(Ext2Inode, "base");
        try base.chmod(mode);
        ext2_inode.data.i_mtime = base.mtime;
        ext2_inode.data.i_mode.copyPerms(base.mode);
        try ext2_inode.iput();
    }


    fn symlink(parent: *fs.DEntry, name: []const u8, target: []const u8) !void {
        const new_link =  try parent.inode.ops.create(
            parent.inode,
            name,
            fs.UMode.link(),
            parent
        );
        const ext2_inode = new_link.inode.getImpl(Ext2Inode, "base");
        if (target.len >= 60) {
            const pbn = try ext2_inode.allocBlock();
            const ext2_super = parent.sb.getImpl(ext2_sb.Ext2Super, "base");
            const res = try ext2_super.writeBuff(pbn, target.ptr, target.len);
            if (res != target.len) {
                return kernel.errors.PosixError.EIO;
            }
        } else {
            const target_buf: [*]u8 = @ptrCast(&ext2_inode.data.i_block);
            @memset(target_buf[0..60], 0);
            @memcpy(target_buf[0..target.len], target);
        }
        try ext2_inode.iput();
    }

    fn link(parent: *fs.DEntry, name: []const u8, target: fs.path.Path) !void {
        const parent_ext2_inode = parent.inode.getImpl(Ext2Inode, "base");
        try parent_ext2_inode.insertDirent(target.dentry.inode.i_no, name, target.dentry.inode.mode);
        const target_ext2_inode = target.dentry.inode.getImpl(Ext2Inode, "base");
        target_ext2_inode.base.links += 1;
        target_ext2_inode.data.i_links_count += 1;
        const curr_seconds: u32 = @intCast(kernel.cmos.toUnixSeconds(kernel.cmos));
        target_ext2_inode.data.i_mtime = curr_seconds;
        target_ext2_inode.base.mtime = curr_seconds;
        try target_ext2_inode.iput();
        _ = try parent.new(name, target.dentry.inode);
    }

    fn readlink(base: *fs.Inode, buf: [*]u8, size: usize) !u32 {
        const sb = if (base.sb) |_s| _s else return kernel.errors.PosixError.EINVAL;
        const ext2_inode = base.getImpl(Ext2Inode, "base");
        const ext2_s = sb.getImpl(ext2_sb.Ext2Super, "base");
        if (ext2_inode.data.i_blocks > 0) {
            const lbn = try ext2_s.resolveLbn(ext2_inode, 0);
            const block = try ext2_s.readBlocks(lbn, 1);
            const span: []u8 = std.mem.span(@as([*:0]u8, @ptrCast(block.ptr)));

            var to_write: u32 = size;
            if (span.len < size)
                to_write = span.len;
            @memcpy(buf[0..to_write], span[0..to_write]);
            return to_write;
        } else {
            const block: [*:0]u8 = @ptrCast(&ext2_inode.data.i_block);
            const span: []u8 = std.mem.span(block);

            var to_write: u32 = size;
            if (span.len < size)
                to_write = span.len;
            @memcpy(buf[0..to_write], span[0..to_write]);
            return to_write;
        }
    }

    fn unlink(parent: *fs.Inode, dentry: *fs.DEntry) !void {
        const ext2_parent_inode = parent.getImpl(Ext2Inode, "base");
        const ext2_child_inode = dentry.inode.getImpl(Ext2Inode, "base");
        try ext2_parent_inode.removeDirent(dentry.name, dentry.inode.i_no);

        ext2_child_inode.base.links -= 1;
        ext2_child_inode.data.i_links_count -= 1;
        try ext2_child_inode.iput();
    }

    fn isEmptyDir(dir: Ext2Inode) bool {
        if (dir.base.sb == null)
            return false;
        const ext2_super = dir.base.sb.?.getImpl(ext2_sb.Ext2Super, "base");
        for (0..dir.maxBlockIdx()) |idx| {
            // TODO: resolve blocks
            if (idx >= 12)
                break;
            const block: u32 = dir.data.i_block[idx];
            const block_slice: []u8 = ext2_super.readBlocks(block, 1) catch {
                return false;
            };
            defer kernel.mm.kfree(block_slice.ptr);
            const ext_dir: ?*Ext2DirEntry = @ptrCast(@alignCast(block_slice.ptr));
            if (ext_dir) |first| {
                var it = first.iterator(ext2_super.base.block_size);
                while (it.next()) |curr_ent| {
                    if (curr_ent.rec_len == 0) {
                        kernel.logger.WARN("ext2 0 rec_len directory entry {s}\n", .{first.getName()});
                        return false;
                    }
                    if (curr_ent.inode != 0) {
                        const name = curr_ent.getName();
                        if (name[0] != '.')
                            return false;
                        if (name.len > 2)
                            return false;
                        if (name.len < 2) {
                            if (curr_ent.inode != dir.base.i_no)
                                return false;
                        } else if (name[1] != '.') {
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }

    fn rmdir(current: *fs.DEntry, parent: *fs.DEntry) !void {
        if (!current.inode.mode.isDir())
            return kernel.errors.PosixError.ENOTDIR;
        if (current.inode.links > 2)
            return kernel.errors.PosixError.ENOTEMPTY;
        const current_inode = current.inode.getImpl(Ext2Inode, "base");
        if (!current_inode.isEmptyDir())
            return kernel.errors.PosixError.ENOTEMPTY;

        const parent_inode = parent.inode.getImpl(Ext2Inode, "base");
        try parent_inode.removeDirent(current.name, current.inode.i_no);
        parent_inode.base.links -= 1;
        parent_inode.data.i_links_count -= 1;
        try parent_inode.iput();

        current_inode.data.i_links_count = 0;
        current_inode.base.links = 0;
        try current_inode.iput();
        current.release();
    }

    fn updateDotDotIno(self: *Ext2Inode, i_no: u32) !void {
        if (self.base.sb == null)
            return kernel.errors.PosixError.EINVAL;
        const ext2_super = self.base.sb.?.getImpl(ext2_sb.Ext2Super, "base");
        for (0..self.maxBlockIdx()) |idx| {
            if (idx >= 12)
                break;
            const block: u32 = self.data.i_block[idx];
            const block_slice: []u8 = try ext2_super.readBlocks(block, 1);
            defer kernel.mm.kfree(block_slice.ptr);
            const ext_dir: ?*Ext2DirEntry = @ptrCast(@alignCast(block_slice.ptr));
            if (ext_dir) |first| {
                var it = first.iterator(ext2_super.base.block_size);
                while (it.next()) |curr_ent| {
                    if (curr_ent.rec_len == 0) {
                        kernel.logger.WARN(
                            "ext2 0 rec_len directory entry {s}\n",
                            .{first.getName()}
                        );
                        return kernel.errors.PosixError.EIO;
                    }
                    if (curr_ent.inode != 0) {
                        const name = curr_ent.getName();
                        if (name.len == 2 and std.mem.eql(u8, name, "..")) {
                            curr_ent.inode = i_no;
                            _ = try ext2_super.writeBuff(
                                block, block_slice.ptr, block_slice.len
                            );
                            return ;
                        }
                    }
                }
            }
        }
    }

    pub fn rename(
        old_parent: *fs.DEntry, old: *fs.DEntry,
        new_parent: *fs.DEntry, new_name: []const u8
    ) !void {
        if (old.ref.getValue() > old.tree.childrenCount() + 1)
            return kernel.errors.PosixError.EBUSY;
        const new_d: ?*fs.DEntry = new_parent.inode.ops.lookup(
            new_parent,
            new_name
        ) catch |err| blk: {
            switch (err) {
                kernel.errors.PosixError.ENOENT => break :blk null,
                else => return err,
            }
        };
        const new_parent_ino_ext2 = new_parent.inode.getImpl(Ext2Inode, "base");
        if (new_d) |_d| {
            const ino_ext2 = _d.inode.getImpl(Ext2Inode, "base");
            if (_d.inode.mode.isDir() and !ino_ext2.isEmptyDir())
                return kernel.errors.PosixError.ENOTEMPTY;
            if (_d.ref.getValue() > old.tree.childrenCount() + 1)
                return kernel.errors.PosixError.EBUSY;
            ino_ext2.base.links -= 1;
            ino_ext2.data.i_links_count -= 1;
            if (ino_ext2.base.mode.isDir()) {
                ino_ext2.base.links -= 1;
                ino_ext2.data.i_links_count -= 1;
            }
            try new_parent_ino_ext2.removeDirent(new_name, _d.inode.i_no);
            try ino_ext2.iput();
            _d.release();
        }
        const old_parent_ino_ext2 = old_parent.inode.getImpl(Ext2Inode, "base");
        if (old_parent.inode != new_parent.inode and old.inode.mode.isDir()) {
            const ext2_ino = old.inode.getImpl(Ext2Inode, "base");
            try ext2_ino.updateDotDotIno(new_parent_ino_ext2.base.i_no);
            old_parent_ino_ext2.base.links -= 1;
            old_parent_ino_ext2.data.i_links_count -= 1;
            try old_parent_ino_ext2.iput();
            new_parent_ino_ext2.base.links += 1;
            new_parent_ino_ext2.data.i_links_count += 1;
            try new_parent_ino_ext2.iput();
        }
        try old_parent_ino_ext2.removeDirent(old.name, old.inode.i_no);
        try new_parent_ino_ext2.insertDirent(old.inode.i_no, new_name, old.inode.mode);
        old.release();
    }

    fn chown(base: *fs.Inode, uid: u32, gid: u32) !void {
        const ext2_inode = base.getImpl(Ext2Inode, "base");
        if (uid > 0xFFFF or gid > 0xFFFF)
            return kernel.errors.PosixError.EINVAL;
        ext2_inode.base.uid = uid;
        ext2_inode.data.i_uid = @intCast(uid);
        ext2_inode.base.gid = gid;
        ext2_inode.data.i_gid = @intCast(gid);
        try ext2_inode.iput();
    }
};

const ext2_inode_ops = fs.InodeOps {
    .create = Ext2Inode.create,
    .mknod = null,
    .lookup = Ext2Inode.lookup,
    .mkdir = Ext2Inode.mkdir,
    .get_link = Ext2Inode.getLink,
    .chmod = Ext2Inode.chmod,
    .link = Ext2Inode.link,
    .symlink = Ext2Inode.symlink,
    .unlink = Ext2Inode.unlink,
    .readlink = Ext2Inode.readlink,
    .rmdir = Ext2Inode.rmdir,
    .rename = Ext2Inode.rename,
    .chown = Ext2Inode.chown,
};
