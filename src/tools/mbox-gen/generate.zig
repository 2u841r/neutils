pub const Params = struct {
    size: u64,
    seed: u64 = 0,
    body_size: u32 = 1024,
    with_id_ratio: f32 = 1.0,
};

const safe_alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
const epoch_base: u64 = 1700000000;

fn fillBody(body: []u8) void {
    var col: usize = 0;
    var i: usize = 0;
    for (body) |*b| {
        if (col >= 76) {
            b.* = '\n';
            col = 0;
        } else {
            b.* = safe_alphabet[i % safe_alphabet.len];
            col += 1;
            i += 1;
        }
    }
}

pub fn generate(
    allocator: Allocator,
    out: *std.io.Writer,
    params: Params,
) !void {
    var prng: std.Random.DefaultPrng = .init(params.seed);
    const rand = prng.random();

    const body = try allocator.alloc(u8, params.body_size);
    defer allocator.free(body);
    fillBody(body);

    var counting: Counting = .init(out);
    const writer = &counting.writer;

    var counter: u64 = 0;
    while (counting.count < params.size) {
        try writeMessage(writer, body, counter, rand, params);
        counter += 1;
    }
}

fn writeMessage(
    writer: *std.io.Writer,
    body: []const u8,
    counter: u64,
    rand: std.Random,
    params: Params,
) !void {
    const ts: u64 = epoch_base + counter * 60;

    try writer.print("From bench@neutils.local {d}\n", .{ts});
    try writer.print("From: bench-{d}@neutils.local\n", .{counter});
    try writer.print("To: dest-{d}@neutils.local\n", .{counter});
    try writer.print("Subject: Benchmark message {d}\n", .{counter});
    try writer.print("Date: {d}\n", .{ts});

    if (rand.float(f32) < params.with_id_ratio) {
        try writer.print("Message-ID: <{d}@neutils.local>\n", .{counter});
    }

    try writer.writeAll("\n");
    try writer.writeAll(body);
    try writer.writeAll("\n");
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Counting = @import("Counting.zig");
const Index = @import("mbox").Index;

test "generate produces a parseable mbox" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        var file = try tmp.dir.createFile("gen.mbox", .{});
        defer file.close();

        var write_buf: [4096]u8 = undefined;
        var stream = file.writer(&write_buf);
        const writer = &stream.interface;

        const params: Params = .{
            .size = 4096,
            .body_size = 1024,
            .with_id_ratio = 1.0,
        };

        try generate(allocator, writer, params);
        try writer.flush();
    }

    var read_file = try tmp.dir.openFile("gen.mbox", .{});
    defer read_file.close();

    var idx = try Index.index(allocator, read_file);
    defer idx.deinit(allocator);

    try std.testing.expect(idx.locations.count() > 0);
}

test "generate is deterministic for the same seed" {
    const allocator = std.testing.allocator;

    var buf_a: [16384]u8 = undefined;
    var w_a: std.io.Writer = .fixed(&buf_a);

    var buf_b: [16384]u8 = undefined;
    var w_b: std.io.Writer = .fixed(&buf_b);

    const params: Params = .{
        .size = 8192,
        .seed = 42,
        .body_size = 512,
        .with_id_ratio = 0.5,
    };

    try generate(allocator, &w_a, params);
    try generate(allocator, &w_b, params);

    try std.testing.expectEqualSlices(u8, w_a.buffered(), w_b.buffered());
}

test "generate diverges across different seeds" {
    const allocator = std.testing.allocator;

    var buf_a: [16384]u8 = undefined;
    var w_a: std.io.Writer = .fixed(&buf_a);

    var buf_b: [16384]u8 = undefined;
    var w_b: std.io.Writer = .fixed(&buf_b);

    // Ratio < 1.0 so the seed actually influences output via the
    // Message-ID gate.
    const params_a: Params = .{
        .size = 8192,
        .seed = 1,
        .body_size = 512,
        .with_id_ratio = 0.5,
    };
    var params_b = params_a;
    params_b.seed = 2;

    try generate(allocator, &w_a, params_a);
    try generate(allocator, &w_b, params_b);

    try std.testing.expect(!std.mem.eql(u8, w_a.buffered(), w_b.buffered()));
}

test "generate respects size bound" {
    const allocator = std.testing.allocator;

    var buf: [32768]u8 = undefined;
    var w: std.io.Writer = .fixed(&buf);

    const target: u64 = 8192;
    const params: Params = .{
        .size = target,
        .body_size = 1024,
        .with_id_ratio = 1.0,
    };

    try generate(allocator, &w, params);

    const written = w.buffered().len;
    try std.testing.expect(written >= target);
    // Upper bound = target + one full message. With body_size 1024 + headers
    // a message is well under 2 KB.
    try std.testing.expect(written < target + 2048);
}

test "generate at ratio 1.0 includes Message-ID for every message" {
    const allocator = std.testing.allocator;

    var buf: [32768]u8 = undefined;
    var w: std.io.Writer = .fixed(&buf);

    const params: Params = .{
        .size = 8192,
        .body_size = 512,
        .with_id_ratio = 1.0,
    };

    try generate(allocator, &w, params);

    const data = w.buffered();
    const from_count = countFromLines(data);
    const msgid_count = std.mem.count(u8, data, "Message-ID:");

    try std.testing.expectEqual(from_count, msgid_count);
}

test "generate at ratio 0.0 produces no Message-ID and indexes via fallback" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        var file = try tmp.dir.createFile("nomid.mbox", .{});
        defer file.close();

        var write_buf: [4096]u8 = undefined;
        var stream = file.writer(&write_buf);
        const writer = &stream.interface;

        const params: Params = .{
            .size = 8192,
            .body_size = 512,
            .with_id_ratio = 0.0,
        };

        try generate(allocator, writer, params);
        try writer.flush();
    }

    {
        var content_file = try tmp.dir.openFile("nomid.mbox", .{});
        defer content_file.close();
        const data = try content_file.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(data);
        try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, data, "Message-ID:"));
    }

    var read_file = try tmp.dir.openFile("nomid.mbox", .{});
    defer read_file.close();

    var idx = try Index.index(allocator, read_file);
    defer idx.deinit(allocator);

    try std.testing.expect(idx.locations.count() > 0);
}

test "generate ratio 1.0 round-trips through index with N unique messages" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        var file = try tmp.dir.createFile("rt.mbox", .{});
        defer file.close();

        var write_buf: [4096]u8 = undefined;
        var stream = file.writer(&write_buf);
        const writer = &stream.interface;

        const params: Params = .{
            .size = 16384,
            .body_size = 512,
            .with_id_ratio = 1.0,
        };

        try generate(allocator, writer, params);
        try writer.flush();
    }

    var content_file = try tmp.dir.openFile("rt.mbox", .{});
    defer content_file.close();
    const data = try content_file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(data);
    const from_count = countFromLines(data);

    var read_file = try tmp.dir.openFile("rt.mbox", .{});
    defer read_file.close();

    var idx = try Index.index(allocator, read_file);
    defer idx.deinit(allocator);

    try std.testing.expectEqual(from_count, idx.locations.count());
}

fn countFromLines(data: []const u8) usize {
    var count: usize = if (std.mem.startsWith(u8, data, "From ")) 1 else 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, data, i, "\nFrom ")) |pos| {
        count += 1;
        i = pos + 1;
    }
    return count;
}
