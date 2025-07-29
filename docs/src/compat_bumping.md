# Compat Bumping

OrgMaintenanceScripts.jl provides functionality to automatically check for major version updates of dependencies, test them locally, and create pull requests if tests pass.

## Overview

The compat bumping functionality helps maintain Julia packages by:

  - Detecting when dependencies have new major versions available
  - Automatically updating compat entries to allow the new versions
  - Running tests locally to ensure compatibility
  - Creating pull requests if tests pass

## Functions

### `get_available_compat_updates`

Check for available major version updates in a package's dependencies.

```julia
updates = get_available_compat_updates("Project.toml")
```

Returns a vector of `CompatUpdate` structs, each containing:

  - `package_name`: Name of the dependency
  - `current_compat`: Current compat specification
  - `latest_version`: Latest available version
  - `is_major_update`: Whether this is a major version bump

### `bump_compat_and_test`

Bump compat entries for major version updates and run tests locally.

```julia
success, message, pr_url, bumped_packages = bump_compat_and_test("path/to/repo";
    package_name = "SpecificPackage",  # Optional: bump only this package
    bump_all = false,                  # Bump all available updates
    create_pr = true,                  # Create PR if tests pass
    fork_user = "yourusername"         # Required for PR creation
)
```

**Arguments:**

  - `repo_path`: Path to the repository
  - `package_name`: Specific package to bump (optional)
  - `bump_all`: Whether to bump all available updates or just one
  - `create_pr`: Whether to create a PR if tests pass
  - `fork_user`: GitHub username for creating PRs

**Returns:**

  - `success`: Whether the operation succeeded
  - `message`: Status message
  - `pr_url`: URL of created PR (if any)
  - `bumped_packages`: List of packages that were bumped

### `bump_compat_org_repositories`

Process all repositories in a GitHub organization.

```julia
successes, failures, pr_urls = bump_compat_org_repositories("SciML";
    package_name = nothing,      # Bump all packages
    bump_all = false,           # One update per repo
    create_pr = true,
    fork_user = "yourusername",
    limit = 100,
    log_file = "compat_bump.log"
)
```

## Examples

### Check for Updates

```julia
using OrgMaintenanceScripts

# Check what updates are available
updates = get_available_compat_updates("Project.toml")
for update in updates
    println("$(update.package_name): $(update.current_compat) → $(update.latest_version)")
end
```

### Bump Single Package

```julia
# Bump compat for DataFrames only
success, msg, pr_url, bumped = bump_compat_and_test(".";
    package_name = "DataFrames",
    create_pr = true,
    fork_user = "myusername"
)
```

### Bump All Updates

```julia
# Bump all available major version updates
success, msg, pr_url, bumped = bump_compat_and_test(".";
    bump_all = true,
    create_pr = true,
    fork_user = "myusername"
)
```

### Process Organization

```julia
# Process all SciML repositories
successes, failures, pr_urls = bump_compat_org_repositories("SciML";
    bump_all = false,  # One update per repo
    create_pr = true,
    fork_user = "myusername",
    limit = 50
)

println("Successfully updated: $(length(successes)) repos")
println("Failed: $(length(failures)) repos")
println("Created $(length(pr_urls)) pull requests")
```

## Workflow

 1. **Detection**: The tool scans `Project.toml` to find dependencies with new major versions
 2. **Update**: Compat entries are updated to allow the new major version
 3. **Test**: The package's tests are run locally with the updated dependencies
 4. **PR Creation**: If tests pass, a pull request is automatically created

## Requirements

  - Julia 1.6 or later
  - GitHub CLI (`gh`) installed and authenticated for PR creation
  - Write access to a fork of the repositories you want to update

## Notes

  - The tool only creates PRs for updates where tests pass
  - Tests have a default timeout of 30 minutes (configurable)
  - Rate limiting is applied when processing multiple repositories
  - Logs are saved for organization-wide operations
