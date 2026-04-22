const std = @import("std");
const Io = std.Io;
const types = @import("types.zig");
const parser = @import("parser.zig");

/// Check if directory is a git repository
pub fn isGitRepository(allocator: std.mem.Allocator, io: Io, dir: []const u8) !bool {
    _ = allocator; // for compatibility
    var dir_fd = Io.Dir.cwd().openDir(io, dir, .{}) catch return false;
    defer dir_fd.close(io);

    dir_fd.access(io, ".git", .{}) catch return false;
    return true;
}

/// Get the latest git tag
pub fn getLatestTag(allocator: std.mem.Allocator, io: Io, dir: []const u8) !?[]const u8 {
    const result = runGitCommand(allocator, io, dir, &[_][]const u8{
        "git",
        "describe",
        "--tags",
        "--abbrev=0",
    }) catch return null; // No tags found
    defer allocator.free(result);

    if (result.len == 0) return null;

    // Trim newline
    const trimmed = std.mem.trim(u8, result, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    return try allocator.dupe(u8, trimmed);
}

/// Get repository URL from git config
pub fn getRepositoryUrl(allocator: std.mem.Allocator, io: Io, dir: []const u8) !?[]const u8 {
    const result = try runGitCommand(allocator, io, dir, &[_][]const u8{
        "git",
        "config",
        "--get",
        "remote.origin.url",
    });
    defer allocator.free(result);

    if (result.len == 0) return null;

    var trimmed = std.mem.trim(u8, result, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    // Convert SSH URLs to HTTPS
    if (std.mem.startsWith(u8, trimmed, "git@github.com:")) {
        const path = trimmed["git@github.com:".len..];
        const url = try std.fmt.allocPrint(allocator, "https://github.com/{s}", .{path});
        return url;
    }

    // Remove .git suffix
    if (std.mem.endsWith(u8, trimmed, ".git")) {
        trimmed = trimmed[0 .. trimmed.len - 4];
    }

    return try allocator.dupe(u8, trimmed);
}

/// Get git commits in a range
pub fn getCommits(
    allocator: std.mem.Allocator,
    io: Io,
    dir: []const u8,
    from_ref: ?[]const u8,
    to_ref: []const u8,
) !std.ArrayList(types.Commit) {
    const range = if (from_ref) |from|
        try std.fmt.allocPrint(allocator, "{s}..{s}", .{ from, to_ref })
    else
        try allocator.dupe(u8, to_ref);
    defer allocator.free(range);

    // Format: hash|short_hash|author_name|author_email|date|subject|body
    // Use special delimiter that's unlikely to appear in commit messages
    const separator = "|||";
    const commit_separator = "\x00COMMIT_SEP\x00"; // Null-byte based separator
    const format = "--pretty=format:%H" ++ separator ++ "%h" ++ separator ++ "%an" ++ separator ++ "%ae" ++ separator ++ "%ci" ++ separator ++ "%s" ++ separator ++ "%b" ++ commit_separator;

    const result = try runGitCommand(allocator, io, dir, &[_][]const u8{
        "git",
        "log",
        range,
        format,
        "--no-merges",
    });
    defer allocator.free(result);

    var commits: std.ArrayList(types.Commit) = .empty;
    errdefer {
        for (commits.items) |*commit| {
            commit.deinit(allocator);
        }
        commits.deinit(allocator);
    }

    var commit_blocks = std.mem.splitSequence(u8, result, commit_separator);
    while (commit_blocks.next()) |block| {
        const trimmed = std.mem.trim(u8, block, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        const commit = try parser.parseCommitLine(allocator, trimmed, separator);
        try commits.append(allocator, commit);
    }

    return commits;
}

/// Run a git command and return its output
fn runGitCommand(
    allocator: std.mem.Allocator,
    io: Io,
    dir: []const u8,
    argv: []const []const u8,
) ![]const u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = dir },
    });
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        if (result.stderr.len > 0) {
            std.debug.print("Git command failed: {s}\n", .{result.stderr});
        }
        allocator.free(result.stdout);
        return error.GitCommandFailed;
    }

    return result.stdout;
}

/// Generate compare URL for a commit range
pub fn generateCompareUrl(
    allocator: std.mem.Allocator,
    repo_url: []const u8,
    from_ref: []const u8,
    to_ref: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, repo_url, "github.com") != null) {
        return try std.fmt.allocPrint(allocator, "{s}/compare/{s}...{s}", .{ repo_url, from_ref, to_ref });
    }
    if (std.mem.indexOf(u8, repo_url, "gitlab.com") != null) {
        return try std.fmt.allocPrint(allocator, "{s}/-/compare/{s}...{s}", .{ repo_url, from_ref, to_ref });
    }
    return try std.fmt.allocPrint(allocator, "{s}/compare/{s}...{s}", .{ repo_url, from_ref, to_ref });
}

/// Generate commit URL
pub fn generateCommitUrl(
    allocator: std.mem.Allocator,
    repo_url: []const u8,
    hash: []const u8,
) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}/commit/{s}", .{ repo_url, hash });
}
