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
- **Version Check Finder**: Find and remove obsolete Julia version compatibility checks
- **Invalidation Analysis**: Detect and analyze method invalidations using SnoopCompileCore
- **Organization-wide Operations**: Process entire organizations at once

## Usage Examples

### Code Formatting

```julia
using OrgMaintenanceScripts

# Format a single repository
success, message, pr_url = format_repository(
    "https://github.com/SciML/Example.jl.git";
    fork_user = "myusername"
)

# Format all repos with failing CI
successes, failures, pr_urls = format_org_repositories(
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
results = bump_and_register_org("SciML"; auth_token="your_github_token")

for (repo, result) in results
    println("$repo:")
    println("  Registered: ", result.registered)
    println("  Failed: ", result.failed)
end
```

## Contents

```@contents
Pages = ["formatting.md", "version_check_finder.md", "invalidation_analysis.md"]
Depth = 2
```

## API Reference

```@index
```

```@autodocs
Modules = [OrgMaintenanceScripts]
```