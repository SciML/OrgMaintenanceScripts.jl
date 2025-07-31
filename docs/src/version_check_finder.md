# Version Check Finder

The Version Check Finder functionality helps identify and remove obsolete Julia version compatibility checks from your codebase.

## Overview

When Julia releases new versions, older version checks become obsolete. For example, with Julia 1.10 as the current LTS, checks for versions older than 1.10 are no longer needed. This module helps you:

 1. Find obsolete version checks
 2. Generate scripts to review them
 3. Automatically create PRs to remove them

## Functions

### Finding Version Checks

```julia
find_version_checks_in_file(filepath::String; min_version::VersionNumber = v"1.10")
```

Find version checks in a single file that compare against versions older than `min_version`.

```julia
find_version_checks_in_repo(repo_path::String; min_version::VersionNumber = v"1.10",
    ignore_dirs = ["test", "docs", ".git"])
```

Find version checks in an entire repository.

```julia
find_version_checks_in_org(org::String; min_version::VersionNumber = v"1.10",
    auth_token::String = "", work_dir::String = mktempdir())
```

Find version checks across all repositories in a GitHub organization.

### Writing Results to Scripts

```julia
write_version_checks_to_script(checks::Vector{VersionCheck}, output_file::String = "fix_version_checks.jl")
```

Write version check results to an executable Julia script for review and manual fixes.

```julia
write_org_version_checks_to_script(org_results::Dict{String, Vector{VersionCheck}},
    output_file::String = "fix_org_version_checks.jl")
```

Write organization-wide results to a script.

### Automated Fixing

```julia
fix_version_checks_parallel(checks::Vector{VersionCheck}, n_processes::Int = 4;
    github_token::String = "", base_branch::String = "main")
```

Fix version checks in parallel using N processes. Each process creates a PR to remove obsolete checks.

```julia
fix_org_version_checks_parallel(org::String, n_processes::Int = 4;
    min_version::VersionNumber = v"1.10", github_token::String = "")
```

Find and fix version checks across an entire organization using parallel processing.

## Supported Patterns

The finder detects these version check patterns:

  - `if VERSION >= v"1.6"`
  - `@static if VERSION > v"1.8.0"`
  - `VERSION <= v"1.9"`
  - `VERSION == v"1.7"`
  - `VERSION >= VersionNumber("1.6")`

## Usage Examples

### Find checks in a single repository

```julia
using OrgMaintenanceScripts

# Find all version checks older than Julia 1.10
checks = find_version_checks_in_repo("/path/to/repo")

# Write results to a script
write_version_checks_to_script(checks, "fix_my_checks.jl")
```

### Process an entire organization

```julia
# Set up GitHub token
github_token = ENV["GITHUB_TOKEN"]

# Find and fix all obsolete version checks
results = fix_org_version_checks_parallel("JuliaLang", 4;
    github_token = github_token,
    min_version = v"1.10"
)
```

### Custom minimum version

```julia
# Find checks older than Julia 1.11
checks = find_version_checks_in_repo("/path/to/repo"; min_version = v"1.11")
```

## Best Practices

 1. Always review the generated scripts before applying fixes
 2. Test your code after removing version checks
 3. Consider keeping version checks in test files for compatibility testing
 4. Use GitHub authentication for better API rate limits
 5. Start with a single repository before processing entire organizations
