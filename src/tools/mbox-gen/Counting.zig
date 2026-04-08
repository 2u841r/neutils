//! Passthrough `std.io.Writer` that forwards all writes to an underlying
//! sink while tallying the bytes that flow through it.
//!
//! Mirrors the `{ state, writer: Writer }` pattern used by
//! `std.Io.Writer.Discarding` and `std.Io.Writer.Hashed`: own the state,
//! expose a `writer` face whose `drain` runs the side-effect (here, a
//! byte counter) and forwards the payload to `out`.
//!
//! Buffer is empty, so every write lands in `drain` and reaches `out`
//! without an intermediate copy — the outer sink is expected to do its
//! own buffering.

out: *std.io.Writer,
count: u64 = 0,
writer: std.io.Writer,

const Counting = @This();

pub fn init(out: *std.io.Writer) Counting {
    return .{
        .out = out,
        .writer = .{
            .vtable = &.{ .drain = Counting.drain },
            .buffer = &.{},
        },
    };
}

fn drain(
    w: *std.io.Writer,
    data: []const []const u8,
    splat: usize,
) std.io.Writer.Error!usize {
    const this: *Counting = @alignCast(@fieldParentPtr("writer", w));
    const n = try this.out.writeSplat(data, splat);
    this.count += n;
    return n;
}

const std = @import("std");

test "counts bytes forwarded to an underlying writer" {
    var sink_buf: [256]u8 = undefined;
    var sink: std.io.Writer = .fixed(&sink_buf);

    var counting: Counting = .init(&sink);
    try counting.writer.writeAll("hello");
    try counting.writer.print(" {s}!", .{"world"});

    try std.testing.expectEqual(@as(u64, 12), counting.count);
    try std.testing.expectEqualStrings("hello world!", sink.buffered());
}

test "count matches sink contents across many writes" {
    var sink_buf: [1024]u8 = undefined;
    var sink: std.io.Writer = .fixed(&sink_buf);

    var counting: Counting = .init(&sink);
    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        try counting.writer.print("line-{d}\n", .{i});
    }

    try std.testing.expectEqual(@as(u64, sink.buffered().len), counting.count);
}
