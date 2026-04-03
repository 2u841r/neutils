pub var config: Config = .{
    .mbox = "",
    .output = "",
};

pub fn execute(allocator: Allocator, exec_fn: ExecFn) !void {
    var runner = try AppRunner.init(allocator);

    const app: App = .{
        .version = build_options.version,
        .command = Command{
            .name = "mbox-index",

            .options = &[_]Option{
                .{
                    .long_name = "output",
                    .short_alias = 'o',
                    .help = "Output file",
                    .value_ref = runner.mkRef(&config.output),
                },
            },

            .target = cli.CommandTarget{
                .action = cli.CommandAction{
                    .exec = exec_fn,
                    .positional_args = cli.PositionalArgs{
                        .required = &[_]cli.PositionalArg{
                            .{
                                .name = "mbox",
                                .help = "Mbox file to index",
                                .value_ref = runner.mkRef(&config.mbox),
                            },
                        },
                    },
                },
            },
        },
    };

    return runner.run(&app);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const cli = @import("cli");
const App = cli.App;
const AppRunner = cli.AppRunner;
const ExecFn = cli.ExecFn;
const Option = cli.Option;
const Command = cli.Command;

const build_options = @import("build_options");

const Config = @import("Config.zig");
