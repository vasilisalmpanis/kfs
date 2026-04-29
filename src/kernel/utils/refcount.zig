const std = @import("std");

pub const RefCount = struct {
    count: std.atomic.Value(usize),
    dropFn: *const fn (*RefCount) void,

    pub fn init() RefCount {
        return .{
            .count = std.atomic.Value(usize).init(0),
            .dropFn = RefCount.noop,
        };
    }

    pub fn get(rc: *RefCount) void {
        // no synchronization necessary; just updating a counter.
        _ = rc.count.fetchAdd(1, .monotonic);
    }

    pub fn put(rc: *RefCount) void {
        // release ensures code before unref() happens-before the
        // count is decremented as dropFn could be called by then.
        if (rc.getValue() == 0)
            @panic("Underflow\n");
        if (rc.count.fetchSub(1, .release) == 1) {
            // seeing 1 in the counter means that other unref()s have happened,
            // but it doesn't mean that uses before each unref() are visible.
            // The load acquires the release-sequence created by previous unref()s
            // in order to ensure visibility of uses before dropping.
            _ = rc.count.load(.acquire);
            (rc.dropFn)(rc);
        }
    }

    pub fn getValue(rc: *RefCount) usize {
        return rc.count.load(.monotonic);
    }

    pub fn isFree(rc: *RefCount) bool {
        return rc.getValue() == 0;
    }

    fn noop(rc: *RefCount) void {
        _ = rc;
    }
};