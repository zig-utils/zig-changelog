const std = @import("std");
const types = @import("types.zig");

/// Parse a conventional commit message
pub fn parseConventionalCommit(
    allocator: std.mem.Allocator,
    message: []const u8,
) !struct {
    commit_type: types.CommitType,
    scope: ?[]const u8,
    description: []const u8,
    breaking: bool,
} {
    var breaking = false;
    var commit_type = types.CommitType.unknown;
    var scope: ?[]const u8 = null;
    var description: []const u8 = message;

    // Check for breaking change indicator (!)
    if (std.mem.indexOf(u8, message, "!:")) |idx| {
        breaking = true;
        const type_part = std.mem.trim(u8, message[0..idx], &std.ascii.whitespace);

        // Parse type and scope
        if (std.mem.indexOf(u8, type_part, "(")) |scope_start| {
            const type_str = type_part[0..scope_start];
            commit_type = types.CommitType.fromString(type_str);

            if (std.mem.indexOf(u8, type_part[scope_start..], ")")) |scope_end| {
                const scope_str = type_part[scope_start + 1 .. scope_start + scope_end];
                scope = try allocator.dupe(u8, scope_str);
            }
        } else {
            commit_type = types.CommitType.fromString(type_part);
        }

        description = std.mem.trim(u8, message[idx + 2 ..], &std.ascii.whitespace);
    }
    // Check for regular conventional commit format
    else if (std.mem.indexOf(u8, message, ":")) |idx| {
        const type_part = std.mem.trim(u8, message[0..idx], &std.ascii.whitespace);

        // Parse type and scope
        if (std.mem.indexOf(u8, type_part, "(")) |scope_start| {
            const type_str = type_part[0..scope_start];
            commit_type = types.CommitType.fromString(type_str);

            if (std.mem.indexOf(u8, type_part[scope_start..], ")")) |scope_end| {
                const scope_str = type_part[scope_start + 1 .. scope_start + scope_end];
                scope = try allocator.dupe(u8, scope_str);
            }
        } else {
            commit_type = types.CommitType.fromString(type_part);
        }

        description = std.mem.trim(u8, message[idx + 1 ..], &std.ascii.whitespace);
    }

    // Check for BREAKING CHANGE in message
    if (std.mem.indexOf(u8, message, "BREAKING CHANGE")) |_| {
        breaking = true;
    }

    return .{
        .commit_type = commit_type,
        .scope = scope,
        .description = try allocator.dupe(u8, description),
        .breaking = breaking,
    };
}

/// Parse a commit line from git log output
pub fn parseCommitLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    separator: []const u8,
) !types.Commit {
    var parts = std.mem.split(u8, line, separator);

    const hash = parts.next() orelse return error.InvalidCommitFormat;
    const short_hash = parts.next() orelse return error.InvalidCommitFormat;
    const author_name = parts.next() orelse return error.InvalidCommitFormat;
    const author_email = parts.next() orelse return error.InvalidCommitFormat;
    const date = parts.next() orelse return error.InvalidCommitFormat;
    const message = parts.next() orelse return error.InvalidCommitFormat;
    const body = parts.next();

    // Parse conventional commit
    const parsed = try parseConventionalCommit(allocator, message);

    return types.Commit{
        .hash = try allocator.dupe(u8, hash),
        .short_hash = try allocator.dupe(u8, short_hash),
        .author_name = try allocator.dupe(u8, author_name),
        .author_email = try allocator.dupe(u8, author_email),
        .date = try allocator.dupe(u8, date),
        .message = try allocator.dupe(u8, message),
        .commit_type = parsed.commit_type,
        .scope = parsed.scope,
        .description = parsed.description,
        .breaking = parsed.breaking,
        .body = if (body != null and body.?.len > 0)
            try allocator.dupe(u8, body.?)
        else
            null,
    };
}

test "parse conventional commit - feat" {
    const allocator = std.testing.allocator;
    const result = try parseConventionalCommit(allocator, "feat: add new feature");
    defer allocator.free(result.description);
    defer if (result.scope) |s| allocator.free(s);

    try std.testing.expectEqual(types.CommitType.feat, result.commit_type);
    try std.testing.expectEqual(@as(?[]const u8, null), result.scope);
    try std.testing.expectEqualStrings("add new feature", result.description);
    try std.testing.expectEqual(false, result.breaking);
}

test "parse conventional commit - feat with scope" {
    const allocator = std.testing.allocator;
    const result = try parseConventionalCommit(allocator, "feat(api): add authentication");
    defer allocator.free(result.description);
    defer if (result.scope) |s| allocator.free(s);

    try std.testing.expectEqual(types.CommitType.feat, result.commit_type);
    try std.testing.expectEqualStrings("api", result.scope.?);
    try std.testing.expectEqualStrings("add authentication", result.description);
    try std.testing.expectEqual(false, result.breaking);
}

test "parse conventional commit - breaking change" {
    const allocator = std.testing.allocator;
    const result = try parseConventionalCommit(allocator, "feat!: remove deprecated API");
    defer allocator.free(result.description);
    defer if (result.scope) |s| allocator.free(s);

    try std.testing.expectEqual(types.CommitType.feat, result.commit_type);
    try std.testing.expectEqual(@as(?[]const u8, null), result.scope);
    try std.testing.expectEqualStrings("remove deprecated API", result.description);
    try std.testing.expectEqual(true, result.breaking);
}
