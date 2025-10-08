const kernel = @import("kernel");
const tsk = kernel.task;

pub const ThreadHandler = *const fn (arg: ?*const anyopaque) callconv(.c) i32;

const WrapperInfo = struct {
    callback: ThreadHandler,
    arg: ?*const anyopaque,
};
pub fn wrapper(arg: ?*const anyopaque) i32 {
    const info: *WrapperInfo = @ptrCast(@constCast(@alignCast(arg)));
    return info.callback(info.arg);
}

pub fn kthreadCreate(f: ThreadHandler, arg: ?*const anyopaque) callconv(.c) ?*tsk.Task {
    const info = WrapperInfo{
        .callback = f,
        .arg = arg,
    };
    const task = kernel.kthreadCreate(wrapper, &info) catch {
        return null;
    };
    return task;
}

pub fn kthreadStop(thread: *tsk.Task) callconv(.c) i32 {
    return kernel.kthreadStop(thread);
}
