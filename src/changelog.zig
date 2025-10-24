const std = @import("std");
const types = @import("types.zig");
const git = @import("git.zig");

/// Group commits by type into sections
pub fn groupCommits(
    allocator: std.mem.Allocator,
    commits: []const types.Commit,
    config: *const types.Config,
) !std.ArrayList(types.Section) {
    var sections_map = std.AutoHashMap(types.CommitType, types.Section).init(allocator);
    defer {
        var it = sections_map.valueIterator();
        while (it.next()) |section| {
            section.deinit();
        }
        sections_map.deinit();
    }

    // Group commits by type
    for (commits) |commit| {
        // Skip excluded authors
        var should_skip = false;
        for (config.exclude_authors) |excluded| {
            if (std.mem.eql(u8, commit.author_name, excluded) or
                std.mem.eql(u8, commit.author_email, excluded))
            {
                should_skip = true;
                break;
            }
        }
        if (should_skip) continue;

        const entry = try sections_map.getOrPut(commit.commit_type);
        if (!entry.found_existing) {
            entry.value_ptr.* = types.Section.init(allocator, commit.commit_type);
        }

        // Duplicate commit for section
        const commit_copy = types.Commit{
            .hash = try allocator.dupe(u8, commit.hash),
            .short_hash = try allocator.dupe(u8, commit.short_hash),
            .author_name = try allocator.dupe(u8, commit.author_name),
            .author_email = try allocator.dupe(u8, commit.author_email),
            .date = try allocator.dupe(u8, commit.date),
            .message = try allocator.dupe(u8, commit.message),
            .commit_type = commit.commit_type,
            .scope = if (commit.scope) |s| try allocator.dupe(u8, s) else null,
            .description = try allocator.dupe(u8, commit.description),
            .breaking = commit.breaking,
            .body = if (commit.body) |b| try allocator.dupe(u8, b) else null,
        };

        try entry.value_ptr.commits.append(commit_copy);
    }

    // Convert map to sorted array
    var sections = std.ArrayList(types.Section).init(allocator);
    errdefer {
        for (sections.items) |*section| {
            section.deinit();
        }
        sections.deinit();
    }

    // Define section order
    const ordered_types = [_]types.CommitType{
        .feat,
        .fix,
        .perf,
        .refactor,
        .docs,
        .style,
        .test,
        .build,
        .ci,
        .chore,
        .revert,
        .unknown,
    };

    for (ordered_types) |commit_type| {
        if (sections_map.get(commit_type)) |section| {
            if (section.commits.items.len > 0) {
                // Create new section with copied commits
                var new_section = types.Section.init(allocator, commit_type);
                for (section.commits.items) |commit| {
                    const commit_copy = types.Commit{
                        .hash = try allocator.dupe(u8, commit.hash),
                        .short_hash = try allocator.dupe(u8, commit.short_hash),
                        .author_name = try allocator.dupe(u8, commit.author_name),
                        .author_email = try allocator.dupe(u8, commit.author_email),
                        .date = try allocator.dupe(u8, commit.date),
                        .message = try allocator.dupe(u8, commit.message),
                        .commit_type = commit.commit_type,
                        .scope = if (commit.scope) |s| try allocator.dupe(u8, s) else null,
                        .description = try allocator.dupe(u8, commit.description),
                        .breaking = commit.breaking,
                        .body = if (commit.body) |b| try allocator.dupe(u8, b) else null,
                    };
                    try new_section.commits.append(commit_copy);
                }
                try sections.append(new_section);
            }
        }
    }

    return sections;
}

/// Generate markdown changelog content
pub fn generateMarkdown(
    allocator: std.mem.Allocator,
    sections: []const types.Section,
    config: *const types.Config,
    from_ref: ?[]const u8,
    to_ref: []const u8,
) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    // Write date header if enabled
    if (config.include_dates) {
        const timestamp = std.time.timestamp();
        const epoch_seconds: i64 = @intCast(timestamp);
        const epoch_day = @divFloor(epoch_seconds, std.time.s_per_day);
        const year_day = @import("std").time.epoch.EpochDay{ .day = epoch_day };
        const year_and_day = year_day.calculateYearDay();
        const month_day = year_and_day.calculateMonthDay();

        try writer.print("## [{s}] - {d}-{d:0>2}-{d:0>2}\n\n", .{
            to_ref,
            year_and_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
        });
    } else {
        try writer.print("## [{s}]\n\n", .{to_ref});
    }

    // Write compare URL if available
    if (config.repo_url) |repo_url| {
        if (from_ref) |from| {
            const compare_url = try git.generateCompareUrl(allocator, repo_url, from, to_ref);
            defer allocator.free(compare_url);
            try writer.print("[{s}]: {s}\n\n", .{ to_ref, compare_url });
        }
    }

    // Write sections
    for (sections) |section| {
        if (section.commits.items.len == 0) continue;

        try writer.print("### {s}\n\n", .{section.title});

        for (section.commits.items) |commit| {
            // Format: - **scope**: description (hash)
            if (commit.scope) |scope| {
                try writer.print("- **{s}**: {s}", .{ scope, commit.description });
            } else {
                try writer.print("- {s}", .{commit.description});
            }

            // Add commit link if repo URL is available
            if (config.repo_url) |repo_url| {
                const commit_url = try git.generateCommitUrl(allocator, repo_url, commit.short_hash);
                defer allocator.free(commit_url);
                try writer.print(" ([{s}]({s}))", .{ commit.short_hash, commit_url });
            } else {
                try writer.print(" ({s})", .{commit.short_hash});
            }

            // Add breaking change indicator
            if (commit.breaking) {
                try writer.writeAll(" ⚠️ BREAKING");
            }

            try writer.writeAll("\n");
        }

        try writer.writeAll("\n");
    }

    return buffer.toOwnedSlice();
}

/// Get unique contributors from commits
pub fn getContributors(
    allocator: std.mem.Allocator,
    commits: []const types.Commit,
    config: *const types.Config,
) !std.ArrayList([]const u8) {
    var contributors_set = std.StringHashMap(void).init(allocator);
    defer contributors_set.deinit();

    for (commits) |commit| {
        // Skip excluded authors
        var should_skip = false;
        for (config.exclude_authors) |excluded| {
            if (std.mem.eql(u8, commit.author_name, excluded) or
                std.mem.eql(u8, commit.author_email, excluded))
            {
                should_skip = true;
                break;
            }
        }
        if (should_skip) continue;

        const contributor = if (config.hide_author_email)
            try allocator.dupe(u8, commit.author_name)
        else
            try std.fmt.allocPrint(allocator, "{s} <{s}>", .{ commit.author_name, commit.author_email });

        const entry = try contributors_set.getOrPut(contributor);
        if (entry.found_existing) {
            allocator.free(contributor);
        }
    }

    var contributors = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (contributors.items) |c| allocator.free(c);
        contributors.deinit();
    }

    var it = contributors_set.keyIterator();
    while (it.next()) |key| {
        try contributors.append(try allocator.dupe(u8, key.*));
    }

    return contributors;
}

/// Generate complete changelog
pub fn generateChangelog(
    allocator: std.mem.Allocator,
    dir: []const u8,
    config: *const types.Config,
) !types.ChangelogResult {
    // Verify git repository
    if (!try git.isGitRepository(allocator, dir)) {
        return error.NotAGitRepository;
    }

    // Determine from reference
    const from_ref = if (config.from_ref) |from|
        from
    else
        try git.getLatestTag(allocator, dir);

    defer {
        if (config.from_ref == null and from_ref != null) {
            allocator.free(from_ref.?);
        }
    }

    if (config.verbose) {
        if (from_ref) |from| {
            std.debug.print("Generating changelog from {s} to {s}\n", .{ from, config.to_ref });
        } else {
            std.debug.print("Generating changelog up to {s}\n", .{config.to_ref});
        }
    }

    // Get commits
    var commits = try git.getCommits(allocator, dir, from_ref, config.to_ref);
    defer {
        for (commits.items) |*commit| {
            commit.deinit(allocator);
        }
        commits.deinit();
    }

    if (config.verbose) {
        std.debug.print("Found {d} commits\n", .{commits.items.len});
    }

    // Group commits by type
    var sections = try groupCommits(allocator, commits.items, config);
    errdefer {
        for (sections.items) |*section| {
            section.deinit();
        }
        sections.deinit();
    }

    if (config.verbose) {
        std.debug.print("Generated {d} sections\n", .{sections.items.len});
    }

    // Generate markdown content
    const content = try generateMarkdown(allocator, sections.items, config, from_ref, config.to_ref);

    return types.ChangelogResult{
        .content = content,
        .sections = sections,
    };
}
