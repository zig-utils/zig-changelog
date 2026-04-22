const std = @import("std");
const lib = @import("lib.zig");

const VERSION = "0.1.0";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Parse command line arguments via the new Init.minimal.args iterator.
    var config = lib.Config{};
    var show_help = false;
    var show_version = false;
    var dir: []const u8 = ".";

    var args = init.minimal.args.iterate();
    _ = args.skip(); // program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            show_version = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--from")) {
            config.from_ref = args.next() orelse return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--to")) {
            config.to_ref = args.next() orelse return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            config.output_file = args.next() orelse return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--dir")) {
            dir = args.next() orelse return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--hide-author-email")) {
            config.hide_author_email = true;
        } else if (std.mem.eql(u8, arg, "--no-dates")) {
            config.include_dates = false;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            std.debug.print("Use --help for usage information\n", .{});
            return error.InvalidArgument;
        }
    }

    if (show_version) {
        std.debug.print("changelog v{s}\n", .{VERSION});
        return;
    }

    if (show_help) {
        printHelp();
        return;
    }

    // Get repository URL for links
    const repo_url = try lib.getRepositoryUrl(allocator, io, dir);
    defer if (repo_url) |url| allocator.free(url);
    config.repo_url = repo_url;

    if (config.verbose) {
        std.debug.print("Starting changelog generation...\n", .{});
    }

    var result = try lib.generateChangelog(allocator, io, dir, &config);
    defer result.deinit(allocator);

    // Output changelog
    if (config.output_file) |output_file| {
        var file_content: std.ArrayList(u8) = .empty;
        defer file_content.deinit(allocator);

        const cwd = std.Io.Dir.cwd();
        const existing = cwd.readFileAlloc(io, output_file, allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| blk: {
            if (err == error.FileNotFound) {
                try file_content.appendSlice(allocator, "# Changelog\n\n");
                break :blk null;
            }
            return err;
        };
        defer if (existing) |e| allocator.free(e);

        if (existing) |content| {
            if (std.mem.indexOf(u8, content, "\n## ")) |idx| {
                try file_content.appendSlice(allocator, content[0 .. idx + 1]);
                try file_content.appendSlice(allocator, result.content);
                try file_content.appendSlice(allocator, "\n");
                try file_content.appendSlice(allocator, content[idx + 1 ..]);
            } else {
                try file_content.appendSlice(allocator, content);
                if (!std.mem.endsWith(u8, content, "\n\n")) {
                    try file_content.appendSlice(allocator, "\n");
                }
                try file_content.appendSlice(allocator, result.content);
            }
        } else {
            try file_content.appendSlice(allocator, result.content);
        }

        try cwd.writeFile(io, .{ .sub_path = output_file, .data = file_content.items });

        if (config.verbose) {
            std.debug.print("Changelog written to {s}\n", .{output_file});
        } else {
            std.debug.print("Changelog written to {s}\n", .{output_file});
        }
    } else {
        // Print to stdout via std.debug since std.fs.File/STDOUT_FILENO
        // are not the right path on 0.17-dev anymore.
        std.debug.print("{s}", .{result.content});
    }
}

fn printHelp() void {
    const help =
        \\changelog - Generate beautiful changelogs from conventional commits
        \\
        \\Usage:
        \\  changelog [options]
        \\
        \\Options:
        \\  -h, --help              Show this help message
        \\  -v, --version           Show version information
        \\  --verbose               Enable verbose logging
        \\  --from <ref>            Start commit reference (default: latest git tag)
        \\  --to <ref>              End commit reference (default: HEAD)
        \\  --dir <dir>             Path to git repository (default: current directory)
        \\  -o, --output <file>     Output file (default: stdout)
        \\  --hide-author-email     Hide author email addresses
        \\  --no-dates              Don't include dates in changelog
        \\
        \\Examples:
        \\  changelog                              Generate and display changelog
        \\  changelog -o CHANGELOG.md              Write to CHANGELOG.md
        \\  changelog --from v1.0.0 --to HEAD      Generate from v1.0.0 to HEAD
        \\  changelog --verbose -o CHANGELOG.md    Verbose output to file
        \\
    ;
    std.debug.print("{s}\n", .{help});
}
