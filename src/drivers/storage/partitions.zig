const std = @import("std");
const ata = @import("ata.zig");
const krn = @import("kernel");


pub const Partition = struct {
    name: []u8,
    PGUID: [16]u8,
    GUID: [16]u8,
    start_lba: u32 = 0,
    end_lba: u32 = 0,
};

const GPT_Prot = 0xee;

const MasterBootRecord = extern struct {
    boot: u8 = 0,
    starting_CHS: [3]u8 = .{0} ** 3,
    os_type: u8 = 0,
    ending_CHS: [3]u8 = .{0} ** 3,
    starting_LBA: u32 = 0,
    ening_LBA: u32 = 0,
};

const GUID = extern struct {
    a: u32,
    b: u16,
    c: u16,
    d: [8]u8,

    pub fn init() GUID {
        return GUID{
            .a = 0,
            .b = 0,
            .c = 0,
            .d = .{0} ** 8,
        };
    }

    pub fn toSting(self: *GUID, buff: []u8) !void {
        _ = try std.fmt.bufPrint(
            buff,
            "{X}-{X}-{X}-{X}-{X}",
            .{
                self.a,
                self.b,
                self.c,
                self.d[0..2],
                self.d[2..8],
            }
        );
    }
};

const GPTTableHeader = extern struct {
    signature: [8]u8 = .{0} ** 8,
    gpt_revision: u32 = 0,
    header_size: u32 = 0,
    crc32_sum: u32 = 0,
    _reserved: u32 = 0,
    header_LBA: u64 = 0,
    alt_header_LBA: u64 = 0,
    first_block: u64 = 0,
    last_block: u64 = 0,
    disk_GUID: GUID = GUID.init(),
    part_entry_arr_LBA: u64 = 0,
    part_entry_count: u32 = 0,
    part_entry_size: u32 = 0,
    part_entry_arr_CRC32: u32 = 0,
};


const GPTEntry = extern struct {
    PGUID: [16]u8,
    GUID: [16]u8,
    slba: u64,
    elba: u64,
    attrib: u64,
    name: [72]u8,

    pub fn eqlZero(self: *GPTEntry) bool {
        return std.mem.allEqual(u8, self.PGUID[0..16], 0);
    }
};


pub fn parsePartitionTable(drive: *ata.ATADrive) !void {
    try drive.readSectorsDMA(0, 1);
    var mbr_buff: [16]u8 align(4) = .{0} ** 16;
    @memcpy(
        mbr_buff[0..16],
        @as([*]u8, @ptrFromInt(drive.dma_buff_virt + 0x1BE))
    );
    const mbr: *MasterBootRecord = @ptrCast(&mbr_buff);
    krn.logger.DEBUG("MBR of {s}: {any}\n", .{drive.name, mbr.*});
    if (mbr.os_type == 0)
        return ;
    if (mbr.os_type == GPT_Prot) {
        try drive.readSectorsDMA(mbr.starting_LBA, 1);
        const header: *GPTTableHeader =  @ptrFromInt(drive.dma_buff_virt);

        // TO DO: fix GUID
        var guid_buf: [40]u8 = undefined;
        try header.disk_GUID.toSting(guid_buf[0..40]);
        if (std.mem.eql(u8, header.signature[0..8], "EFI PART")) {
            krn.logger.DEBUG("Disk {s} has partitions, header: {any}", .{
                guid_buf[0..36],
                header.*
            });
            // const part_num = header.part_entry_count;
            var curr_lba: u32 = @intCast(header.part_entry_arr_LBA);
            var offset: u32 = 0;
            const entry_size: u32 = header.part_entry_size;
            const part_count = header.part_entry_count;
            try drive.readSectorsDMA(@intCast(curr_lba), 1);
            var part_num: u32 = 0;
            for (0..part_count) |_| {
                if (offset >= ata.ATADrive.SECTOR_SIZE) {
                    curr_lba += 1;
                    try drive.readSectorsDMA(@intCast(curr_lba), 1);
                    offset = 0;
                }
                defer offset += entry_size;
                const first_entry: *GPTEntry = @ptrFromInt(drive.dma_buff_virt + offset);

                if (first_entry.eqlZero())
                    continue;
                part_num += 1;
                if (krn.mm.kmalloc(Partition)) |part| {
                    part.start_lba = @intCast(first_entry.slba);
                    part.end_lba = @intCast(first_entry.elba);
                    @memcpy(part.PGUID[0..16], first_entry.PGUID[0..16]);
                    @memcpy(part.GUID[0..16], first_entry.GUID[0..16]);
                    var len: u32 = 0;
                    for (0..72) |idx| {
                        if (first_entry.name[idx] != 0)
                            len += 1;
                    }
                    // const span = std.mem.span(@as([*:0]u8, @ptrCast(&first_entry.name)));
                    if (krn.mm.kmallocSlice(u8, len)) |name| {
                        var curr: u32 = 0;
                        for (0..72) |idx| {
                            if (first_entry.name[idx] != 0) {
                                name[curr] = first_entry.name[idx];
                                curr += 1;
                            }
                        }
                        krn.logger.INFO("partition name len {d} {s}\n", .{len, name});
                        part.name = name;
                        try drive.partitions.append(
                            krn.mm.kernel_allocator.allocator(),
                            part
                        );

                    }
                }
            }

        } else {
            krn.logger.ERROR("Wrong GPT magic of {s}!", .{drive.name});
            return krn.errors.PosixError.ENODEV;
        }
    }
}

fn parseGPT() void {}
