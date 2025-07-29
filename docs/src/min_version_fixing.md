# Minimum Version Fixing

The `OrgMaintenanceScripts.jl` package provides tools to automatically fix minimum version compatibility bounds for Julia packages. This functionality helps ensure that packages pass the downgrade CI tests by intelligently updating outdated minimum version specifications.

## Overview

The minimum version fixer:

  - Uses Stefan Karpinski's Resolver.jl to test if minimum versions can be resolved
  - Identifies packages with problematic minimum versions through resolver errors
  - Intelligently bumps versions using multiple strategies
  - Creates pull requests with the fixes automatically

## Functions

### `fix_package_min_versions`

Fix minimum versions for a package that's already cloned locally.

```julia
fix_package_min_versions(repo_path::String;
    max_iterations::Int = 10,
    work_dir::String = mktempdir(),
    julia_version::String = "1.10")
```

**Parameters:**

  - `repo_path`: Path to the cloned repository
  - `max_iterations`: Maximum number of fix iterations (default: 10)
  - `work_dir`: Working directory for temporary files
  - `julia_version`: Julia version for compatibility testing (default: "1.10")

**Returns:** `(success::Bool, updates::Dict{String,String})`

### `fix_repo_min_versions`

Clone a repository, fix its minimum versions, and optionally create a PR.

```julia
fix_repo_min_versions(repo_name::String;
    work_dir::String = mktempdir(),
    max_iterations::Int = 10,
    create_pr::Bool = true,
    julia_version::String = "1.10")
```

**Parameters:**

  - `repo_name`: GitHub repository name (e.g., "SciML/OrdinaryDiffEq.jl")
  - `work_dir`: Working directory for cloning and temporary files
  - `max_iterations`: Maximum number of fix iterations
  - `create_pr`: Whether to create a pull request (default: true)
  - `julia_version`: Julia version for compatibility testing

**Returns:** `success::Bool`

### `fix_org_min_versions`

Fix minimum versions for all Julia packages in a GitHub organization.

```julia
fix_org_min_versions(org_name::String;
    work_dir::String = mktempdir(),
    max_iterations::Int = 10,
    create_prs::Bool = true,
    skip_repos::Vector{String} = String[],
    only_repos::Union{Nothing, Vector{String}} = nothing,
    julia_version::String = "1.10")
```

**Parameters:**

  - `org_name`: GitHub organization name (e.g., "SciML")
  - `work_dir`: Working directory
  - `max_iterations`: Maximum iterations per repository
  - `create_prs`: Whether to create pull requests
  - `skip_repos`: Repository names to skip
  - `only_repos`: If specified, only process these repositories
  - `julia_version`: Julia version for compatibility testing

**Returns:** `results::Dict{String,Bool}` mapping repository names to success status

## Usage Examples

### Fix a Single Package

```julia
using OrgMaintenanceScripts

# Fix a repository by name (clones automatically)
fix_repo_min_versions("SciML/OrdinaryDiffEq.jl")

# Fix without creating a PR
fix_repo_min_versions("SciML/DiffEqBase.jl"; create_pr = false)

# Fix an already cloned repository
success, updates = fix_package_min_versions("/path/to/cloned/repo")
```

### Fix an Entire Organization

```julia
# Fix all Julia packages in the SciML organization
results = fix_org_min_versions("SciML")

# Skip certain repositories
results = fix_org_min_versions("SciML"; skip_repos = ["SciMLDocs", "SciMLBenchmarks.jl"])

# Only process specific repositories
results = fix_org_min_versions("SciML"; only_repos = ["OrdinaryDiffEq.jl", "DiffEqBase.jl"])

# Don't create PRs (useful for testing)
results = fix_org_min_versions("SciML"; create_prs = false)
```

## Version Bumping Strategy

The tool uses multiple strategies to determine appropriate minimum versions:

 1. **Registry Lookup**: Queries the General registry for the latest compatible version

 2. **Conservative Bumping**:
    
      + For `0.x` packages: Uses the latest `0.x` version
      + For stable packages (`≥1.0`): Uses `major.0.0`
      + Preserves existing upper bounds in all compat entries
 3. **Fallback Strategy**: If registry lookup fails, conservatively bumps the current version

## Requirements

  - Julia 1.6+
  - Git
  - GitHub CLI (`gh`) for automatic PR creation
  - Authenticated with GitHub (`gh auth login`)

## How It Works

 1. **Clone Repository**: Clones the target repository (if needed)
 2. **Create Branch**: Creates a feature branch for the fixes
 3. **Test Resolution**: Uses Resolver.jl with `--min=@alldeps` to test if minimum versions resolve
 4. **Identify Issues**: Parses resolver errors to find problematic packages
 5. **Apply Fixes**: Intelligently bumps failing minimum versions
 6. **Iterate**: Repeats until all packages resolve
 7. **Create PR**: Commits changes and creates a detailed pull request

## Example Output

```
[ Info: Fixing minimum versions for OrdinaryDiffEq
[ Info: Iteration 1/10
[ Info: Resolution failed, analyzing...
[ Info: Found problematic packages: RecursiveArrayTools, StaticArrays
[ Info: Updated RecursiveArrayTools: 2.0 → 3.0
[ Info: Updated StaticArrays: 0.12 → 1.0
[ Info: Iteration 2/10
[ Info: ✓ Minimum versions resolved successfully!
[ Info: Creating pull request...
[ Info: ✓ Pull request created successfully!
```
