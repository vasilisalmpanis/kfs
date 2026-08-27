const std = @import("std");
const krn = @import("./main.zig");
const arch = @import("arch");

var prng: std.Random.Xoshiro256 = undefined;
var lock = krn.Spinlock.init();

pub fn init() void {
    prng = std.Random.Xoshiro256.init(arch.cpu.rdtsc() ^ 0x9e3779b97f4a7c15);
}

pub fn fill(buf: []u8) void {
    lock.lock();
    defer lock.unlock();
    prng.fill(buf);
}

pub fn mix(buf: []const u8) void {
    lock.lock();
    defer lock.unlock();
    var seed: u64 = prng.next();
    for (buf) |b| seed = (seed *% 0x100000001b3) ^ b;
    prng.s[0] ^= seed;
}
