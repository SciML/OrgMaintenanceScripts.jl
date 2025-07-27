# OrgMaintenanceScripts.jl

```@meta
CurrentModule = OrgMaintenanceScripts
```

Documentation for [OrgMaintenanceScripts](https://github.com/SciML/OrgMaintenanceScripts.jl).

## Package Features

This package provides maintenance scripts for SciML organization repositories, including:

- Automated version bumping for Julia packages
- Batch registration of packages to Julia registries
- Organization-wide package maintenance operations

## Usage Examples

### Bump and Register a Single Repository

```julia
using OrgMaintenanceScripts

# Bump minor versions and register all packages in a repository
result = bump_and_register_repo("/path/to/repo")

println("Registered packages: ", result.registered)
println("Failed packages: ", result.failed)
```

### Bump and Register an Entire Organization

```julia
using OrgMaintenanceScripts

# Process all repositories in the SciML organization
results = bump_and_register_org("SciML"; auth_token="your_github_token")

for (repo, result) in results
    println("$repo:")
    println("  Registered: ", result.registered)
    println("  Failed: ", result.failed)
end
```

## API Reference

```@index
```

```@autodocs
Modules = [OrgMaintenanceScripts]
```