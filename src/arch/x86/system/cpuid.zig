const krn = @import("kernel");
const dbg = @import("debug");

pub const Result = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

pub const Leaf1EdxFeatures = packed struct(u32) {
    fpu:                bool = false,
    vme:                bool = false,
    de:                 bool = false,
    pse:                bool = false,
    tsc:                bool = false,
    msr:                bool = false,
    pae:                bool = false,
    mce:                bool = false,
    cx8:                bool = false,
    apic:               bool = false,
    _edx_10:            bool = false,
    sep:                bool = false,
    mtrr:               bool = false,
    pge:                bool = false,
    mca:                bool = false,
    cmov:               bool = false,
    pat:                bool = false,
    pse36:              bool = false,
    psn:                bool = false,
    clfsh:              bool = false,
    _edx_20:            bool = false,
    ds:                 bool = false,
    acpi:               bool = false,
    mmx:                bool = false,
    fxsr:               bool = false,
    sse:                bool = false,
    sse2:               bool = false,
    ss:                 bool = false,
    htt:                bool = false,
    tm:                 bool = false,
    ia64:               bool = false,
    pbe:                bool = false,

};

pub const Leaf1EcxFeatures = packed struct(u32) {
    sse3:               bool = false,
    pclmulqdq:          bool = false,
    dtes64:             bool = false,
    monitor:            bool = false,
    ds_cpl:             bool = false,
    vmx:                bool = false,
    smx:                bool = false,
    est:                bool = false,
    tm2:                bool = false,
    ssse3:              bool = false,
    cnxt_id:            bool = false,
    sdbg:               bool = false,
    fma:                bool = false,
    cx16:               bool = false,
    xtpr:               bool = false,
    pdcm:               bool = false,
    _ecx_16:            bool = false,
    pcid:               bool = false,
    dca:                bool = false,
    sse4_1:             bool = false,
    sse4_2:             bool = false,
    x2apic:             bool = false,
    movbe:              bool = false,
    popcnt:             bool = false,
    tsc_deadline:       bool = false,
    aes:                bool = false,
    xsave:              bool = false,
    osxsave:            bool = false,
    avx:                bool = false,
    f16c:               bool = false,
    rdrand:             bool = false,
    hypervisor:         bool = false,
};

pub const Leaf7EbxFeatures = packed struct(u32) {
    fsgsbase:           bool = false,
    ia32_tsc_adjust:    bool = false,
    sgx:                bool = false,
    bmi1:               bool = false,
    hle:                bool = false,
    avx2:               bool = false,
    fdp_excptn_only:    bool = false,
    smep:               bool = false,
    bmi2:               bool = false,
    erms:               bool = false,
    invpcid:            bool = false,
    rtm:                bool = false,
    pqm:                bool = false,
    fpucsds_deprec:     bool = false,
    mpx:                bool = false,
    pqe:                bool = false,
    avx512f:            bool = false,
    avx512dq:           bool = false,
    rdseed:             bool = false,
    adx:                bool = false,
    smap:               bool = false,
    avx512_ifma:        bool = false,
    pcommit:            bool = false,
    clflushopt:         bool = false,
    clwb:               bool = false,
    intel_pt:           bool = false,
    avx512pf:           bool = false,
    avx512er:           bool = false,
    avx512cd:           bool = false,
    sha:                bool = false,
    avx512bw:           bool = false,
    avx512vl:           bool = false,

};

pub const Leaf7EcxFeatures = packed struct(u32) {
    prefetchwt1:        bool = false,
    avx512_vbmi:        bool = false,
    umip:               bool = false,
    pku:                bool = false,
    ospke:              bool = false,
    waitpkg:            bool = false,
    avx512_vbmi2:       bool = false,
    cet_ss:             bool = false,
    gfni:               bool = false,
    vaes:               bool = false,
    vpclmulqdq:         bool = false,
    avx512_vnni:        bool = false,
    avx512_bitalg:      bool = false,
    tme_en:             bool = false,
    avx512_vpopcntdq:   bool = false,
    _ecx_15:            bool = false,
    la57:               bool = false,
    mawau0:             bool = false,
    mawau1:             bool = false,
    mawau2:             bool = false,
    mawau3:             bool = false,
    mawau4:             bool = false,
    rdpid:              bool = false,
    kl:                 bool = false,
    bus_lock_detect:    bool = false,
    cldemote:           bool = false,
    _ecx_26:            bool = false,
    movdiri:            bool = false,
    movdir64b:          bool = false,
    enqcmd:             bool = false,
    sgx_lc:             bool = false,
    pks:                bool = false,

};

pub const Leaf7EdxFeatures = packed struct(u32) {
    _edx_0:             bool = false,
    _edx_1:             bool = false,
    avx512_4vnniw:      bool = false,
    avx512_4fmaps:      bool = false,
    fsrm:               bool = false,
    uintr:              bool = false,
    _edx_6:             bool = false,
    _edx_7:             bool = false,
    avx512_vp2inters:   bool = false,
    srbds_ctrl:         bool = false,
    md_clear:           bool = false,
    rtm_always_abort:   bool = false,
    _edx_12:            bool = false,
    tsx_force_abort:    bool = false,
    serialize:          bool = false,
    hybrid:             bool = false,
    tsxldtrk:           bool = false,
    _edx_17:            bool = false,
    pconfig:            bool = false,
    arch_lbr:           bool = false,
    cet_ibt:            bool = false,
    _edx_21:            bool = false,
    amx_bf16:           bool = false,
    avx512_fp16:        bool = false,
    amx_tile:           bool = false,
    amx_int8:           bool = false,
    ibrs_ibpb:          bool = false,
    stibp:              bool = false,
    l1d_flush:          bool = false,
    ia32_arch_cap:      bool = false,
    ia32_core_cap:      bool = false,
    ssbd:               bool = false,
};

pub const Leaf1Features = struct {
    edx: Leaf1EdxFeatures = Leaf1EdxFeatures{},
    ecx: Leaf1EcxFeatures = Leaf1EcxFeatures{},
};

pub const Leaf7Features = struct {
    ebx: Leaf7EbxFeatures = Leaf7EbxFeatures{},
    ecx: Leaf7EcxFeatures = Leaf7EcxFeatures{},
    edx: Leaf7EdxFeatures = Leaf7EdxFeatures{},
};

pub const Info = struct {
    supported:          bool = false,
    max_basic_leaf:     u32 = 0,
    max_extended_leaf:  u32 = 0,
    vendor:             [12]u8 = .{0} ** 12,
    brand:              [48]u8 = .{0} ** 48,
    features:           Leaf1Features = Leaf1Features{},
    ext_features:       Leaf7Features = Leaf7Features{},
};

pub fn isSupported() bool {
    const supported = asm volatile (
        \\ pushfl
        \\ pop %%eax
        \\ mov %%eax, %%ecx
        \\ xor $0x200000, %%eax
        \\ push %%eax
        \\ popfl
        \\ pushfl
        \\ pop %%eax
        \\ xor %%ecx, %%eax
        \\ and $0x200000, %%eax
        \\ push %%ecx
        \\ popfl
        : [result] "={eax}" (-> u32)
        :: .{ .ecx = true, .memory = true }
    );
    return supported != 0;
}

pub fn read(leaf: u32, subleaf: u32) Result {
    if (!isSupported()) {
        return .{
            .eax = 0,
            .ebx = 0,
            .ecx = 0,
            .edx = 0
        };
    }

    var eax: u32 = leaf;
    var ebx: u32 = 0;
    var ecx: u32 = subleaf;
    var edx: u32 = 0;
    asm volatile (
        \\ cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (eax),
          [subleaf] "{ecx}" (ecx),
        : .{ .memory = true }
    );
    return .{
        .eax = eax,
        .ebx = ebx,
        .ecx = ecx,
        .edx = edx
    };
}

pub fn query() Info {
    var _info = Info{};
    if (!isSupported()) {
        return _info;
    }

    _info.supported = true;
    const leaf0 = read(0, 0);
    _info.max_basic_leaf = leaf0.eax;

    const ebx = @as([4]u8, @bitCast(leaf0.ebx));
    const edx = @as([4]u8, @bitCast(leaf0.edx));
    const ecx = @as([4]u8, @bitCast(leaf0.ecx));
    @memcpy(_info.vendor[0..4], ebx[0..4]);
    @memcpy(_info.vendor[4..8], edx[0..4]);
    @memcpy(_info.vendor[8..12], ecx[0..4]);

    const ext0 = read(0x80000000, 0);
    _info.max_extended_leaf = ext0.eax;

    if (_info.max_basic_leaf >= 1) {
        const leaf1 = read(1, 0);
        _info.features.edx = @bitCast(leaf1.edx);
        _info.features.ecx = @bitCast(leaf1.ecx);
    }

    if (_info.max_basic_leaf >= 7) {
        const leaf7 = read(7, 0);
        _info.ext_features.ebx = @bitCast(leaf7.ebx);
        _info.ext_features.ecx = @bitCast(leaf7.ecx);
        _info.ext_features.edx = @bitCast(leaf7.edx);
    }

    if (_info.max_extended_leaf >= 0x80000004) {
        const b0 = read(0x80000002, 0);
        const b1 = read(0x80000003, 0);
        const b2 = read(0x80000004, 0);

        const p0 = @as([4]u8, @bitCast(b0.eax));
        const p1 = @as([4]u8, @bitCast(b0.ebx));
        const p2 = @as([4]u8, @bitCast(b0.ecx));
        const p3 = @as([4]u8, @bitCast(b0.edx));
        const p4 = @as([4]u8, @bitCast(b1.eax));
        const p5 = @as([4]u8, @bitCast(b1.ebx));
        const p6 = @as([4]u8, @bitCast(b1.ecx));
        const p7 = @as([4]u8, @bitCast(b1.edx));
        const p8 = @as([4]u8, @bitCast(b2.eax));
        const p9 = @as([4]u8, @bitCast(b2.ebx));
        const p10 = @as([4]u8, @bitCast(b2.ecx));
        const p11 = @as([4]u8, @bitCast(b2.edx));

        @memcpy(_info.brand[0..4], p0[0..4]);
        @memcpy(_info.brand[4..8], p1[0..4]);
        @memcpy(_info.brand[8..12], p2[0..4]);
        @memcpy(_info.brand[12..16], p3[0..4]);
        @memcpy(_info.brand[16..20], p4[0..4]);
        @memcpy(_info.brand[20..24], p5[0..4]);
        @memcpy(_info.brand[24..28], p6[0..4]);
        @memcpy(_info.brand[28..32], p7[0..4]);
        @memcpy(_info.brand[32..36], p8[0..4]);
        @memcpy(_info.brand[36..40], p9[0..4]);
        @memcpy(_info.brand[40..44], p10[0..4]);
        @memcpy(_info.brand[44..48], p11[0..4]);
    }
    return _info;
}

fn logLeaf(header: []const u8, features: anytype) void {
    krn.logger.WARN("{s}", .{header});
    const T = @TypeOf(features);
    inline for (@typeInfo(T).@"struct".fields) |field| {
        const val: bool = @field(features, field.name);
        krn.logger.WARN("{s}{s:>16}: {any}{s}", .{
            if (val) dbg.log.GREEN else dbg.log.YELLOW,
            field.name,
            val,
            dbg.log.DEFAULT
        });
    }
    krn.logger.WARN("======", .{});
}

pub fn logAllFeatures(cpuid_info: Info) void {
    if (!cpuid_info.supported) {
        krn.logger.WARN("CPUID not supported", .{});
        return;
    }

    krn.logger.WARN(
        \\CPUID
        \\  vendor:         {s}
        \\  brand:          {s}
        \\  max basic leaf: 0x{x}
        \\  max exten leaf: 0x{x}
        \\
        ,
        .{
            cpuid_info.vendor[0..],
            cpuid_info.brand[0..],
            cpuid_info.max_basic_leaf,
            cpuid_info.max_extended_leaf,
        }
    );

    if (cpuid_info.max_basic_leaf >= 1) {
        const leaf1 = read(1, 0);
        krn.logger.WARN(
            \\CPUID leaf1 eax
            \\  stepping:   {d}
            \\  model:      {d}
            \\  family:     {d}
            \\  type:       {d}
            \\  ext_model:  {d}
            \\  ext_family: {d}
            \\
            ,
            .{
                (leaf1.eax >> 0) & 0xF,
                (leaf1.eax >> 4) & 0xF,
                (leaf1.eax >> 8) & 0xF,
                (leaf1.eax >> 12) & 0x3,
                (leaf1.eax >> 16) & 0xF,
                (leaf1.eax >> 20) & 0xFF,
            }
        );
        logLeaf("CPUID leaf1 ecx", cpuid_info.features.ecx);
        logLeaf("CPUID leaf1 edx", cpuid_info.features.edx);
    }

    if (cpuid_info.max_basic_leaf >= 7) {
        logLeaf("CPUID leaf7 ebx", cpuid_info.ext_features.ebx);
        logLeaf("CPUID leaf7 ecx", cpuid_info.ext_features.ecx);
        logLeaf("CPUID leaf7 edx", cpuid_info.ext_features.edx);
    }
}

pub var info: Info = undefined;
pub fn init() void {
    info = query();
    logAllFeatures(info);
}

