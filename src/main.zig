const std = @import("std");
const lib = @import("lib.zig");

const VERSION = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line arguments
    var config = lib.Config{};
    var show_help = false;
    var show_version = false;
    var dir: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            show_version = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--from")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --from requires an argument\n", .{});
                return error.InvalidArgument;
            }
            config.from_ref = args[i];
        } else if (std.mem.eql(u8, arg, "--to")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --to requires an argument\n", .{});
                return error.InvalidArgument;
            }
            config.to_ref = args[i];
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --output requires an argument\n", .{});
                return error.InvalidArgument;
            }
            config.output_file = args[i];
        } else if (std.mem.eql(u8, arg, "--dir")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --dir requires an argument\n", .{});
                return error.InvalidArgument;
            }
            dir = args[i];
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
    const repo_url = try lib.getRepositoryUrl(allocator, dir);
    defer if (repo_url) |url| allocator.free(url);
    config.repo_url = repo_url;

    // Generate changelog
    if (config.verbose) {
        std.debug.print("Starting changelog generation...\n", .{});
    }

    var result = try lib.generateChangelog(allocator, dir, &config);
    defer result.deinit(allocator);

    // Output changelog
    if (config.output_file) |output_file| {
        // Read existing changelog if it exists
        var file_content: std.ArrayList(u8) = .{};
        defer file_content.deinit(allocator);

        const file = std.fs.cwd().openFile(output_file, .{}) catch |err| blk: {
            if (err == error.FileNotFound) {
                // Create new file with header
                try file_content.writer(allocator).writeAll("# Changelog\n\n");
                break :blk null;
            }
            return err;
        };

        if (file) |f| {
            defer f.close();
            const existing_content = try f.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(existing_content);

            // Find first ## or end of file to insert new changelog
            if (std.mem.indexOf(u8, existing_content, "\n## ")) |idx| {
                try file_content.writer(allocator).writeAll(existing_content[0 .. idx + 1]);
                try file_content.writer(allocator).writeAll(result.content);
                try file_content.writer(allocator).writeAll("\n");
                try file_content.writer(allocator).writeAll(existing_content[idx + 1 ..]);
            } else {
                try file_content.writer(allocator).writeAll(existing_content);
                if (!std.mem.endsWith(u8, existing_content, "\n\n")) {
                    try file_content.writer(allocator).writeAll("\n");
                }
                try file_content.writer(allocator).writeAll(result.content);
            }
        } else {
            try file_content.writer(allocator).writeAll(result.content);
        }

        // Write to file
        const out_file = try std.fs.cwd().createFile(output_file, .{});
        defer out_file.close();
        try out_file.writeAll(file_content.items);

        if (config.verbose) {
            std.debug.print("✨ Changelog written to {s}\n", .{output_file});
        } else {
            std.debug.print("Changelog written to {s}\n", .{output_file});
        }
    } else {
        // Print to stdout
        const stdout_file = std.posix.STDOUT_FILENO;
        const stdout = std.fs.File{ .handle = stdout_file };
        try stdout.writeAll(result.content);
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
