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
results = bump_and_register_org("MyOrg"; auth_token=ENV["GITHUB_TOKEN"])
```

Features:
- Main package Project.toml
- Subpackages in `lib/*/Project.toml`
- Git commits for version changes
- Error handling and reporting

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/SciML/OrgMaintenanceScripts.jl")
```

## Prerequisites

- Julia 1.6 or higher
- GitHub CLI (`gh`) installed and authenticated (for formatting features)
- Git configured with appropriate credentials

## Documentation

For detailed documentation, see the [docs](https://sciml.github.io/OrgMaintenanceScripts.jl/dev/).