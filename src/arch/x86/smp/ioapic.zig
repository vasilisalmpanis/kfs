const apic = @import("./apic.zig");
const krn = @import("kernel");
const arch = @import("../main.zig");

pub var controller: ?Controller = null;

const IOAPICID : u8  = 0x00;
const IOAPICVER : u8 = 0x01;
const IOAPICARB : u8 = 0x02;

const REDIR_BASE: u32   = 0x10;
const MASKED: u32       = 1 << 16;

const LOWEST_PRIORITY: u32 = 0b001;
const PHYSICAL: u1  = 0;
const LOGICAL: u1   = 1;

const RedirectionEntry = packed struct {
    vector       : u8,
    delvMode     : u3,
    destMode     : u1,
    delvStatus   : u1,
    pinPolarity  : u1,
    remoteIRR    : u1,
    triggerMode  : u1,
    mask         : u1,
    reserved     : u39,
    destination  : u8,
};

pub const SourceOverride = struct {
    gsi: u32,
    active_low: bool,
    level_triggered: bool,
};

pub var overrides: [16]?SourceOverride = .{ null } ** 16;

pub fn registerOverride(entry: *align(1) apic.IOAPICInterruptSourceOverride) void {
    if (entry.irq_source >= overrides.len)
        return;
    overrides[entry.irq_source] = SourceOverride{
        .gsi = entry.gsi,
        .active_low = (entry.flags & 0b11) == 0b11,
        .level_triggered = (entry.flags >> 2) & 0b11 == 0b11,
    };
}

pub const Controller = struct {
    io_apic_id:         u8,
    gsi_base:           u32,
    version:            u32 = undefined,
    redir_entr_count:   u32 = undefined,
    regs:               [*] volatile u32,
    lock:               krn.Spinlock = krn.Spinlock.init(),

    pub fn init(entry: *align(1) apic.IOAPIC) !Controller {
        const ioapic_addr = try krn.mm.mapPhys(
            entry.io_apic_addr,
            1,
            .{ .present = true, .writable = true, .cache_disable = true}
        );
        var res = Controller{
            .io_apic_id = entry.io_apic_id,
            .gsi_base = entry.gsi_base,
            .regs = @ptrFromInt(ioapic_addr),
            .lock = krn.Spinlock.init(),
        };
        res.version = res.read(IOAPICVER);
        res.redir_entr_count = ((res.version >> 16) & 0xFF) + 1;
        return res;
    }

    pub fn read(self: *const Controller, offset: u8) u32 {
        // tell IOREGSEL which offset we want to access
        self.regs[0] = offset;
        return self.regs[4];
    }

    pub fn write(self: *const Controller, offset: u8, val: u32) void {
        // tell IOREGSEL which offset we want to access
        self.regs[0] = offset;
        self.regs[4] = val;
    }

    fn setRoute(
        self: *Controller,
        pin: u32,
        irq_num: u8,
        active_low: bool,
        level_triggered: bool,
        masked: bool,
    ) void {
        const entry = RedirectionEntry{
            .vector = irq_num,
            .delvMode = LOWEST_PRIORITY,
            .destMode = LOGICAL,
            .delvStatus = 0,
            .pinPolarity = @intFromBool(active_low),
            .remoteIRR = 0,
            .triggerMode = @intFromBool(level_triggered),
            .mask = @intFromBool(masked),
            .reserved = 0,
            .destination = @as(u8, 1) << @as(u3, @intCast(arch.smp.boot_cpu_apicid)),
        };
        const raw: u64 = @bitCast(entry);
        const low_reg: u8 = @intCast(REDIR_BASE + pin * 2);

        // Check in the future if we will need to access this
        // function in atomic context. If yes use irq_disable
        // instead.
        self.lock.lock();
        defer self.lock.unlock();

        self.write(low_reg, self.read(low_reg) | MASKED);
        self.write(low_reg + 1, @truncate(raw >> 32));
        self.write(low_reg, @truncate(raw));
    }

    pub fn maskIrq(self: *Controller, irq: u32, vector: u8) !void {
        if (irq >= self.gsi_base and irq < self.gsi_base + self.redir_entr_count) {
            const pin = irq - self.gsi_base;
            self.setRoute(
                pin,
                vector,
                false,
                false,
                true,
            );
            return;
        }
        return krn.errors.PosixError.EINVAL;
    }

    pub fn maskAll(self: *Controller) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (0..self.redir_entr_count) |pin| {
            const reg: u8 = 0x10 + @as(u8, @intCast(pin)) * 2;
            self.write(reg, MASKED);
            self.write(reg + 1, 0);
        }
    }


    pub fn setIRQ(self: *Controller, irq: u32, vector: u8) !void {
        var gsi: u32 = irq;
        if (gsi < self.gsi_base)
            return krn.errors.PosixError.EINVAL;
        if (gsi >= self.gsi_base + self.redir_entr_count)
            return krn.errors.PosixError.EINVAL;

        var level_triggered: bool = false;
        var active_low: bool = false;
        const pin = gsi - self.gsi_base;

        if (gsi < overrides.len) {
            if (overrides[gsi]) |ovr| {
                gsi = ovr.gsi;
                active_low = ovr.active_low;
                level_triggered = ovr.level_triggered;
            }
        }

        self.setRoute(
            pin,
            vector,
            active_low,
            level_triggered,
            false
        );
    }
};

pub fn init(ioapic_entry: *align(1) apic.IOAPIC) !void {
    controller = try Controller.init(ioapic_entry);
}
