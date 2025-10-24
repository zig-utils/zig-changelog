const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");

/// Check if directory is a git repository
pub fn isGitRepository(allocator: std.mem.Allocator, dir: []const u8) !bool {
    const git_dir = try std.fs.path.join(allocator, &[_][]const u8{ dir, ".git" });
    defer allocator.free(git_dir);

    std.fs.accessAbsolute(git_dir, .{}) catch return false;
    return true;
}

/// Get the latest git tag
pub fn getLatestTag(allocator: std.mem.Allocator, dir: []const u8) !?[]const u8 {
    const result = try runGitCommand(allocator, dir, &[_][]const u8{
        "git",
        "describe",
        "--tags",
        "--abbrev=0",
    });
    defer allocator.free(result);

    if (result.len == 0) return null;

    // Trim newline
    const trimmed = std.mem.trim(u8, result, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    return try allocator.dupe(u8, trimmed);
}

/// Get repository URL from git config
pub fn getRepositoryUrl(allocator: std.mem.Allocator, dir: []const u8) !?[]const u8 {
    const result = try runGitCommand(allocator, dir, &[_][]const u8{
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
    const separator = "|||";
    const format = "--pretty=format:%H" ++ separator ++ "%h" ++ separator ++ "%an" ++ separator ++ "%ae" ++ separator ++ "%ci" ++ separator ++ "%s" ++ separator ++ "%b";

    const result = try runGitCommand(allocator, dir, &[_][]const u8{
        "git",
        "log",
        range,
        format,
        "--no-merges",
    });
    defer allocator.free(result);

    var commits = std.ArrayList(types.Commit).init(allocator);
    errdefer {
        for (commits.items) |*commit| {
            commit.deinit(allocator);
        }
        commits.deinit();
    }

    var lines = std.mem.split(u8, result, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const commit = try parser.parseCommitLine(allocator, line, separator);
        try commits.append(commit);
    }

    return commits;
}

/// Run a git command and return its output
fn runGitCommand(
    allocator: std.mem.Allocator,
    dir: []const u8,
    argv: []const []const u8,
) ![]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.cwd = dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(stderr);

    const term = try child.wait();

    if (term != .Exited or term.Exited != 0) {
        if (stderr.len > 0) {
            std.debug.print("Git command failed: {s}\n", .{stderr});
        }
        allocator.free(stdout);
        return error.GitCommandFailed;
    }

    return stdout;
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
