// Auto-generated kernel type interface
const std = @import("std");

pub const arch = struct {
    pub const io = struct {
    };

    pub const system = struct {
    };

    pub const gdt = struct {
        pub const GdtEntry = packed struct {
            limit_low : u16,
            base_low : u16,
            base_middle : u8,
            access : u8,
            granularity : u8,
            base_high : u8,
        };

    };

    pub const multiboot = struct {
        pub const MultibootInfo1 = packed struct {
            flags : u32,
            mem_lower : u32,
            mem_upper : u32,
            boot_device : u32,
            cmdline : u32,
            mods_count : u32,
            mods_addr : u32,
            syms_0 : u32,
            syms_1 : u32,
            syms_2 : u32,
            syms_3 : u32,
            mmap_length : u32,
            mmap_addr : u32,
            drives_length : u32,
            drives_addr : u32,
            config_table : u32,
            boot_loader_name : u32,
            apm_table : u32,
            vbe_control_info : u32,
            vbe_mode_info : u32,
            vbe_mode : u16,
            vbe_interface_seg : u16,
            vbe_interface_off : u16,
            vbe_interface_len : u16,
            framebuffer_addr : u64,
            framebuffer_pitch : u32,
            framebuffer_width : u32,
            framebuffer_height : u32,
            framebuffer_bpp : u8,
            framebuffer_type : u8,
        };

        pub const Multibo2otMemoryMap1 = struct {
            size : u32,
            addr : [2]u32,
            len : [2]u32,
            type : u32,
        };

        pub const FramebufferInfo1 = struct {
            address : u32,
            width : u32,
            height : u32,
            pitch : u32,
        };

        pub const Header = struct {
            total_size : u32,
            reserved : u32,
        };

        pub const Tag = struct {
            type : u32,
            size : u32,
        };

        pub const TagBootCommandLine = struct {
            type : u32= 1,
            size : u32,
        };

        pub const TagBootLoaderName = struct {
            type : u32= 2,
            size : u32,
        };

        pub const TagModules = struct {
            type : u32= 3,
            size : u32,
            start : u32,
            end : u32,
        };

        pub const TagBasicMemInfo = struct {
            type : u32= 4,
            size : u32,
            mem_lower : u32,
            mem_upper : u32,
        };

        pub const TagBIOSBootDevice = struct {
            type : u32= 5,
            size : u32,
            biosdev : u32,
            partition : u32,
            sub_partition : u32,
        };

        pub const MemMapEntry = struct {
            base_addr : u64,
            length : u64,
            type : u32,
            reserved : u32,
        };

        pub const TagMemoryMap = struct {
            type : u32= 6,
            size : u32,
            entry_size : u32,
            entry_version : u32,
        };

        pub const TagVBEInfo = struct {
            type : u32= 7,
            size : u32,
            mode : u16,
            interface_seg : u16,
            interface_off : u16,
            interface_len : u16,
            control_info : [512]u8,
            mode_info : [256]u8,
        };

        pub const TagFrameBufferInfo = struct {
            type : u32= 8,
            size : u32,
            addr : u64,
            pitch : u32,
            width : u32,
            height : u32,
            bpp : u8,
            fb_type : u8,
            reserved : u8,
        };

        pub const TagELFSymbols = struct {
            type : u32= 9,
            size : u32,
            num : u16,
            entsize : u16,
            shndx : u16,
            reserved : u16,
        };

        pub const TagAPMTable = struct {
            type : u32= 10,
            size : u32,
            version : u16,
            cseg : u16,
            offset : u32,
            cseg_16 : u16,
            dseg : u16,
            flags : u16,
            cseg_len : u16,
            cseg_16_len : u16,
            dseg_len : u16,
        };

        pub const TagEFI32SysTablePointer = struct {
            type : u32= 11,
            size : u32,
            pointer : u32,
        };

        pub const TagEFI64SysTablePointer = struct {
            type : u32= 12,
            size : u32,
            pointer : u64,
        };

        pub const TagSMBIOSTables = struct {
            type : u32= 13,
            size : u32,
            major : u8,
            minor : u8,
            reserved : [6]u8,
        };

        pub const TagACPIOldRSDP = struct {
            type : u32= 14,
            size : u32,
        };

        pub const TagACPINewRSDP = struct {
            type : u32= 15,
            size : u32,
        };

        pub const TagNetInfo = struct {
            type : u32= 16,
            size : u32,
        };

        pub const TagEFIMemMap = struct {
            type : u32= 17,
            size : u32,
            descriptor_size : u32,
            descriptor_version : u32,
        };

        pub const TagEFIBootNotTerm = struct {
            type : u32= 18,
            size : u32,
        };

        pub const TagEFI32HandlePtr = struct {
            type : u32= 19,
            size : u32,
            pointer : u32,
        };

        pub const TagEFI64HandlePtr = struct {
            type : u32= 20,
            size : u32,
            pointer : u64,
        };

        pub const TagImageLoadBasePhysAddr = struct {
            type : u32= 21,
            size : u32,
            load_base_addr : u32,
        };

        pub const Multiboot = struct {
            addr : u32,
            header : *arch.multiboot.Header,
            curr_tag : ?*arch.multiboot.Tag= null,
            tag_addresses : [22]u32,
        };

    };

    pub const vmm = struct {
        pub const PagingFlags = packed struct {
            present : bool= true,
            writable : bool= true,
            user : bool= false,
            write_through : bool= false,
            cache_disable : bool= false,
            accessed : bool= false,
            dirty : bool= false,
            huge_page : bool= false,
            global : bool= false,
            available : u3= 0,
        };

        pub const VASpair = struct {
            virt : u32= 0,
            phys : u32= 0,
        };

        pub const VMM = struct {
            pmm : *arch.pmm.PMM,
        };

    };

    pub const pmm = struct {
        pub const PMM = struct {
            free_area : []u32,
            index : u32,
            size : u64,
            begin : u32,
            end : u32,
        };

    };

    pub const idt = struct {
        pub extern fn exceptionHandler(*arch.Regs)void;
        pub extern fn irqHandler(*arch.Regs)*arch.Regs;
    };

    pub const Regs = struct {
        gs : u32,
        fs : u32,
        es : u32,
        ds : u32,
        edi : u32,
        esi : u32,
        ebp : u32,
        esp : u32,
        ebx : u32,
        edx : u32,
        ecx : u32,
        eax : i32,
        int_no : u32,
        err_code : u32,
        eip : u32,
        cs : u32,
        eflags : u32,
        useresp : u32,
        ss : u32,
    };

    pub const cpu = struct {

        pub const TSS = packed struct {
            back_link : u16,
            _padding0 : u16,
            esp0 : u32,
            ss0 : u16,
            _padding1 : u16,
            esp1 : u32,
            ss1 : u16,
            _padding2 : u16,
            esp2 : u32,
            ss2 : u16,
            _padding3 : u16,
            cr3 : u32,
            eip : u32,
            eflags : u32,
            eax : u32,
            ecx : u32,
            edx : u32,
            ebx : u32,
            esp : u32,
            ebp : u32,
            esi : u32,
            edi : u32,
            es : u16,
            cs : u16,
            ss : u16,
            ds : u16,
            fs : u16,
            gs : u16,
            ldt : u16,
            trace : u16,
            bitmap : u16,
        };

    };

};

pub const kernel = struct {
    pub const screen = struct {
        pub const Screen = struct {
            tty : [1]drivers.platform.tty.TTY,
            frmb : drivers.framebuffer.FrameBuffer,
        };

    };

    pub const mm = struct {
        pub const proc_mm = struct {
            pub const MAP_TYPE = enum(u4) {
                SHARED = 1,
                PRIVATE = 2,
                SHARED_VALIDATE = 3,
            };


            pub const MAP = packed struct {
                TYPE : kernel.mm.proc_mm.MAP_TYPE,
                FIXED : bool= false,
                ANONYMOUS : bool= false,
                _32BIT : bool= false,
                _7 : u1= 0,
                GROWSDOWN : bool= false,
                _9 : u2= 0,
                DENYWRITE : bool= false,
                EXECUTABLE : bool= false,
                LOCKED : bool= false,
                NORESERVE : bool= false,
                POPULATE : bool= false,
                NONBLOCK : bool= false,
                STACK : bool= false,
                HUGETLB : bool= false,
                SYNC : bool= false,
                FIXED_NOREPLACE : bool= false,
                _21 : u5= 0,
                UNINITIALIZED : bool= false,
                _ : u5= 0,
            };

            pub const VMA = struct {
                start : u32,
                end : u32,
                mm : ?*kernel.mm.proc_mm.MM,
                flags : kernel.mm.proc_mm.MAP,
                prot : u32,
                list : kernel.list.ListHead,
            };

            pub const MM = struct {
                stack_top : u32= 0,
                stack_bottom : u32= 0,
                code : u32= 0,
                data : u32= 0,
                arg_start : u32= 0,
                arg_end : u32= 0,
                env_start : u32= 0,
                env_end : u32= 0,
                bss : u32= 0,
                heap : u32= 0,
                brk_start : u32= 0,
                brk : u32= 0,
                vas : u32= 0,
                vmas : ?*kernel.mm.proc_mm.VMA= null,
            };

        };






        pub const KernelAllocator = struct {
        };

    };

    pub const irq = struct {
        pub extern fn registerHandler(u32, *const anyopaque)void;
        pub extern fn unregisterHandler(u32)void;
    };

    pub const exceptions = struct {
        pub const Exceptions = enum(u5) {
            DivisionError = 0,
            Debug = 1,
            NonMaskableInterrupt = 2,
            Breakpoint = 3,
            Overflow = 4,
            BoundRangeExceeded = 5,
            InvalidOpcode = 6,
            DeviceNotAvailable = 7,
            DoubleFault = 8,
            CoprocessorSegmentOverrun = 9,
            InvalidTSS = 10,
            SegmentNotPresent = 11,
            StackSegmentFault = 12,
            GeneralProtectionFault = 13,
            PageFault = 14,
            Reserved_1 = 15,
            x87FloatingPointException = 16,
            AlignmentCheck = 17,
            MachineCheck = 18,
            SIMDFloatingPointException = 19,
            VirtualizationException = 20,
            ControlProtectionException = 21,
            Reserved_2 = 22,
            Reserved_3 = 23,
            Reserved_4 = 24,
            Reserved_5 = 25,
            Reserved_6 = 26,
            Reserved_7 = 27,
            HypervisorInjectionException = 28,
            VMMCommunicationException = 29,
            SecurityException = 30,
            Reserved_8 = 31,
        };


    };

    pub const syscalls = struct {
    };

    pub const list = struct {
        pub const Iterator = struct {
            curr : *kernel.list.ListHead,
            head : *kernel.list.ListHead,
            used : bool= false,
        };

        pub const ListHead = packed struct {
            next : ?*kernel.list.ListHead,
            prev : ?*kernel.list.ListHead,
        };

    };

    pub const tree = struct {
        pub const TreeNode = struct {
            parent : ?*kernel.tree.TreeNode= null,
            child : ?*kernel.tree.TreeNode= null,
            next : ?*kernel.tree.TreeNode= null,
            prev : ?*kernel.tree.TreeNode= null,
        };

        pub const Iterator = struct {
            curr : *kernel.tree.TreeNode,
            head : *kernel.tree.TreeNode,
            used : bool= false,
        };

    };

    pub const ringbuf = struct {
        pub const RingBuf = struct {
            buf : []u8,
            mask : u32,
            r : u32= 0,
            w : u32= 0,
            line_count : u32= 0,
        };

    };

    pub const task = struct {
        pub const TaskState = enum(u8) {
            RUNNING = 0,
            UNINTERRUPTIBLE_SLEEP = 1,
            INTERRUPTIBLE_SLEEP = 2,
            STOPPED = 3,
            ZOMBIE = 4,
        };


        pub const TaskType = enum(u8) {
            KTHREAD = 0,
            PROCESS = 1,
        };


        pub const RefCount = struct {
            count : std.atomic.Value(usize),
            dropFn : *const fn(*kernel.task.RefCount) void,
        };

        pub const Task = struct {
            pid : u32,
            tsktype : kernel.task.TaskType,
            uid : u16,
            gid : u16,
            pgid : u16= 1,
            stack_bottom : u32,
            state : kernel.task.TaskState,
            regs : arch.Regs,
            tls : u32= 0,
            limit : u32= 0,
            tree : kernel.tree.TreeNode,
            list : kernel.list.ListHead,
            refcount : kernel.task.RefCount,
            wakeup_time : u32= 0,
            mm : ?*kernel.mm.proc_mm.MM= null,
            fs : *kernel.fs.FSInfo,
            files : *kernel.fs.file.TaskFiles,
            sighand : kernel.signals.SigHand,
            sigmask : kernel.signals.sigset_t,
            threadfn : ?*const fn(?*const anyopaque) i32= null,
            arg : ?*const anyopaque= null,
            result : i32= 0,
            should_stop : bool= false,
        };

    };

    pub const sched = struct {
        pub extern fn schedule(*arch.Regs)*arch.Regs;
    };

    pub const Mutex = struct {
        locked : std.atomic.Value(bool),
    };

    pub const userspace = struct {
    };

    pub const signals = struct {
        pub const Siginfo = struct {
            signo : i32,
            errno : i32,
            code : i32,
            fields : std.sched.signals.SiginfoFieldsUnion,
        };

        pub const sigset_t = struct {
            _bits : [2]u32,
        };

        pub const Sigaction = struct {
            handler : std.sched.signals.Sigaction__union_23673,
            flags : u32,
            restorer : ?*const fn() void= null,
            mask : kernel.signals.sigset_t,
        };

        pub const Signal = enum(u8) {
            EMPTY = 0,
            SIGHUP = 1,
            SIGINT = 2,
            SIGQUIT = 3,
            SIGILL = 4,
            SIGTRAP = 5,
            SIGABRT = 6,
            SIGBUS = 7,
            SIGFPE = 8,
            SIGKILL = 9,
            SIGUSR1 = 10,
            SIGSEGV = 11,
            SIGUSR2 = 12,
            SIGPIPE = 13,
            SIGALRM = 14,
            SIGTERM = 15,
            SIGSTKFLT = 16,
            SIGCHLD = 17,
            SIGCONT = 18,
            SIGSTOP = 19,
            SIGTSTP = 20,
            SIGTTIN = 21,
            SIGTTOU = 22,
            SIGURG = 23,
            SIGXCPU = 24,
            SIGXFSZ = 25,
            SIGVTALRM = 26,
            SIGPROF = 27,
            SIGWINCH = 28,
            SIGIO = 29,
            SIGPOLL = 30,
            SIGPWR = 31,
            SIGSYS = 32,
        };


        pub const SigHand = struct {
            pending : std.bit_set.IntegerBitSet(32),
            actions : std.enums.EnumArray(kernel.signals.Signal, kernel.signals.Sigaction),
        };

    };

    pub const jiffies = struct {
    };

    pub const errors = struct {
    };

    pub const socket = struct {
        pub const Socket = struct {
            _buffer : [128]u8,
            writer : std.Io.Writer,
            reader : std.Io.Reader,
            conn : ?*kernel.socket.Socket,
            list : kernel.list.ListHead,
            lock : kernel.Mutex,
        };

    };


    pub const fs = struct {

        pub const SuperBlock = struct {
            ops : *const kernel.fs.SuperOps,
            root : *kernel.fs.DEntry,
            fs : *kernel.fs.filesystem.FileSystem,
            ref : kernel.task.RefCount,
            list : kernel.list.ListHead,
            block_size : u32,
            inode_map : std.hash_map.HashMap(u32, *kernel.fs.Inode, std.hash_map.AutoContext(u32), 80),
            dev_file : ?*kernel.fs.file.File= null,
        };

        pub const SuperOps = struct {
            alloc_inode : *const fn(*kernel.fs.SuperBlock) anyerror!*kernel.fs.Inode,
        };

        pub const Mount = struct {
            sb : *kernel.fs.SuperBlock,
            root : *kernel.fs.DEntry,
            tree : kernel.tree.TreeNode,
            count : kernel.task.RefCount,
        };

        pub const mount = struct {

        };

        pub const DEntry = struct {
            sb : *kernel.fs.SuperBlock,
            inode : *kernel.fs.Inode,
            ref : kernel.task.RefCount,
            name : []u8,
            tree : kernel.tree.TreeNode,
        };

        pub const filesystem = struct {
            pub const FileSystem = struct {
                name : []const u8,
                list : kernel.list.ListHead,
                sbs : kernel.list.ListHead,
                virtual : bool= true,
                ops : *const kernel.fs.filesystem.FileSystemOps,
            };

            pub const FileSystemOps = struct {
                getSB : *const fn(*kernel.fs.filesystem.FileSystem, ?*kernel.fs.file.File) anyerror!*kernel.fs.SuperBlock,
            };

        };



        pub const Inode = struct {
            i_no : u32= 0,
            sb : ?*kernel.fs.SuperBlock,
            ref : kernel.task.RefCount,
            mode : kernel.fs.UMode,
            uid : u32= 0,
            gid : u32= 0,
            atime : u32= 0,
            ctime : u32= 0,
            mtime : u32= 0,
            dev_id : drivers.device.dev_t,
            data : std.fs.inode.Inode__union_23216,
            size : u32= 0,
            ops : *const kernel.fs.InodeOps,
            fops : *const kernel.fs.file.FileOps,
        };

        pub const InodeOps = struct {
            create : *const fn(*kernel.fs.Inode, []const u8, kernel.fs.UMode, *kernel.fs.DEntry) anyerror!*kernel.fs.DEntry,
            mknod : ?*const fn(*kernel.fs.Inode, []const u8, kernel.fs.UMode, *kernel.fs.DEntry, drivers.device.dev_t) anyerror!*kernel.fs.DEntry,
            lookup : *const fn(*kernel.fs.DEntry, []const u8) anyerror!*kernel.fs.DEntry,
            mkdir : *const fn(*kernel.fs.Inode, *kernel.fs.DEntry, []const u8, kernel.fs.UMode) anyerror!*kernel.fs.DEntry,
            get_link : ?*const fn(*kernel.fs.Inode, *[]u8) anyerror!void,
        };




        pub const path = struct {
            pub const Path = struct {
                mnt : *kernel.fs.Mount,
                dentry : *kernel.fs.DEntry,
            };

        };

        pub const file = struct {
            pub const File = struct {
                mode : kernel.fs.UMode,
                flags : u32,
                ops : *const kernel.fs.file.FileOps,
                pos : u32,
                inode : *kernel.fs.Inode,
                ref : kernel.task.RefCount,
                path : ?kernel.fs.path.Path,
            };

            pub const FileOps = struct {
                open : *const fn(*kernel.fs.file.File, *kernel.fs.Inode) anyerror!void,
                close : *const fn(*kernel.fs.file.File) void,
                write : *const fn(*kernel.fs.file.File, [*]const u8, u32) anyerror!u32,
                read : *const fn(*kernel.fs.file.File, [*]u8, u32) anyerror!u32,
                lseek : ?*const fn(*kernel.fs.file.File, u32, u32) anyerror!u32= null,
                readdir : ?*const fn(*kernel.fs.file.File, []u8) anyerror!u32= null,
            };

            pub const TaskFiles = struct {
                map : std.bit_set.DynamicBitSet,
                fds : std.hash_map.HashMap(u32, *kernel.fs.file.File, std.hash_map.AutoContext(u32), 80),
            };

        };




        pub const examplefs = struct {
            pub const ExampleFileSystem = struct {
                base : kernel.fs.filesystem.FileSystem,
            };

        };

        pub const sysfs = struct {
            pub const SysFileSystem = struct {
                base : kernel.fs.filesystem.FileSystem,
            };

        };

        pub const devfs = struct {
            pub const DevFileSystem = struct {
                base : kernel.fs.filesystem.FileSystem,
            };

        };

        pub const ext2 = struct {
            pub const Ext2FileSystem = struct {
                base : kernel.fs.filesystem.FileSystem,
            };

        };

        pub const DentryHash = struct {
            sb : u32,
            ino : u32,
            name : []const u8,
        };

        pub const InoNameContext = struct {
        };

        pub const Dirent = extern struct {
            ino : u32,
            off : u32,
            reclen : u16,
            name : [256]u8,
        };

        pub const Dirent64 = extern struct {
            ino : u64,
            off : u64,
            reclen : u16,
            type : u8,
        };

        pub const LinuxDirent = extern struct {
            ino : u32,
            off : u32,
            reclen : u16,
            type : u8,
        };

        pub const UMode = packed struct {
            other : u3= 0,
            grp : u3= 0,
            usr : u3= 0,
            type : u7= 0,
        };

        pub const FSInfo = struct {
            root : kernel.fs.path.Path,
            pwd : kernel.fs.path.Path,
        };

    };

    pub const TestStruct = struct {
        array : [50]u8,
        optional : ?*u32,
        slice : []const u8,
        opq : *anyopaque,
        sent : [*:0]u8,
    };

};

pub const debug = struct {
    pub const Logger = struct {
        log_level : std.logger.LogLevel,
    };

};

pub const drivers = struct {
    pub const Keyboard = struct {
        write_pos : u8= 0,
        read_pos : u8= 0,
        buffer : [256]u8,
        keymap : *const std.enums.EnumMap(drivers.keyboard.ScanCode, drivers.keyboard.KeymapEntry),
        shift : bool,
        cntl : bool,
        alt : bool,
        caps : bool,
    };


    pub const shell = struct {
        pub const ShellCommand = struct {
            name : []const u8,
            desc : []const u8,
            hndl : *const fn(*drivers.shell.Shell, [][]const u8) void,
        };

        pub const Shell = struct {
            arg_buf : [10][]const u8,
            commands : std.hash_map.HashMap([]const u8, drivers.shell.ShellCommand, std.hash_map.StringContext, 80),
        };

    };

    pub const framebuffer = struct {
        pub const Img = struct {
            width : u32,
            height : u32,
            data : []const u32,
        };

        pub const Font = struct {
            width : u8,
            height : u8,
            data : [256][]const u16,
        };

        pub const FrameBuffer = struct {
            fb_info : *arch.multiboot.TagFrameBufferInfo,
            fb_ptr : [*]u32,
            cwidth : u32,
            cheight : u32,
            virtual_buffer : [*]u32,
            font : *const drivers.framebuffer.Font,
        };

    };

    pub const keyboard = struct {
        pub const ScanCode = enum(u8) {
            K_ESC = 1,
            K_1 = 2,
            K_2 = 3,
            K_3 = 4,
            K_4 = 5,
            K_5 = 6,
            K_6 = 7,
            K_7 = 8,
            K_8 = 9,
            K_9 = 10,
            K_0 = 11,
            K_MINUS = 12,
            K_EQUALS = 13,
            K_BACKSPACE = 14,
            K_TAB = 15,
            K_Q = 16,
            K_W = 17,
            K_E = 18,
            K_R = 19,
            K_T = 20,
            K_Y = 21,
            K_U = 22,
            K_I = 23,
            K_O = 24,
            K_P = 25,
            K_OSQB = 26,
            K_CSQB = 27,
            K_ENTER = 28,
            K_LCTRL = 29,
            K_A = 30,
            K_S = 31,
            K_D = 32,
            K_F = 33,
            K_G = 34,
            K_H = 35,
            K_J = 36,
            K_K = 37,
            K_L = 38,
            K_SEMICOL = 39,
            K_QUOTE = 40,
            K_BCKQUOTE = 41,
            K_LSHIFT = 42,
            K_BCKSL = 43,
            K_Z = 44,
            K_X = 45,
            K_C = 46,
            K_V = 47,
            K_B = 48,
            K_N = 49,
            K_M = 50,
            K_COMMA = 51,
            K_DOT = 52,
            K_SLASH = 53,
            K_RSHIFT = 54,
            K_KPAD_STAR = 55,
            K_LALT = 56,
            K_WHITESPACE = 57,
            K_CAPSLOCK = 58,
            K_F1 = 59,
            K_F2 = 60,
            K_F3 = 61,
            K_F4 = 62,
            K_F5 = 63,
            K_F6 = 64,
            K_F7 = 65,
            K_F8 = 66,
            K_F9 = 67,
            K_F10 = 68,
            K_NUMLOCK = 69,
            K_SCRLLOCK = 70,
            K_HOME = 71,
            K_UP = 72,
            K_PGUP = 73,
            K_KPAD_MINUS = 74,
            K_LEFT = 75,
            K_KPAD_FIVE = 76,
            K_RIGHT = 77,
            K_KPAD_PLUS = 78,
            K_END = 79,
            K_DOWN = 80,
            K_PGDN = 81,
            K_INS = 82,
            K_DEL = 83,
            K_ALT_SYSRQ = 84,
            K_FN = 85,
            K_LLALT = 86,
            K_F11 = 87,
            K_F12 = 88,
            K_LMODAL = 91,
            K_RMODAL = 92,
            K_MENU = 93,
            K_POWER = 94,
            K_SLEEP = 95,
            K_WAKE = 99,
            _,
        };


        pub const KeymapEntry = struct {
            normal : u8,
            shift : ?u8= null,
            ctrl : ?u8= null,
            alt : ?u8= null,
        };

        pub const KeyEvent = struct {
            ctl : bool,
            val : u8,
        };

        pub const CtrlType = enum(u8) {
            LEFT = 0,
            RIGHT = 1,
            UP = 2,
            DOWN = 3,
            HOME = 4,
            END = 5,
            _,
        };



    };

    pub const pit = struct {
        pub const PIT = struct {
            clock_freq : u32= 1193182,
        };

    };

    pub const storage = struct {
        pub const bus = struct {
        };

        pub const driver = struct {
            pub const StorageDriver = struct {
                driver : drivers.driver.Driver,
                probe : *const fn(*drivers.storage.device.StorageDevice) anyerror!void,
                remove : *const fn(*drivers.storage.device.StorageDevice) anyerror!void,
            };

        };

        pub const device = struct {
            pub const StorageDevice = struct {
                dev : drivers.device.Device,
            };

        };



        pub const ata = struct {
            pub const ATADrive = struct {
                name : [41]u8,
                channel : std.storage.ata.ChannelType,
                io_base : u16= 0,
                ctrl_base : u16= 0,
                bmide_base : u16= 0,
                irq_num : u32= 0,
                current_op : std.storage.ata.ATA_Operation,
                status : std.storage.ata.ATA_Status,
                device_cmd : u8= 0,
                buffer : []u8,
                lba28 : u32= 0,
                lba48 : u64= 0,
                drive : u8= 0,
                irq_enabled : bool= false,
                prdt_phys : u32= 0,
                prdt_virt : u32= 0,
                dma_buff_phys : u32= 0,
                dma_buff_virt : u32= 0,
                dma_initialized : bool= false,
                partitions : std.array_list.Aligned(*std.storage.partitions.Partition, null),
            };

            pub const Iterator = struct {
                drives : *const std.array_list.Aligned(*drivers.storage.ata.ATADrive, null),
                current : u32,
            };

            pub const ATAManager = struct {
                drives : std.array_list.Aligned(*drivers.storage.ata.ATADrive, null),
            };

        };

    };

    pub const cmos = struct {
        pub const CMOS = struct {
            curr_time : [7]u8,
        };

    };

    pub const bus = struct {
        pub const Bus = struct {
            name : []const u8,
            list : kernel.list.ListHead,
            drivers : ?*drivers.driver.Driver,
            drivers_mutex : kernel.Mutex,
            devices : ?*drivers.device.Device,
            device_mutex : kernel.Mutex,
            sysfs_dentry : ?*kernel.fs.DEntry= null,
            sysfs_devices : ?*kernel.fs.DEntry= null,
            sysfs_drivers : ?*kernel.fs.DEntry= null,
            match : *const fn(*drivers.driver.Driver, *drivers.device.Device) bool,
            scan : ?*const fn(*drivers.bus.Bus) void,
        };

    };

    pub const device = struct {
        pub const dev_t = packed struct {
            major : u8,
            minor : u8,
        };

        pub const Device = struct {
            name : []const u8,
            bus : *drivers.bus.Bus,
            driver : ?*drivers.driver.Driver,
            id : drivers.device.dev_t,
            lock : kernel.Mutex,
            list : kernel.list.ListHead,
            tree : kernel.tree.TreeNode,
            data : *anyopaque,
        };

    };

    pub const driver = struct {
        pub const Driver = struct {
            name : []const u8,
            list : kernel.list.ListHead,
            minor_set : std.bit_set.ArrayBitSet(usize, 256),
            minor_mutex : kernel.Mutex,
            major : u8= 0,
            fops : ?*kernel.fs.file.FileOps= null,
            probe : *const fn(*drivers.driver.Driver, *drivers.device.Device) anyerror!void,
            remove : *const fn(*drivers.driver.Driver, *drivers.device.Device) anyerror!void,
        };

    };

    pub const cdev = struct {
    };

    pub const bdev = struct {
    };

    pub const platform = struct {
        pub const bus = struct {
        };

        pub const driver = struct {
            pub const PlatformDriver = struct {
                driver : drivers.driver.Driver,
                probe : *const fn(*drivers.platform.device.PlatformDevice) anyerror!void,
                remove : *const fn(*drivers.platform.device.PlatformDevice) anyerror!void,
            };

        };

        pub const device = struct {
            pub const PlatformDevice = struct {
                dev : drivers.device.Device,
            };

        };

        pub const serial = struct {
            pub const Serial = struct {
                addr : u16,
            };

        };

        pub const tty = struct {
            pub const ConsoleColors = enum(u32) {
                Black = 0,
                Blue = 255,
                Green = 65280,
                Cyan = 65535,
                Red = 16711680,
                Magenta = 16711935,
                Brown = 16753920,
                LightGray = 13882323,
                DarkGray = 11119017,
                LightBlue = 11393254,
                LightGreen = 13621465,
                LightCyan = 14745599,
                LightRed = 16764107,
                LightMagenta = 16713397,
                LightBrown = 12887172,
                White = 16777215,
            };


            pub const DirtyRect = struct {
                x1 : u32,
                y1 : u32,
                x2 : u32,
                y2 : u32,
            };

            pub const TTY = struct {
                width : u32= 80,
                height : u32= 25,
                _x : u32= 0,
                _y : u32= 0,
                _bg_colour : u32= 0,
                _fg_colour : u32= 16777215,
                _buffer : [*]u8,
                _prev_buffer : [*]u8,
                _line : [*]u8,
                _input_len : u32= 0,
                _prev_x : u32= 0,
                _prev_y : u32= 0,
                _dirty_rect : drivers.platform.tty.DirtyRect,
                _has_dirty_rect : bool= false,
                file_buff : kernel.ringbuf.RingBuf,
                lock : kernel.Mutex,
            };

        };





    };


    pub const pci = struct {
        pub const bus = struct {
            pub const ConfigCommand = packed struct {
                always_zero : u2= 0,
                reg_offset : u6= 0,
                func_num : u3= 0,
                dev_num : u5= 0,
                bus_num : u8= 0,
                reserved : u7= 0,
                enable : bool= false,
            };

        };

        pub const driver = struct {
            pub const PCIDriver = struct {
                driver : drivers.driver.Driver,
                ids : ?[]const drivers.pci.driver.PCIid,
                probe : *const fn(*drivers.pci.device.PCIDevice) anyerror!void,
                remove : *const fn(*drivers.pci.device.PCIDevice) anyerror!void,
            };

            pub const PCIid = struct {
                class : u8,
                subclass : u8,
                vendorid : u16,
                deviceid : u16,
            };

        };

        pub const device = struct {
            pub const PCIDevice = struct {
                vendor_id : u16= 0,
                device_id : u16= 0,
                command : u16= 0,
                status : u16= 0,
                revision_id : u8= 0,
                prog_IF : u8= 0,
                subclass : u8= 0,
                class_code : u8= 0,
                cache_line_size : u8= 0,
                latency_timer : u8= 0,
                header_type : u8= 0,
                bist : u8= 0,
                bar0 : u32= 0,
                bar1 : u32= 0,
                bar2 : u32= 0,
                bar3 : u32= 0,
                bar4 : u32= 0,
                bar5 : u32= 0,
                cardbus_cis : u32= 0,
                subsystem_vendor_id : u16= 0,
                subsystem_id : u16= 0,
                expansion_rom_base_addr : u32= 0,
                capabil_ptr : u8= 0,
                reserved_1 : u8= 0,
                reserved_2 : u16= 0,
                reserved_3 : u32= 0,
                int_line : u8= 0,
                int_pin : u8= 0,
                min_grant : u8= 0,
                max_latency : u8= 0,
                pci_cmd : drivers.pci.bus.ConfigCommand,
                dev : drivers.device.Device,
            };

        };



        pub const ide = struct {
        };

    };

};

