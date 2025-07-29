# OrgMaintenanceScripts.jl

```@meta
CurrentModule = OrgMaintenanceScripts
```

Documentation for [OrgMaintenanceScripts](https://github.com/SciML/OrgMaintenanceScripts.jl).

## Package Features

This package provides maintenance scripts for SciML organization repositories, including:

  - **Code Formatting**: Automated formatting with JuliaFormatter across entire organizations
  - **Version Bumping**: Automatically bump minor versions in Project.toml files
  - **Package Registration**: Register packages to Julia registries
  - **Minimum Version Fixing**: Fix minimum version compatibility bounds to pass downgrade CI tests
  - **Compat Bumping**: Automatically update package compatibility bounds for dependencies
  - **Version Check Finding**: Find outdated VERSION checks that can be removed
  - **Invalidation Analysis**: Use SnoopCompileCore to detect performance bottlenecks
  - **Import Timing Analysis**: Analyze package loading times with @time_imports
  - **Explicit Imports Fixing**: Automatically fix implicit imports and remove unused imports
  - **Organization-wide Operations**: Process entire organizations at once

## Usage Examples

### Code Formatting

```julia
using OrgMaintenanceScripts

# Format a single repository
success, message,
pr_url = format_repository(
    "https://github.com/SciML/Example.jl.git";
    fork_user = "myusername"
)

# Format all repos with failing CI
successes, failures,
pr_urls = format_org_repositories(
    "SciML";
    fork_user = "myusername",
    only_failing_ci = true
)
```

### Version Bumping and Registration

```julia
using OrgMaintenanceScripts

# Bump minor versions and register all packages in a repository
result = bump_and_register_repo("/path/to/repo")

println("Registered packages: ", result.registered)
println("Failed packages: ", result.failed)

# Process all repositories in the SciML organization
results = bump_and_register_org("SciML"; auth_token = "your_github_token")

for (repo, result) in results
    println("$repo:")
    println("  Registered: ", result.registered)
    println("  Failed: ", result.failed)
end
```

### Minimum Version Fixing

```julia
using OrgMaintenanceScripts

# Fix minimum versions for a single repository
success = fix_repo_min_versions("SciML/OrdinaryDiffEq.jl")

# Fix all repositories in an organization
results = fix_org_min_versions("SciML")

# Process only specific repositories
results = fix_org_min_versions("SciML"; only_repos = ["OrdinaryDiffEq.jl", "DiffEqBase.jl"])
```

### Compat Bumping

```julia
using OrgMaintenanceScripts

# Check available compat updates for a repository
updates = get_available_compat_updates("/path/to/MyPackage.jl")
for (pkg, info) in updates
    println("$pkg: $(info.current) → $(info.latest)")
end

# Bump compat bounds and test
success = bump_compat_and_test("/path/to/MyPackage.jl";
    create_pr = true,
    fork_user = "myusername"
)

# Process an entire organization
results = bump_compat_org_repositories("SciML";
    fork_user = "myusername",
    limit = 10
)
```

### Version Check Finding

```julia
using OrgMaintenanceScripts

# Find old version checks in a repository
checks = find_version_checks_in_repo("/path/to/MyPackage.jl")

# Find old version checks across an organization
results = find_version_checks_in_org("SciML"; min_version = v"1.10")
print_version_check_summary(results)

# Use custom minimum version
results = find_version_checks_in_org("MyOrg"; min_version = v"1.9", max_repos = 10)
```

### Explicit Imports Fixing

```julia
using OrgMaintenanceScripts

# Fix explicit imports in a package
success, iterations, report = fix_explicit_imports("/path/to/MyPackage.jl")

# Fix and create PR for a repository
fix_repo_explicit_imports("MyOrg/MyPackage.jl"; create_pr = true)

# Fix all packages in an organization
results = fix_org_explicit_imports("MyOrg"; create_prs = true)
```

## Contents

```@contents
Pages = ["formatting.md", "version_bumping.md", "compat_bumping.md", "min_version_fixing.md", "version_check_finder.md", "invalidation_analysis.md", "import_timing_analysis.md", "explicit_imports_fixing.md"]
Depth = 2
```

## API Reference

```@index
```

```@autodocs
Modules = [OrgMaintenanceScripts]
```
