const boundary = "\nFrom ";
const msg_id_header = "Message-ID:";

// Binary index format (v1):
//   [8]    magic
//   [u64]  version
//   [u64]  chunk type 0x01 (message IDs)
//   [u64]  blob length
//   [...]  null-terminated message IDs, concatenated
//   [u64]  chunk type 0x02 (locations)
//   [u64]  entry count
//   [...]  {start: u64, end: u64} per message, ordered to match IDs
//
// All integers are little-endian.
const file_header = [_]u8{ 0x00, 0x08, 0x10, 'm', 'b', 'i', 'd', 'x' };
const file_version: u64 = 0x01;

const chunk_type_message_ids: u64 = 0x01;
const chunk_type_locations: u64 = 0x02;

const State = enum {
    start,
    from,
    headers,
    body,
};

const Event = enum {
    from_line,
    blank_line,
    other_line,
};

pub const Location = struct {
    start: u64,
    end: u64,
};

pub const MessageIdIterator = struct {
    offset: usize,
    list: *const std.ArrayListUnmanaged(u8),

    pub fn init(message_ids: *const std.ArrayListUnmanaged(u8)) MessageIdIterator {
        return .{ .offset = 0, .list = message_ids };
    }

    pub fn next(self: *MessageIdIterator) ?[]const u8 {
        const i = std.mem.indexOfScalarPos(u8, self.list.items, self.offset, 0) orelse return null;
        const message_id = self.list.items[self.offset..i];

        self.offset = i + 1;

        return message_id;
    }
};

message_ids: std.ArrayListUnmanaged(u8) = .empty,
locations: std.StringHashMapUnmanaged(Location) = .empty,

const Self = @This();

pub fn deinit(self: *Self, allocator: Allocator) void {
    self.locations.deinit(allocator);
    self.message_ids.deinit(allocator);
}

pub fn write(self: Self, writer: *std.io.Writer) !void {
    try writer.writeAll(&file_header);
    try writer.writeInt(u64, file_version, .little);

    try writer.writeInt(u64, chunk_type_message_ids, .little);
    try writer.writeInt(u64, self.message_ids.items.len, .little);
    try writer.writeAll(self.message_ids.items);

    try writer.writeInt(u64, chunk_type_locations, .little);
    try writer.writeInt(u64, self.locations.count(), .little);

    var iter: MessageIdIterator = .init(&self.message_ids);
    while (iter.next()) |id| {
        const loc = self.locations.get(id) orelse continue;
        try writer.writeInt(u64, loc.start, .little);
        try writer.writeInt(u64, loc.end, .little);
    }

    try writer.flush();
}

pub fn index(allocator: Allocator, file: File) !Self {
    var read_buf: [65535]u8 = undefined;
    var stream = file.readerStreaming(&read_buf);
    const reader = &stream.interface;

    var fsm = zigfsm.StateMachine(State, Event, .start).init();

    try fsm.addEventAndTransition(.from_line, .start, .from);

    try fsm.addEventAndTransition(.other_line, .from, .headers);

    try fsm.addEventAndTransition(.other_line, .headers, .headers);
    try fsm.addEventAndTransition(.blank_line, .headers, .body);
    try fsm.addEventAndTransition(.from_line, .headers, .from);

    try fsm.addEventAndTransition(.other_line, .body, .body);
    try fsm.addEventAndTransition(.blank_line, .body, .body);
    try fsm.addEventAndTransition(.from_line, .body, .from);

    var count: usize = 0;
    var start: usize = 0;
    var offset: usize = 0;

    var locations: std.ArrayListUnmanaged(Location) = .empty;
    defer locations.deinit(allocator);

    var message_ids: std.ArrayListUnmanaged(u8) = .empty;

    var seen_ids: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var iter = seen_ids.keyIterator();
        while (iter.next()) |id| {
            allocator.free(id.*);
        }
        seen_ids.deinit(allocator);
    }

    var current_hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var current_message_id: ?[]const u8 = null;
    var done = false;

    while (!done) {
        const line = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => blk: {
                done = true;
                break :blk reader.buffered();
            },
            else => return err,
        };

        if (std.mem.startsWith(u8, line, boundary[1..])) {
            _ = try fsm.do(.from_line);
        } else if (std.mem.trim(u8, line, &std.ascii.whitespace).len == 0) {
            _ = try fsm.do(.blank_line);
        } else {
            _ = try fsm.do(.other_line);
        }

        if (done or fsm.currentState() == .from) {
            if (count > 0) {
                const message_id: []const u8 = if (current_message_id) |id| id else blk: {
                    const hash_bytes = current_hash.finalResult();
                    break :blk &std.fmt.bytesToHex(&hash_bytes, .lower);
                };

                if (!seen_ids.contains(message_id)) {
                    try locations.append(allocator, .{
                        .start = start,
                        .end = offset,
                    });

                    if (done and std.mem.trim(u8, line, &std.ascii.whitespace).len > 0) {
                        current_hash.update(line);
                    }

                    try message_ids.ensureUnusedCapacity(allocator, message_id.len + 1);
                    message_ids.appendSliceAssumeCapacity(message_id);
                    message_ids.appendAssumeCapacity(0);

                    try seen_ids.putNoClobber(allocator, try allocator.dupe(u8, message_id), {});
                }

                if (current_message_id) |id| allocator.free(id);
            }

            start = offset;
            count += 1;
            current_hash = .init(.{});
            current_message_id = null;
        } else if (std.mem.trim(u8, line, &std.ascii.whitespace).len > 0) {
            current_hash.update(line);

            if (std.ascii.startsWithIgnoreCase(line, msg_id_header)) {
                const raw = std.mem.trim(u8, line[msg_id_header.len..], &std.ascii.whitespace);
                if (raw.len > 0) {
                    current_message_id = try allocator.dupe(u8, raw);
                }
            }
        }

        offset += line.len;
    }

    var result: Self = .{};
    result.message_ids = message_ids;

    var last_sentinel: usize = 0;
    for (locations.items) |location| {
        const i = std.mem.indexOfScalarPos(u8, message_ids.items, last_sentinel, 0).?;
        const message_id = message_ids.items[last_sentinel..i];

        if (!result.locations.contains(message_id)) {
            try result.locations.putNoClobber(allocator, message_id, location);
        }

        last_sentinel = i + 1;
    }

    return result;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Writer = std.io.Writer;

const zigfsm = @import("zigfsm");
