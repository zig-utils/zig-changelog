# zig-changelog

A Zig library and CLI tool for generating beautiful changelogs from conventional commits.

## Features

- 🚀 **Automatic changelog generation** from conventional commits
- 🎨 **Beautiful formatting** with emojis and proper grouping
- 📝 **Conventional commits** parsing and analysis
- 🔗 **Git repository integration** with commit and compare URLs
- ⚡ **Fast and lightweight** - written in Zig
- 📦 **Both library and CLI** - use programmatically or from command line
- 🔧 **Highly configurable** with sensible defaults

## Installation

### From Source

```bash
git clone https://github.com/yourusername/zig-changelog.git
cd zig-changelog
zig build
```

The binary will be available at `zig-out/bin/changelog`.

### Add to PATH

```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
export PATH="$PATH:/path/to/zig-changelog/zig-out/bin"
```

## Quick Start

### CLI Usage

Generate a changelog and display in console:

```bash
changelog
```

Generate a changelog and save to CHANGELOG.md:

```bash
changelog -o CHANGELOG.md
```

Generate changelog from specific commit range:

```bash
changelog --from v1.0.0 --to HEAD -o CHANGELOG.md
```

### Programmatic Usage

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .changelog = .{
        .url = "https://github.com/yourusername/zig-changelog/archive/main.tar.gz",
        .hash = "...",
    },
},
```

Use in your code:

```zig
const std = @import("std");
const changelog = @import("changelog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = changelog.Config{
        .from_ref = "v1.0.0",
        .to_ref = "HEAD",
        .verbose = true,
    };

    var result = try changelog.generateChangelog(allocator, ".", &config);
    defer result.deinit(allocator);

    std.debug.print("{s}\n", .{result.content});
}
```

## CLI Options

```
Options:
  -h, --help              Show help message
  -v, --version           Show version information
  --verbose               Enable verbose logging
  --from <ref>            Start commit reference (default: latest git tag)
  --to <ref>              End commit reference (default: HEAD)
  --dir <dir>             Path to git repository (default: current directory)
  -o, --output <file>     Output file (default: stdout)
  --hide-author-email     Hide author email addresses
  --no-dates              Don't include dates in changelog
```

## Examples

### Basic Usage

```bash
# Generate and display changelog
changelog

# Write to file
changelog -o CHANGELOG.md

# Generate from specific tag
changelog --from v1.0.0 -o CHANGELOG.md

# Generate with verbose output
changelog --verbose -o CHANGELOG.md
```

### Integration with Release Flow

In your release script:

```bash
#!/bin/bash

# Generate changelog
changelog --from $(git describe --tags --abbrev=0) -o CHANGELOG.md

# Review the changelog
cat CHANGELOG.md

# Commit and tag
git add CHANGELOG.md
git commit -m "chore: update changelog"
git tag -a v1.2.3 -m "Release v1.2.3"
git push && git push --tags
```

## Conventional Commits

zig-changelog parses conventional commits and groups them by type:

```
feat: add new authentication system
fix: resolve memory leak in parser
docs: update API documentation
style: fix code formatting
refactor: simplify user service
perf: optimize database queries
test: add integration tests
build: update dependencies
ci: improve GitHub Actions workflow
chore: update development tools
```

### Breaking Changes

Breaking changes are detected and highlighted:

```
feat!: remove deprecated API endpoints
feat: add new feature

BREAKING CHANGE: The old API has been removed
```

## Output Format

The generated changelog follows this format:

```markdown
## [v1.2.3] - 2024-01-15

[v1.2.3]: https://github.com/user/repo/compare/v1.2.2...v1.2.3

### 🚀 Features

- **auth**: add OAuth integration ([abc123d](https://github.com/user/repo/commit/abc123d))
- **api**: implement rate limiting ([def456a](https://github.com/user/repo/commit/def456a))

### 🐛 Bug Fixes

- **parser**: fix memory leak in token processing ([ghi789b](https://github.com/user/repo/commit/ghi789b))

### 📚 Documentation

- update API documentation ([jkl012c](https://github.com/user/repo/commit/jkl012c))
```

## API Reference

### Types

#### `Config`

Configuration options for changelog generation:

```zig
pub const Config = struct {
    from_ref: ?[]const u8 = null,        // Start commit reference
    to_ref: []const u8 = "HEAD",         // End commit reference
    output_file: ?[]const u8 = null,     // Output file path
    verbose: bool = false,                // Enable verbose logging
    hide_author_email: bool = false,      // Hide author emails
    exclude_authors: []const []const u8 = &[_][]const u8{}, // Authors to exclude
    include_dates: bool = true,           // Include dates in output
    group_breaking_changes: bool = true,  // Group breaking changes
    repo_url: ?[]const u8 = null,        // Repository URL for links
};
```

#### `Commit`

Parsed commit information:

```zig
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
};
```

#### `CommitType`

Enum of conventional commit types:

```zig
pub const CommitType = enum {
    feat,
    fix,
    docs,
    style,
    refactor,
    perf,
    test,
    build,
    ci,
    chore,
    revert,
    unknown,
};
```

### Functions

#### `generateChangelog`

```zig
pub fn generateChangelog(
    allocator: std.mem.Allocator,
    dir: []const u8,
    config: *const Config,
) !ChangelogResult
```

Generate a changelog from git commits.

#### `isGitRepository`

```zig
pub fn isGitRepository(
    allocator: std.mem.Allocator,
    dir: []const u8,
) !bool
```

Check if a directory is a git repository.

#### `getLatestTag`

```zig
pub fn getLatestTag(
    allocator: std.mem.Allocator,
    dir: []const u8,
) !?[]const u8
```

Get the latest git tag in the repository.

## Building

### Build the CLI

```bash
zig build
```

### Run Tests

```bash
zig build test
```

### Build for Release

```bash
zig build -Doptimize=ReleaseFast
```

### Install Locally

```bash
zig build install
```

## Development

### Project Structure

```
zig-changelog/
├── build.zig           # Build configuration
├── src/
│   ├── main.zig        # CLI entry point
│   ├── lib.zig         # Library entry point
│   ├── types.zig       # Core types and structures
│   ├── git.zig         # Git operations
│   ├── parser.zig      # Commit parser
│   └── changelog.zig   # Changelog generator
└── README.md
```

### Running Tests

```bash
zig build test
```

## Comparison with logsmith

This tool is inspired by [logsmith](https://github.com/stacksjs/logsmith) but implemented in Zig for:

- **Performance**: Native Zig performance without runtime overhead
- **Portability**: Single binary with no dependencies
- **Memory Safety**: Zig's compile-time memory safety guarantees
- **Simplicity**: Focused on core changelog generation features

## License

MIT License - see LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
