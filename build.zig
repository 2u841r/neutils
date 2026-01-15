const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var tools_dir = std.fs.cwd().openDir("src/tools", .{ .iterate = true }) catch {
        return;
    };
    defer tools_dir.close();

    var iter = tools_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".zig")) continue;

        const tool_name = name[0 .. name.len - 4];
        const path = b.fmt("src/tools/{s}", .{name});

        const exe = b.addExecutable(.{
            .name = tool_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });

        b.installArtifact(exe);

        const build_step = b.step(tool_name, b.fmt("Build {s}", .{tool_name}));
        build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }
}
