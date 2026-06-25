const std = @import("std");

pub const PosixError = error{
    // Basic system errors
    EPERM,     // 1 - Operation not permitted
    ENOENT,    // 2 - No such file or directory
    ESRCH,     // 3 - No such process
    EINTR,     // 4 - Interrupted system call
    EIO,       // 5 - I/O error
    ENXIO,     // 6 - No such device or address
    E2BIG,     // 7 - Argument list too long
    ENOEXEC,   // 8 - Exec format error
    EBADF,     // 9 - Bad file number
    ECHILD,    // 10 - No child processes
    EAGAIN,    // 11 - Try again
    ENOMEM,    // 12 - Out of memory
    EACCES,    // 13 - Permission denied
    EFAULT,    // 14 - Bad address
    ENOTBLK,   // 15 - Block device required
    EBUSY,     // 16 - Device or resource busy
    EEXIST,    // 17 - File exists
    EXDEV,     // 18 - Cross-device link
    ENODEV,    // 19 - No such device
    ENOTDIR,   // 20 - Not a directory
    EISDIR,    // 21 - Is a directory
    EINVAL,    // 22 - Invalid argument
    ENFILE,    // 23 - File table overflow
    EMFILE,    // 24 - Too many open files
    ENOTTY,    // 25 - Not a typewriter
    ETXTBSY,   // 26 - Text file busy
    EFBIG,     // 27 - File too large
    ENOSPC,    // 28 - No space left on device
    ESPIPE,    // 29 - Illegal seek
    EROFS,     // 30 - Read-only file system
    EMLINK,    // 31 - Too many links
    EPIPE,     // 32 - Broken pipe
    EDOM,      // 33 - Math argument out of domain of func
    ERANGE,    // 34 - Math result not representable

    // Extended errors
    EDEADLK,         // 35 - Resource deadlock would occur
    ENAMETOOLONG,    // 36 - File name too long
    ENOLCK,          // 37 - No record locks available
    ENOSYS,          // 38 - Invalid system call number
    ENOTEMPTY,       // 39 - Directory not empty
    ELOOP,           // 40 - Too many symbolic links encountered
    // Note: EWOULDBLOCK = EAGAIN, so we alias EAGAIN
    _RESERVED_41,
    ENOMSG,          // 42 - No message of desired type
    EIDRM,           // 43 - Identifier removed
    ECHRNG,          // 44 - Channel number out of range
    EL2NSYNC,        // 45 - Level 2 not synchronized
    EL3HLT,          // 46 - Level 3 halted
    EL3RST,          // 47 - Level 3 reset
    ELNRNG,          // 48 - Link number out of range
    EUNATCH,         // 49 - Protocol driver not attached
    ENOCSI,          // 50 - No CSI structure available
    EL2HLT,          // 51 - Level 2 halted
    EBADE,           // 52 - Invalid exchange
    EBADR,           // 53 - Invalid request descriptor
    EXFULL,          // 54 - Exchange full
    ENOANO,          // 55 - No anode
    EBADRQC,         // 56 - Invalid request code
    EBADSLT,         // 57 - Invalid slot
    // Reserved: 58 = EDEADLOCK (aliased to EDEADLK)
    _RESERVED_58,
    EBFONT,          // 59 - Bad font file format
    ENOSTR,          // 60 - Device not a stream
    ENODATA,         // 61 - No data available
    ETIME,           // 62 - Timer expired
    ENOSR,           // 63 - Out of streams resources
    ENONET,          // 64 - Machine is not on the network
    ENOPKG,          // 65 - Package not installed
    EREMOTE,         // 66 - Object is remote
    ENOLINK,         // 67 - Link has been severed
    EADV,            // 68 - Advertise error
    ESRMNT,          // 69 - Srmount error
    ECOMM,           // 70 - Communication error on send
    EPROTO,          // 71 - Protocol error
    EMULTIHOP,       // 72 - Multihop attempted
    EDOTDOT,         // 73 - RFS specific error
    EBADMSG,         // 74 - Not a data message
    EOVERFLOW,       // 75 - Value too large for defined data type
    ENOTUNIQ,        // 76 - Name not unique on network
    EBADFD,          // 77 - File descriptor in bad state
    EREMCHG,         // 78 - Remote address changed
    ELIBACC,         // 79 - Can not access a needed shared library
    ELIBBAD,         // 80 - Accessing a corrupted shared library
    ELIBSCN,         // 81 - lib section in a.out corrupted
    ELIBMAX,         // 82 - Attempting to link in too many shared libraries
    ELIBEXEC,        // 83 - Cannot exec a shared library directly
    EILSEQ,          // 84 - Illegal byte sequence
    ERESTART,        // 85 - Interrupted system call should be restarted
    ESTRPIPE,        // 86 - Streams pipe error
    EUSERS,          // 87 - Too many users

    // Socket errors
    ENOTSOCK,        // 88 - Socket operation on non-socket
    EDESTADDRREQ,    // 89 - Destination address required
    EMSGSIZE,        // 90 - Message too long
    EPROTOTYPE,      // 91 - Protocol wrong type for socket
    ENOPROTOOPT,     // 92 - Protocol not available
    EPROTONOSUPPORT, // 93 - Protocol not supported
    ESOCKTNOSUPPORT, // 94 - Socket type not supported
    EOPNOTSUPP,      // 95 - Operation not supported on transport endpoint
    EPFNOSUPPORT,    // 96 - Protocol family not supported
    EAFNOSUPPORT,    // 97 - Address family not supported by protocol
    EADDRINUSE,      // 98 - Address already in use
    EADDRNOTAVAIL,   // 99 - Cannot assign requested address
    ENETDOWN,        // 100 - Network is down
    ENETUNREACH,     // 101 - Network is unreachable
    ENETRESET,       // 102 - Network dropped connection because of reset
    ECONNABORTED,    // 103 - Software caused connection abort
    ECONNRESET,      // 104 - Connection reset by peer
    ENOBUFS,         // 105 - No buffer space available
    EISCONN,         // 106 - Transport endpoint is already connected
    ENOTCONN,        // 107 - Transport endpoint is not connected
    ESHUTDOWN,       // 108 - Cannot send after transport endpoint shutdown
    ETOOMANYREFS,    // 109 - Too many references: cannot splice
    ETIMEDOUT,       // 110 - Connection timed out
    ECONNREFUSED,    // 111 - Connection refused
    EHOSTDOWN,       // 112 - Host is down
    EHOSTUNREACH,    // 113 - No route to host
    EALREADY,        // 114 - Operation already in progress
    EINPROGRESS,     // 115 - Operation now in progress
    ESTALE,          // 116 - Stale file handle
    EUCLEAN,         // 117 - Structure needs cleaning
    ENOTNAM,         // 118 - Not a XENIX named type file
    ENAVAIL,         // 119 - No XENIX semaphores available
    EISNAM,          // 120 - Is a named type file
    EREMOTEIO,       // 121 - Remote I/O error
    EDQUOT,          // 122 - Quota exceeded
    ENOMEDIUM,       // 123 - No medium found
    EMEDIUMTYPE,     // 124 - Wrong medium type
    ECANCELED,       // 125 - Operation Canceled
    ENOKEY,          // 126 - Required key not available
    EKEYEXPIRED,     // 127 - Key has expired
    EKEYREVOKED,     // 128 - Key has been revoked
    EKEYREJECTED,    // 129 - Key was rejected by service
    EOWNERDEAD,      // 130 - Owner died
    ENOTRECOVERABLE, // 131 - State not recoverable
    ERFKILL,         // 132 - Operation not possible due to RF-kill
    EHWPOISON,       // 133 - Memory page has hardware error

    // From here on these errors belong only in kernel space
    ERESTARTSYS,     // 134 - KFS internal error for restarting syscalls
    ENOIOCTLCMD,     // 135 - KFS internal error for continuing ioctl
};


pub fn errorToCode(err: PosixError) u16 {
    const code = std.meta.stringToEnum(ErrorCode, @errorName(err))
        orelse return 0;
    return @intFromEnum(code);
}

pub fn codeToError(code: u16) ?PosixError {
    const err_code: ErrorCode = @enumFromInt(code);
    switch (err_code) {
        _ => return null,
        else => {},
    }
    const err_name = @tagName(err_code);

    inline for (@typeInfo(PosixError).error_set.?) |e| {
        if (std.mem.eql(u8, e.name, err_name)) {
            return @field(PosixError, e.name);
        }
    }
    return null;
}

pub inline fn toErrno(err: PosixError) i32 {
    return -@as(i32, @intCast(errorToCode(err)));
}

pub inline fn fromErrno(err: i32) PosixError {
    if (err > 0)
    return PosixError.EINVAL;
    const code: u16 = @intCast(-err);
    return codeToError(code) orelse PosixError.EINVAL;
}

const ErrorCode = enum(u16) {
    ESUCCESS = 0,
    EPERM = 1,
    ENOENT = 2,
    ESRCH = 3,
    EINTR = 4,
    EIO = 5,
    ENXIO = 6,
    E2BIG = 7,
    ENOEXEC = 8,
    EBADF = 9,
    ECHILD = 10,
    EAGAIN = 11,
    ENOMEM = 12,
    EACCES = 13,
    EFAULT = 14,
    ENOTBLK = 15,
    EBUSY = 16,
    EEXIST = 17,
    EXDEV = 18,
    ENODEV = 19,
    ENOTDIR = 20,
    EISDIR = 21,
    EINVAL = 22,
    ENFILE = 23,
    EMFILE = 24,
    ENOTTY = 25,
    ETXTBSY = 26,
    EFBIG = 27,
    ENOSPC = 28,
    ESPIPE = 29,
    EROFS = 30,
    EMLINK = 31,
    EPIPE = 32,
    EDOM = 33,
    ERANGE = 34,
    EDEADLK = 35,
    ENAMETOOLONG = 36,
    ENOLCK = 37,
    ENOSYS = 38,
    ENOTEMPTY = 39,
    ELOOP = 40,
    ENOMSG = 42,
    EIDRM = 43,
    ECHRNG = 44,
    EL2NSYNC = 45,
    EL3HLT = 46,
    EL3RST = 47,
    ELNRNG = 48,
    EUNATCH = 49,
    ENOCSI = 50,
    EL2HLT = 51,
    EBADE = 52,
    EBADR = 53,
    EXFULL = 54,
    ENOANO = 55,
    EBADRQC = 56,
    EBADSLT = 57,
    EBFONT = 59,
    ENOSTR = 60,
    ENODATA = 61,
    ETIME = 62,
    ENOSR = 63,
    ENONET = 64,
    ENOPKG = 65,
    EREMOTE = 66,
    ENOLINK = 67,
    EADV = 68,
    ESRMNT = 69,
    ECOMM = 70,
    EPROTO = 71,
    EMULTIHOP = 72,
    EDOTDOT = 73,
    EBADMSG = 74,
    EOVERFLOW = 75,
    ENOTUNIQ = 76,
    EBADFD = 77,
    EREMCHG = 78,
    ELIBACC = 79,
    ELIBBAD = 80,
    ELIBSCN = 81,
    ELIBMAX = 82,
    ELIBEXEC = 83,
    EILSEQ = 84,
    ERESTART = 85,
    ESTRPIPE = 86,
    EUSERS = 87,
    ENOTSOCK = 88,
    EDESTADDRREQ = 89,
    EMSGSIZE = 90,
    EPROTOTYPE = 91,
    ENOPROTOOPT = 92,
    EPROTONOSUPPORT = 93,
    ESOCKTNOSUPPORT = 94,
    EOPNOTSUPP = 95,
    EPFNOSUPPORT = 96,
    EAFNOSUPPORT = 97,
    EADDRINUSE = 98,
    EADDRNOTAVAIL = 99,
    ENETDOWN = 100,
    ENETUNREACH = 101,
    ENETRESET = 102,
    ECONNABORTED = 103,
    ECONNRESET = 104,
    ENOBUFS = 105,
    EISCONN = 106,
    ENOTCONN = 107,
    ESHUTDOWN = 108,
    ETOOMANYREFS = 109,
    ETIMEDOUT = 110,
    ECONNREFUSED = 111,
    EHOSTDOWN = 112,
    EHOSTUNREACH = 113,
    EALREADY = 114,
    EINPROGRESS = 115,
    ESTALE = 116,
    EUCLEAN = 117,
    ENOTNAM = 118,
    ENAVAIL = 119,
    EISNAM = 120,
    EREMOTEIO = 121,
    EDQUOT = 122,
    ENOMEDIUM = 123,
    EMEDIUMTYPE = 124,
    ECANCELED = 125,
    ENOKEY = 126,
    EKEYEXPIRED = 127,
    EKEYREVOKED = 128,
    EKEYREJECTED = 129,
    EOWNERDEAD = 130,
    ENOTRECOVERABLE = 131,
    ERFKILL = 132,
    EHWPOISON = 133,
    ENSRNODATA = 160,
    ENSRFORMERR = 161,
    ENSRSERVFAIL = 162,
    ENSRNOTFOUND = 163,
    ENSRNOTIMP = 164,
    ENSRREFUSED = 165,
    ENSRBADQUERY = 166,
    ENSRBADNAME = 167,
    ENSRBADFAMILY = 168,
    ENSRBADRESP = 169,
    ENSRCONNREFUSED = 170,
    ENSRTIMEOUT = 171,
    ENSROF = 172,
    ENSRFILE = 173,
    ENSRNOMEM = 174,
    ENSRDESTRUCTION = 175,
    ENSRQUERYDOMAINTOOLONG = 176,
    ENSRCNAMELOOP = 177,
    _,
};
