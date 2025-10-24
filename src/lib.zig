const std = @import("std");

pub const types = @import("types.zig");
pub const git = @import("git.zig");
pub const parser = @import("parser.zig");
pub const changelog = @import("changelog.zig");

// Re-export main types
pub const Commit = types.Commit;
pub const CommitType = types.CommitType;
pub const Section = types.Section;
pub const Config = types.Config;
pub const ChangelogResult = types.ChangelogResult;

// Re-export main functions
pub const generateChangelog = changelog.generateChangelog;
pub const isGitRepository = git.isGitRepository;
pub const getLatestTag = git.getLatestTag;
pub const getRepositoryUrl = git.getRepositoryUrl;

test {
    std.testing.refAllDecls(@This());
}
