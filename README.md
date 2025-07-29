# OrgMaintenanceScripts.jl

[![Build Status](https://github.com/SciML/OrgMaintenanceScripts.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SciML/OrgMaintenanceScripts.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/SciML/OrgMaintenanceScripts.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/SciML/OrgMaintenanceScripts.jl)

Automated maintenance scripts for managing repositories across the SciML organization.

## Features

### Code Formatting

Automatically format Julia code across entire organizations using JuliaFormatter:

```julia
using OrgMaintenanceScripts

# Format a single repository
success, message, pr_url = format_repository(
    "https://github.com/SciML/Example.jl.git";
    fork_user = "myusername"
)

# Format all repositories with failing formatter CI
successes, failures, pr_urls = format_org_repositories(
    "SciML";
    fork_user = "myusername",
    only_failing_ci = true
)
```

Key features:

  - Automatically detects repositories with failing formatter CI
  - Creates pull requests or pushes directly to master
  - Runs tests to ensure formatting doesn't break code
  - Generates detailed logs of all operations
  - Handles SciML style formatting by default

### Version Bumping and Registration

Automatically bump minor versions and register packages:

```julia
# Bump and register a single repository
result = bump_and_register_repo("/path/to/MyPackage.jl")

# Process all repositories in an organization
results = bump_and_register_org("MyOrg"; auth_token = ENV["GITHUB_TOKEN"])
```

Features:

  - Main package Project.toml
  - Subpackages in `lib/*/Project.toml`
  - Git commits for version changes
  - Error handling and reporting

### Explicit Imports Fixing

Automatically fix implicit imports and remove unused imports using ExplicitImports.jl:

```julia
# Fix a single package
success, iterations, report = fix_explicit_imports("/path/to/MyPackage.jl")

# Fix and create PR for a repository
fix_repo_explicit_imports("SciML/MyPackage.jl")

# Fix all packages in an organization
results = fix_org_explicit_imports("SciML")
```

Features:

  - Detects implicit imports and adds explicit import statements
  - Removes unused explicit imports
  - Iteratively applies fixes until all checks pass
  - Verifies package still works after changes

### Minimum Version Fixing

Automatically fix minimum version compatibility bounds to ensure packages pass downgrade CI tests:

```julia
# Fix a single repository
success = fix_repo_min_versions("SciML/OrdinaryDiffEq.jl")

# Fix all repositories in an organization
results = fix_org_min_versions("SciML")

# Process only specific repositories
results = fix_org_min_versions("SciML";
    only_repos = ["OrdinaryDiffEq.jl", "DiffEqBase.jl"])
```

Features:

  - Tests minimum versions using Stefan Karpinski's Resolver.jl
  - Intelligently identifies and fixes problematic minimum versions
  - Creates pull requests with detailed changelogs
  - Smart version detection using registry lookups
  - Preserves existing upper bounds in compat entries

### Version Check Finder

Find and fix obsolete Julia version checks in your codebase:

```julia
# Find version checks in a single file
checks = find_version_checks_in_file("src/myfile.jl")

# Find version checks in a repository
checks = find_version_checks_in_repo("/path/to/repo")

# Find version checks across an organization
org_checks = find_version_checks_in_org("SciML")

# Generate fix script for version checks
write_version_checks_to_script(checks, "fix_versions.jl")

# Fix version checks in parallel
fix_version_checks_parallel(repo_path, checks; num_processes = 4)
```

Features:

  - Detects version comparisons that are obsolete based on current Julia LTS (v1.10)
  - Finds various patterns: `@static if`, `if VERSION`, ternary operators, etc.
  - Generates executable scripts to apply fixes
  - Parallel processing for large organizations
  - Respects .gitignore patterns

### Compat Bumping

Automatically bump compat entries for major version updates:

```julia
# Check available updates for a package
updates = get_available_compat_updates("/path/to/Project.toml")

# Bump compat and test
success, msg, pr_url, bumped = bump_compat_and_test(
    repo_path;
    package_name = "DataFrames",  # specific package or nothing for all
    bump_all = false,             # bump all or just one
    create_pr = true,
    fork_user = "myusername"
)

# Process entire organization
successes, failures, pr_urls = bump_compat_org_repositories(
    "SciML";
    package_name = "DataFrames",
    fork_user = "myusername"
)
```

Features:

  - Detects available major version updates
  - Runs tests after bumping to ensure compatibility
  - Creates detailed pull requests
  - Supports mono-repos with multiple Project.toml files
  - Preserves SemVer compatibility

### Invalidation Analysis

Analyze method invalidations to identify performance bottlenecks:

```julia
# Analyze a single repository
report = analyze_repo_invalidations("/path/to/repo")

# Analyze an entire organization
results = analyze_org_invalidations("SciML";
    max_repos = 50,
    output_dir = "invalidation_reports"
)
```

Features:

  - Uses SnoopCompileCore to detect method invalidations
  - Identifies major invalidators and affected packages
  - Generates detailed reports with recommendations
  - Runs analysis in separate Julia processes for accuracy
  - Creates organization-wide summary reports

### Import Timing Analysis

Measure and analyze package loading times:

```julia
# Analyze a single package
report = analyze_repo_import_timing("/path/to/repo")

# Analyze an organization
results = analyze_org_import_timing("SciML";
    max_repos = 50,
    output_dir = "timing_reports"
)
```

Features:

  - Uses `@time_imports` to measure loading times
  - Identifies slow dependencies
  - Distinguishes between precompilation and loading time
  - Generates recommendations for optimization
  - Creates comparative reports across organizations

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/SciML/OrgMaintenanceScripts.jl")
```

## Prerequisites

  - Julia 1.6 or higher
  - GitHub CLI (`gh`) installed and authenticated (for PR creation features)
  - Git configured with appropriate credentials

## Dependencies

All required Julia packages are automatically installed, including:

  - JuliaFormatter for code formatting
  - ExplicitImports for import analysis
  - SnoopCompileCore for invalidation analysis
  - HTTP/JSON3 for GitHub API interactions
  - Distributed for parallel processing

## Documentation

For detailed documentation, see the [docs](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/).

### Available Documentation

  - [Code Formatting Guide](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/formatting/) - Automated Julia code formatting
  - [Version Bumping & Registration](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/version_bumping/) - Semantic versioning and package registration
  - [Explicit Imports Fixing](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/explicit_imports_fixing/) - Fix implicit and unused imports
  - [Minimum Version Fixing](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/min_version_fixing/) - Fix compatibility bounds for downgrade CI
  - [Version Check Finder](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/version_check_finder/) - Find and fix obsolete version checks
  - [Compat Bumping](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/compat_bumping/) - Bump compat for major version updates
  - [Invalidation Analysis](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/invalidation_analysis/) - Analyze method invalidations
  - [Import Timing Analysis](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/import_timing_analysis/) - Measure package loading performance

## Example Workflow

Here's a typical workflow for maintaining a Julia organization:

```julia
using OrgMaintenanceScripts

org = "MyOrg"

# 1. Check for formatting issues
format_org_repositories(org; only_failing_ci = true)

# 2. Fix minimum versions for downgrade CI
fix_org_min_versions(org)

# 3. Update to latest major versions
bump_compat_org_repositories(org; bump_all = true)

# 4. Clean up old version checks
checks = find_version_checks_in_org(org)
fix_org_version_checks_parallel(checks)

# 5. Analyze performance
analyze_org_invalidations(org; output_dir = "reports/invalidations")
analyze_org_import_timing(org; output_dir = "reports/timing")

# 6. Fix import issues
fix_org_explicit_imports(org)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This package is licensed under the MIT license.
