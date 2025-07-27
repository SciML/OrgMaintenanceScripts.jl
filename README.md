# OrgMaintenanceScripts.jl

[![Build Status](https://github.com/SciML/OrgMaintenanceScripts.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SciML/OrgMaintenanceScripts.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/SciML/OrgMaintenanceScripts.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/SciML/OrgMaintenanceScripts.jl)

A bunch of functions which are helpful for maintaining large Github organizations

## Features

- **Version Bumping**: Automatically bump minor versions in Project.toml files
- **Package Registration**: Register packages to Julia registries
- **Batch Operations**: Process entire repositories or organizations at once
- **Subpackage Support**: Handle monorepos with packages in `lib/` directories

## Installation

```julia
using Pkg
Pkg.add("OrgMaintenanceScripts")
```

## Quick Start

### Bump and Register a Single Repository

```julia
using OrgMaintenanceScripts

# Process a local repository
result = bump_and_register_repo("/path/to/MyPackage.jl")
```

### Process an Entire Organization

```julia
# Process all repositories in an organization
results = bump_and_register_org("MyOrg"; auth_token=ENV["GITHUB_TOKEN"])
```

## Functions

- `bump_and_register_repo(repo_path)`: Bump versions and register packages in a repository
- `bump_and_register_org(org_name)`: Process all repositories in a GitHub organization

Both functions handle:
- Main package Project.toml
- Subpackages in `lib/*/Project.toml`
- Git commits for version changes
- Error handling and reporting