# Version Bumping and Registration

The `OrgMaintenanceScripts.jl` package provides tools for automatically bumping minor versions and registering Julia packages. This functionality helps maintain consistent versioning across packages and simplifies the release process.

## Overview

The version bumping and registration tools:

  - Automatically increment minor version numbers in Project.toml files
  - Handle main packages and subpackages in `lib/` directories
  - Create git commits for version changes
  - Register packages to Julia registries using LocalRegistry.jl
  - Process entire GitHub organizations at once
  - Support monorepo structures with interdependent packages

## Functions

### `bump_minor_version`

Bump the minor version of a semantic version string.

```julia
bump_minor_version(version_str::String) -> String
```

**Parameters:**

  - `version_str`: A semantic version string (e.g., "1.2.3")

**Returns:** New version string with incremented minor version (e.g., "1.3.0")

**Example:**

```julia
new_version = bump_minor_version("1.2.3")  # Returns "1.3.0"
new_version = bump_minor_version("0.5.0")  # Returns "0.6.0"
```

### `update_project_version`

Update the version in a Project.toml file by bumping the minor version.

```julia
update_project_version(project_path::String)
```

**Parameters:**

  - `project_path`: Path to the Project.toml file

**Returns:** Tuple `(old_version, new_version)` or `nothing` if no version field exists

**Example:**

```julia
result = update_project_version("path/to/Project.toml")
if !isnothing(result)
    old_ver, new_ver = result
    println("Updated: $old_ver → $new_ver")
end
```

### `register_package`

Register a Julia package to the specified registry using LocalRegistry.

```julia
register_package(package_dir::String; registry = "General", push::Bool = false)
```

**Parameters:**

  - `package_dir`: Directory containing the package to register
  - `registry`: Name or path to the registry (default: "General")
  - `push`: Whether to push the registration to the remote registry (default: false)

**Returns:** `true` on success, `false` on failure

**Example:**

```julia
# Register to General registry
register_package("/path/to/MyPackage")

# Register to custom registry with push
register_package("/path/to/MyPackage"; registry="MyRegistry", push=true)
```

### `bump_and_register_repo`

Bump minor versions and register all packages in a repository (including monorepos).

```julia
bump_and_register_repo(repo_path::String; registry = "General", push::Bool = false)
```

**Parameters:**

  - `repo_path`: Path to the repository
  - `registry`: Name or path to the registry (default: "General")
  - `push`: Whether to push registrations to remote registry (default: false)

**Returns:** Named tuple `(registered=String[], failed=String[])`

This function:

 1. Bumps minor versions in all Project.toml files
 2. Collects all package directories (main + lib/*)
 3. Uses brute-force dependency resolution for registration order
 4. Commits version changes to git
 5. Handles monorepo structures with interdependent packages

**Example:**

```julia
result = bump_and_register_repo("/path/to/MyPackage.jl")
println("Successfully registered: ", result.registered)
println("Failed to register: ", result.failed)
```

### `register_monorepo_packages`

Register all packages in a monorepo without bumping versions.

```julia
register_monorepo_packages(repo_path::String; registry = "General", push::Bool = false)
```

**Parameters:**

  - `repo_path`: Path to the repository root directory
  - `registry`: Name or path to the registry (default: "General")
  - `push`: Whether to push registrations to remote registry (default: false)

**Returns:** Named tuple `(registered=String[], failed=String[])`

This function is similar to `bump_and_register_repo` but only performs registration without modifying package versions. It's useful when:

  - Versions have already been bumped manually
  - You want to register packages at their current versions
  - You need to retry registration after fixing issues

**Features:**

  - Scans for all packages (main Project.toml and lib/*/Project.toml)
  - Uses brute-force dependency resolution
  - Handles circular dependencies and complex dependency graphs
  - Does NOT modify any Project.toml files or create commits

**Example:**

```julia
# Register all packages in a monorepo
result = register_monorepo_packages("/path/to/repo")
println("Successfully registered: ", length(result.registered), " packages")

# Register with custom registry
register_monorepo_packages("/path/to/repo"; registry="MyRegistry", push=true)
```

### `get_org_repos`

Get all repositories for a GitHub organization.

```julia
get_org_repos(org::String; auth_token::String = "")
```

**Parameters:**

  - `org`: GitHub organization name
  - `auth_token`: GitHub authentication token (optional but recommended)

**Returns:** Vector of repository full names (e.g., "SciML/OrdinaryDiffEq.jl")

### `bump_and_register_org`

Bump minor versions and register all packages in all repositories of a GitHub organization.

```julia
bump_and_register_org(org::String;
    registry = "General",
    push::Bool = false,
    auth_token::String = "",
    work_dir::String = mktempdir())
```

**Parameters:**

  - `org`: GitHub organization name
  - `registry`: Name or path to the registry (default: "General")
  - `push`: Whether to push registrations to remote registry (default: false)
  - `auth_token`: GitHub authentication token (recommended for rate limits)
  - `work_dir`: Working directory for cloning repositories

**Returns:** Dictionary mapping repository names to results

**Example:**

```julia
results = bump_and_register_org("SciML"; auth_token = ENV["GITHUB_TOKEN"])

for (repo, result) in results
    println("$repo:")
    println("  Registered: ", result.registered)
    println("  Failed: ", result.failed)
end
```

## Usage Examples

### Bump Version for a Single Package

```julia
using OrgMaintenanceScripts

# Update version in Project.toml
old_ver, new_ver = update_project_version("MyPackage/Project.toml")
println("Version bumped: $old_ver → $new_ver")
```

### Process a Repository with Subpackages

```julia
# Bump versions and register all packages in a repository
result = bump_and_register_repo("/path/to/ComplexPackage.jl")

println("Main package and $(length(result.registered)-1) subpackages processed")
```

### Process an Entire Organization

```julia
# Set up authentication
auth_token = ENV["GITHUB_TOKEN"]

# Process all repositories in the SciML organization
results = bump_and_register_org("SciML"; auth_token = auth_token)

# Generate summary report
total_registered = sum(length(r.registered) for r in values(results))
total_failed = sum(length(r.failed) for r in values(results))

println("Organization Summary:")
println("  Total packages registered: $total_registered")
println("  Total failures: $total_failed")
```

## Workflow Integration

### Automated Release Process

 1. **Version Bumping**: Automatically increment minor versions
 2. **Git Commit**: Create commits with descriptive messages
 3. **Registration**: Register to Julia registries
 4. **Push Changes**: Push version bumps to remote

### CI/CD Integration

The tools can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Action
- name: Bump and Register
  run: |
    julia -e 'using OrgMaintenanceScripts; 
             bump_and_register_repo(".")'
```

## Error Handling

The functions include comprehensive error handling:

  - Missing Project.toml files generate warnings
  - Registration failures are captured and reported
  - Git operations are wrapped in try-catch blocks
  - Each repository in organization processing is isolated

## Best Practices

 1. **Authentication**: Always use GitHub tokens for organization operations
 2. **Testing**: Test version bumping on a single package first
 3. **Backup**: The tools create git commits, ensuring changes can be reverted
 4. **Review**: Check the results before pushing to remote repositories

## Limitations

  - Currently only bumps minor versions (not major or patch)
  - Assumes semantic versioning (MAJOR.MINOR.PATCH)
  - Requires git to be configured with appropriate credentials
  - Registration requires appropriate permissions for the target registry

## API Summary

| Function                                          | Description                              |
|:------------------------------------------------- |:---------------------------------------- |
| `bump_minor_version(version_str)`                 | Increment minor version number           |
| `update_project_version(project_path)`            | Update version in Project.toml          |
| `register_package(package_dir; kwargs...)`        | Register package using LocalRegistry     |
| `bump_and_register_repo(repo_path; kwargs...)`    | Bump versions and register all packages  |
| `register_monorepo_packages(repo_path; kwargs...)` | Register monorepo packages without bumping |
| `get_org_repos(org; auth_token)`                  | List organization repositories           |
| `bump_and_register_org(org; kwargs...)`           | Process entire organization              |
