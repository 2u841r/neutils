pub var config: Config = .{
    .size = "",
    .output = "",
    .seed = 0,
    .body_size = 1024,
    .with_id_ratio = 1.0,
    .force = false,
};

pub fn execute(allocator: Allocator, exec_fn: ExecFn) !void {
    var runner = try AppRunner.init(allocator);

    const app: App = .{
        .version = build_options.version,
        .command = Command{
            .name = "mbox-gen",

            .options = &[_]Option{
                .{
                    .long_name = "size",
                    .short_alias = 's',
                    .help = "Target output size (e.g. 100M, 1GiB, 4096)",
                    .required = true,
                    .value_ref = runner.mkRef(&config.size),
                },
                .{
                    .long_name = "seed",
                    .help = "PRNG seed (default 0)",
                    .value_ref = runner.mkRef(&config.seed),
                },
                .{
                    .long_name = "body-size",
                    .help = "Body bytes per message (default 1024)",
                    .value_ref = runner.mkRef(&config.body_size),
                },
                .{
                    .long_name = "with-id-ratio",
                    .help = "Fraction of messages that include a Message-ID header (default 1.0)",
                    .value_ref = runner.mkRef(&config.with_id_ratio),
                },
                .{
                    .long_name = "force",
                    .short_alias = 'f',
                    .help = "Overwrite the output file if it exists",
                    .value_ref = runner.mkRef(&config.force),
                },
            },

            .target = cli.CommandTarget{
                .action = cli.CommandAction{
                    .exec = exec_fn,
                    .positional_args = cli.PositionalArgs{
                        .required = &[_]cli.PositionalArg{
                            .{
                                .name = "output",
                                .help = "Destination mbox file",
                                .value_ref = runner.mkRef(&config.output),
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
