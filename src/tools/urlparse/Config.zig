pub const OutputFormat = enum {
    json,
    markdown,
};

pub const Field = enum {
    scheme,
    user,
    password,
    host,
    port,
    path,
    query,
    fragment,
};

url: []const u8,
field: ?Field = null,
output_format: ?OutputFormat = null,

const std = @import("std");
