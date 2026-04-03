pub fn main() !void {
    try cli.execute(std.heap.page_allocator, mboxDelta);
}

fn writeDelta(base: MboxIndex, new: MboxIndex, src_file: std.fs.File, writer: *Writer) !usize {
    var count: usize = 0;
    var iter = new.locations.iterator();
    while (iter.next()) |entry| {
        if (!base.locations.contains(entry.key_ptr.*)) {
            const loc = entry.value_ptr.*;
            const len = loc.end - loc.start;

            try src_file.seekTo(loc.start);
            var src_buf: [65536]u8 = undefined;
            var src_reader = src_file.readerStreaming(&src_buf);
            try src_reader.interface.streamExact64(writer, len);
            try writer.writeByte('\n');

            count += 1;
        }
    }

    try writer.flush();
    return count;
}

fn mboxDelta() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const base_file = try std.fs.cwd().openFile(cli.config.base_mbox, .{});
    defer base_file.close();

    const new_file = try std.fs.cwd().openFile(cli.config.new_mbox, .{});
    defer new_file.close();

    var base_index: MboxIndex = try .index(allocator, base_file);
    defer base_index.deinit(allocator);

    var new_index: MboxIndex = try .index(allocator, new_file);
    defer new_index.deinit(allocator);

    // Re-open new file for seeking to message offsets
    const src_file = try std.fs.cwd().openFile(cli.config.new_mbox, .{});
    defer src_file.close();

    const output_file = try std.fs.cwd().createFile(cli.config.output, .{});
    defer output_file.close();
    var out_buf: [65536]u8 = undefined;
    var out_writer = output_file.writer(&out_buf);

    const new_count = try writeDelta(base_index, new_index, src_file, &out_writer.interface);

    const stderr = std.fs.File.stderr();
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = stderr.writer(&stderr_buf);
    try stderr_writer.interface.print("{d} new messages written to {s}\n", .{ new_count, cli.config.output });
    try stderr_writer.interface.flush();
}

const std = @import("std");
const File = std.fs.File;
const Writer = std.Io.Writer;

const cli = @import("cli.zig");
const MboxIndex = @import("mbox").Index;

const testing = std.testing;

const single_msg =
    \\From sender@example.com Mon Jan 1 00:00:00 2024
    \\Message-ID: <msg1@example.com>
    \\Subject: Test 1
    \\
    \\Body of message 1
;

const multi_msg =
    \\From sender@example.com Mon Jan 1 00:00:00 2024
    \\Message-ID: <msg1@example.com>
    \\Subject: Test 1
    \\
    \\Body of message 1
    \\
    \\From sender@example.com Tue Jan 2 00:00:00 2024
    \\Message-ID: <msg2@example.com>
    \\Subject: Test 2
    \\
    \\Body of message 2
    \\
    \\From sender@example.com Wed Jan 3 00:00:00 2024
    \\Message-ID: <msg3@example.com>
    \\Subject: Test 3
    \\
    \\Body of message 3
;

fn writeTmpMbox(tmp: *testing.TmpDir, name: []const u8, content: []const u8) !File {
    const file = try tmp.dir.createFile(name, .{ .read = true });
    try file.writeAll(content);
    try file.seekTo(0);
    return file;
}

fn loadTmpIndex(tmp: *testing.TmpDir, name: []const u8, content: []const u8) !struct { MboxIndex, File } {
    const file = try writeTmpMbox(tmp, name, content);
    const index: MboxIndex = try .index(testing.allocator, file);
    return .{ index, file };
}

test "load parses single message" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var index, const file = try loadTmpIndex(&tmp, "single.mbox", single_msg);
    defer index.deinit(testing.allocator);
    defer file.close();

    try testing.expectEqual(1, index.locations.count());
    try testing.expect(index.locations.contains("<msg1@example.com>"));
}

test "load parses multiple messages" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var index, const file = try loadTmpIndex(&tmp, "multi.mbox", multi_msg);
    defer index.deinit(testing.allocator);
    defer file.close();

    try testing.expectEqual(3, index.locations.count());
    try testing.expect(index.locations.contains("<msg1@example.com>"));
    try testing.expect(index.locations.contains("<msg2@example.com>"));
    try testing.expect(index.locations.contains("<msg3@example.com>"));

    // Verify locations don't overlap
    const loc1 = index.locations.get("<msg1@example.com>").?;
    const loc2 = index.locations.get("<msg2@example.com>").?;
    const loc3 = index.locations.get("<msg3@example.com>").?;
    try testing.expect(loc1.end <= loc2.start);
    try testing.expect(loc2.end <= loc3.start);
}

test "load indexes message without Message-ID using hash fallback" {
    const mbox =
        \\From sender@example.com Mon Jan 1 00:00:00 2024
        \\Subject: No ID
        \\
        \\Body without message id
        \\
        \\From sender@example.com Tue Jan 2 00:00:00 2024
        \\Message-ID: <has-id@example.com>
        \\Subject: Has ID
        \\
        \\Body with message id
    ;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var index, const file = try loadTmpIndex(&tmp, "noid.mbox", mbox);
    defer index.deinit(testing.allocator);
    defer file.close();

    try testing.expectEqual(2, index.locations.count());
    try testing.expect(index.locations.contains("<has-id@example.com>"));
}

test "writeDelta writes only new messages" {
    const base_mbox =
        \\From sender@example.com Mon Jan 1 00:00:00 2024
        \\Message-ID: <msg1@example.com>
        \\Subject: Test 1
        \\
        \\Body of message 1
        \\
        \\From sender@example.com Tue Jan 2 00:00:00 2024
        \\Message-ID: <msg2@example.com>
        \\Subject: Test 2
        \\
        \\Body of message 2
    ;

    const new_mbox =
        \\From sender@example.com Mon Jan 1 00:00:00 2024
        \\Message-ID: <msg1@example.com>
        \\Subject: Test 1
        \\
        \\Body of message 1
        \\
        \\From sender@example.com Tue Jan 2 00:00:00 2024
        \\Message-ID: <msg2@example.com>
        \\Subject: Test 2
        \\
        \\Body of message 2
        \\
        \\From sender@example.com Wed Jan 3 00:00:00 2024
        \\Message-ID: <msg3@example.com>
        \\Subject: Test 3
        \\
        \\Body of message 3
    ;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var base_index, const base_file = try loadTmpIndex(&tmp, "base.mbox", base_mbox);
    defer base_index.deinit(testing.allocator);
    defer base_file.close();

    var new_index, const new_file = try loadTmpIndex(&tmp, "new.mbox", new_mbox);
    defer new_index.deinit(testing.allocator);
    defer new_file.close();

    // Re-open for seeking in writeDelta
    const src_file = try tmp.dir.openFile("new.mbox", .{});
    defer src_file.close();

    var out_allocating: Writer.Allocating = .init(testing.allocator);
    defer out_allocating.deinit();

    const count = try writeDelta(base_index, new_index, src_file, &out_allocating.writer);
    const output = out_allocating.written();

    try testing.expectEqual(1, count);
    try testing.expect(std.mem.indexOf(u8, output, "<msg3@example.com>") != null);
    try testing.expect(std.mem.indexOf(u8, output, "<msg1@example.com>") == null);
    try testing.expect(std.mem.indexOf(u8, output, "<msg2@example.com>") == null);
}

test "writeDelta with no differences returns zero" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var index1, const file1 = try loadTmpIndex(&tmp, "a.mbox", single_msg);
    defer index1.deinit(testing.allocator);
    defer file1.close();

    var index2, const file2 = try loadTmpIndex(&tmp, "b.mbox", single_msg);
    defer index2.deinit(testing.allocator);
    defer file2.close();

    const src_file = try tmp.dir.openFile("b.mbox", .{});
    defer src_file.close();

    var out_allocating: Writer.Allocating = .init(testing.allocator);
    defer out_allocating.deinit();

    const count = try writeDelta(index1, index2, src_file, &out_allocating.writer);

    try testing.expectEqual(0, count);
    try testing.expectEqual(0, out_allocating.written().len);
}
