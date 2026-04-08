pub fn main() !void {
    try cli.execute(std.heap.page_allocator, mboxGen);
}

fn mboxGen() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config = cli.config;

    const params = parseParams(config) catch |err| {
        reportParseError(err, config);
        std.process.exit(1);
    };

    var output_file = std.fs.cwd().createFile(config.output, .{
        .truncate = true,
        .exclusive = !config.force,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            printStderr("error: {s} exists (use --force to overwrite)\n", .{config.output});
            std.process.exit(1);
        },
        else => return err,
    };
    defer output_file.close();

    var output_buf: [64 * 1024]u8 = undefined;
    var stream = output_file.writer(&output_buf);
    const writer = &stream.interface;

    try generate.generate(allocator, writer, params);
    try writer.flush();
}

const max_body_size: u32 = 1 << 24; // 16 MiB per message body

const ParseError = error{
    InvalidSize,
    InvalidBodySize,
    InvalidRatio,
};

fn parseParams(config: Config) ParseError!generate.Params {
    const target_bytes = humanize.parseBytes(config.size) catch {
        return error.InvalidSize;
    };

    if (config.body_size == 0 or config.body_size > max_body_size) {
        return error.InvalidBodySize;
    }

    if (!std.math.isFinite(config.with_id_ratio) or
        config.with_id_ratio < 0.0 or
        config.with_id_ratio > 1.0)
    {
        return error.InvalidRatio;
    }

    return .{
        .size = target_bytes,
        .seed = config.seed,
        .body_size = config.body_size,
        .with_id_ratio = config.with_id_ratio,
    };
}

fn reportParseError(err: ParseError, config: Config) void {
    switch (err) {
        error.InvalidSize => printStderr(
            "error: invalid --size value '{s}' (try e.g. 100M, 1GiB, 4096)\n",
            .{config.size},
        ),
        error.InvalidBodySize => printStderr(
            "error: --body-size must be in [1, {d}], got {d}\n",
            .{ max_body_size, config.body_size },
        ),
        error.InvalidRatio => printStderr(
            "error: --with-id-ratio must be a finite number in [0.0, 1.0], got {d}\n",
            .{config.with_id_ratio},
        ),
    }
}

fn printStderr(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr();
    var buf: [512]u8 = undefined;
    var w = stderr.writer(&buf);
    w.interface.print(fmt, args) catch return;
    w.interface.flush() catch return;
}

const std = @import("std");
const humanize = @import("humanize");

const cli = @import("cli.zig");
const generate = @import("generate.zig");
const Config = @import("Config.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
