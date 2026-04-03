pub fn main() !void {
    try cli.execute(std.heap.page_allocator, mboxIndex);
}

fn mboxIndex() !void {
    var arena: ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var mbox_file = try std.fs.cwd().openFile(cli.config.mbox, .{});
    defer mbox_file.close();

    var index: Index = try .index(allocator, mbox_file);
    defer index.deinit(allocator);

    const output_path = blk: {
        const cli_output = std.mem.trim(u8, cli.config.output, &std.ascii.whitespace);
        if (cli_output.len > 0) {
            break :blk try allocator.dupe(u8, cli_output);
        }

        const mbox_basename = std.fs.path.stem(cli.config.mbox);

        break :blk try std.fmt.allocPrint(allocator, "{f}.mbox-index", .{
            std.fs.path.fmtJoin(&.{ std.fs.path.dirname(cli.config.mbox) orelse ".", mbox_basename }),
        });
    };

    const output_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer output_file.close();

    var output_buf: [4096]u8 = undefined;
    var stream = output_file.writer(&output_buf);
    var writer = &stream.interface;

    try index.write(writer);
    try writer.flush();
}

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const File = std.fs.File;

const cli = @import("cli.zig");

const mbox = @import("mbox");
const Index = mbox.Index;
