// kallsyms Template - Provides empty array of symbols

var string_table_data linksection(".kallsyms") = [_]u8{};

var addresses_data linksection(".kallsyms") = [_]u32{};

var string_indices_data linksection(".kallsyms") = [_]u32{};

export const kallsyms_string_table: [*]const u8 linksection(".kallsyms") = &string_table_data;
export const kallsyms_addresses: [*]const u32 linksection(".kallsyms") = &addresses_data;
export const kallsyms_string_indices: [*]const u32 linksection(".kallsyms") = &string_indices_data;
export const kallsyms_count: u32 linksection(".kallsyms") = 2954;
export const kallsyms_string_table_size: u32 linksection(".kallsyms") = 81464;
