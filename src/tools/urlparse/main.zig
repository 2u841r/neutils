const std = @import("std");

const version = "0.1.0";

const Field = enum {
    scheme,
    user,
    password,
    host,
    port,
    path,
    query,
    fragment,

    fn fromString(s: []const u8) ?Field {
        const map = std.StaticStringMap(Field).initComptime(.{
            .{ "scheme", .scheme },
            .{ "user", .user },
            .{ "password", .password },
            .{ "host", .host },
            .{ "port", .port },
            .{ "path", .path },
            .{ "query", .query },
            .{ "fragment", .fragment },
        });
        return map.get(s);
    }
};

fn getComponentString(component: ?std.Uri.Component) ?[]const u8 {
    const comp = component orelse return null;
    return switch (comp) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };
}

fn writeJsonString(file: std.fs.File, s: []const u8) !void {
    try file.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try file.writeAll("\\\""),
            '\\' => try file.writeAll("\\\\"),
            '\n' => try file.writeAll("\\n"),
            '\r' => try file.writeAll("\\r"),
            '\t' => try file.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                    try file.writeAll(slice);
                } else {
                    try file.writeAll(&[_]u8{c});
                }
            },
        }
    }
    try file.writeAll("\"");
}

fn writeString(file: std.fs.File, s: []const u8) !void {
    try file.writeAll(s);
}

fn writeInt(file: std.fs.File, comptime T: type, value: T) !void {
    var buf: [20]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    try file.writeAll(slice);
}

fn printHelp(file: std.fs.File) !void {
    try file.writeAll(
        \\Usage: urlparse [OPTIONS] <URL>
        \\
        \\Parse a URL and display its components.
        \\
        \\Options:
        \\  --json           Output in JSON format
        \\  --field <name>   Extract a single field (scheme, user, password,
        \\                   host, port, path, query, fragment)
        \\  --help           Show this help message
        \\  --version        Show version information
        \\
        \\Examples:
        \\  urlparse "https://example.com/path?query=value#fragment"
        \\  urlparse --json "https://user:pass@example.com:8080/path"
        \\  urlparse --field host "https://example.com/path"
        \\
    );
}

fn printVersion(file: std.fs.File) !void {
    try file.writeAll("urlparse ");
    try file.writeAll(version);
    try file.writeAll("\n");
}

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    var args = std.process.args();
    _ = args.skip(); // Skip program name

    var json_output = false;
    var field_filter: ?Field = null;
    var url: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(stdout);
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try printVersion(stdout);
            return;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--field")) {
            const field_name = args.next() orelse {
                try stderr.writeAll("error: --field requires a field name argument\n");
                std.process.exit(1);
            };
            field_filter = Field.fromString(field_name) orelse {
                try stderr.writeAll("error: unknown field '");
                try stderr.writeAll(field_name);
                try stderr.writeAll("'\n");
                try stderr.writeAll("valid fields: scheme, user, password, host, port, path, query, fragment\n");
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.writeAll("error: unknown option '");
            try stderr.writeAll(arg);
            try stderr.writeAll("'\n");
            std.process.exit(1);
        } else {
            url = arg;
        }
    }

    const url_str = url orelse {
        try stderr.writeAll("error: no URL provided\n");
        try stderr.writeAll("usage: urlparse [OPTIONS] <URL>\n");
        try stderr.writeAll("try 'urlparse --help' for more information\n");
        std.process.exit(1);
    };

    const uri = std.Uri.parse(url_str) catch |err| {
        try stderr.writeAll("error: failed to parse URL: ");
        try stderr.writeAll(@errorName(err));
        try stderr.writeAll("\n");
        std.process.exit(1);
    };

    // Extract component values
    const scheme = uri.scheme;
    const user = getComponentString(uri.user);
    const password = getComponentString(uri.password);
    const host = getComponentString(uri.host);
    const port = uri.port;
    const path = getComponentString(uri.path);
    const query = getComponentString(uri.query);
    const fragment = getComponentString(uri.fragment);

    // Handle single field extraction
    if (field_filter) |field| {
        const value: ?[]const u8 = switch (field) {
            .scheme => scheme,
            .user => user,
            .password => password,
            .host => host,
            .port => null, // Special case: port is u16
            .path => path,
            .query => query,
            .fragment => fragment,
        };

        if (field == .port) {
            if (port) |p| {
                try writeInt(stdout, u16, p);
                try stdout.writeAll("\n");
            }
        } else {
            if (value) |v| {
                try stdout.writeAll(v);
                try stdout.writeAll("\n");
            }
        }
        return;
    }

    // JSON output
    if (json_output) {
        try stdout.writeAll("{\n");
        try stdout.writeAll("  \"scheme\": ");
        try writeJsonString(stdout, scheme);

        try stdout.writeAll(",\n  \"user\": ");
        if (user) |u| {
            try writeJsonString(stdout, u);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"password\": ");
        if (password) |p| {
            try writeJsonString(stdout, p);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"host\": ");
        if (host) |h| {
            try writeJsonString(stdout, h);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"port\": ");
        if (port) |p| {
            try writeInt(stdout, u16, p);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"path\": ");
        if (path) |p| {
            try writeJsonString(stdout, p);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"query\": ");
        if (query) |q| {
            try writeJsonString(stdout, q);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll(",\n  \"fragment\": ");
        if (fragment) |f| {
            try writeJsonString(stdout, f);
        } else {
            try stdout.writeAll("null");
        }

        try stdout.writeAll("\n}\n");
        return;
    }

    // Plain text output
    try stdout.writeAll("scheme: ");
    try stdout.writeAll(scheme);
    try stdout.writeAll("\n");

    if (user) |u| {
        try stdout.writeAll("user: ");
        try stdout.writeAll(u);
        try stdout.writeAll("\n");
    }

    if (password) |p| {
        try stdout.writeAll("password: ");
        try stdout.writeAll(p);
        try stdout.writeAll("\n");
    }

    if (host) |h| {
        try stdout.writeAll("host: ");
        try stdout.writeAll(h);
        try stdout.writeAll("\n");
    }

    if (port) |p| {
        try stdout.writeAll("port: ");
        try writeInt(stdout, u16, p);
        try stdout.writeAll("\n");
    }

    if (path) |p| {
        if (p.len > 0) {
            try stdout.writeAll("path: ");
            try stdout.writeAll(p);
            try stdout.writeAll("\n");
        }
    }

    if (query) |q| {
        try stdout.writeAll("query: ");
        try stdout.writeAll(q);
        try stdout.writeAll("\n");
    }

    if (fragment) |f| {
        try stdout.writeAll("fragment: ");
        try stdout.writeAll(f);
        try stdout.writeAll("\n");
    }
}
