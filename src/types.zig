const std = @import("std");

/// Commit type based on conventional commits
pub const CommitType = enum {
    feat,
    fix,
    docs,
    @"style",
    refactor,
    perf,
    @"test",
    build,
    ci,
    chore,
    revert,
    unknown,

    pub fn toString(self: CommitType) []const u8 {
        return switch (self) {
            .feat => "feat",
            .fix => "fix",
            .docs => "docs",
            .@"style" => "style",
            .refactor => "refactor",
            .perf => "perf",
            .@"test" => "test",
            .build => "build",
            .ci => "ci",
            .chore => "chore",
            .revert => "revert",
            .unknown => "unknown",
        };
    }

    pub fn fromString(str: []const u8) CommitType {
        if (std.mem.eql(u8, str, "feat")) return .feat;
        if (std.mem.eql(u8, str, "fix")) return .fix;
        if (std.mem.eql(u8, str, "docs")) return .docs;
        if (std.mem.eql(u8, str, "style")) return .@"style";
        if (std.mem.eql(u8, str, "refactor")) return .refactor;
        if (std.mem.eql(u8, str, "perf")) return .perf;
        if (std.mem.eql(u8, str, "test")) return .@"test";
        if (std.mem.eql(u8, str, "build")) return .build;
        if (std.mem.eql(u8, str, "ci")) return .ci;
        if (std.mem.eql(u8, str, "chore")) return .chore;
        if (std.mem.eql(u8, str, "revert")) return .revert;
        return .unknown;
    }

    pub fn getTitle(self: CommitType) []const u8 {
        return switch (self) {
            .feat => "🚀 Features",
            .fix => "🐛 Bug Fixes",
            .docs => "📚 Documentation",
            .@"style" => "💅 Styles",
            .refactor => "♻️ Code Refactoring",
            .perf => "⚡ Performance Improvements",
            .@"test" => "🧪 Tests",
            .build => "📦 Build System",
            .ci => "🤖 Continuous Integration",
            .chore => "🧹 Chores",
            .revert => "⏪ Reverts",
            .unknown => "Other Changes",
        };
    }
};

/// Parsed commit information
pub const Commit = struct {
    hash: []const u8,
    short_hash: []const u8,
    author_name: []const u8,
    author_email: []const u8,
    date: []const u8,
    message: []const u8,
    commit_type: CommitType,
    scope: ?[]const u8,
    description: []const u8,
    breaking: bool,
    body: ?[]const u8,

    pub fn deinit(self: *Commit, allocator: std.mem.Allocator) void {
        allocator.free(self.hash);
        allocator.free(self.short_hash);
        allocator.free(self.author_name);
        allocator.free(self.author_email);
        allocator.free(self.date);
        allocator.free(self.message);
        allocator.free(self.description);
        if (self.scope) |scope| allocator.free(scope);
        if (self.body) |body| allocator.free(body);
    }
};

/// Section grouping commits by type
pub const Section = struct {
    commit_type: CommitType,
    title: []const u8,
    commits: std.ArrayList(Commit),

    pub fn init(allocator: std.mem.Allocator, commit_type: CommitType) Section {
        return Section{
            .commit_type = commit_type,
            .title = commit_type.getTitle(),
            .commits = std.ArrayList(Commit).init(allocator),
        };
    }

    pub fn deinit(self: *Section) void {
        for (self.commits.items) |*commit| {
            commit.deinit(self.commits.allocator);
        }
        self.commits.deinit();
    }
};

/// Configuration options for changelog generation
pub const Config = struct {
    from_ref: ?[]const u8 = null,
    to_ref: []const u8 = "HEAD",
    output_file: ?[]const u8 = null,
    verbose: bool = false,
    hide_author_email: bool = false,
    exclude_authors: []const []const u8 = &[_][]const u8{},
    include_dates: bool = true,
    group_breaking_changes: bool = true,
    repo_url: ?[]const u8 = null,
};

/// Result of changelog generation
pub const ChangelogResult = struct {
    content: []const u8,
    sections: std.ArrayList(Section),

    pub fn deinit(self: *ChangelogResult, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        for (self.sections.items) |*section| {
            section.deinit();
        }
        self.sections.deinit();
    }
};
