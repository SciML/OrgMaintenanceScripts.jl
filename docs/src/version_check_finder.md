# Version Check Finder

The version check finder functionality helps identify outdated Julia version checks in code that can be cleaned up. This is particularly useful when dropping support for older Julia versions.

## Overview

When Julia packages evolve, they often contain compatibility code for older Julia versions. These checks (like `if VERSION >= v"1.6"`) become obsolete once the minimum supported version is raised. The version check finder helps locate these outdated checks across files, repositories, and even entire organizations.

## Functions

### Finding Version Checks in Files

```@docs
find_version_checks_in_file
```

### Finding Version Checks in Repositories

```@docs
find_version_checks_in_repo
```

### Finding Version Checks in Organizations

```@docs
find_version_checks_in_org
```

### Displaying Results

```@docs
print_version_check_summary
```

### Data Structures

The `VersionCheck` struct represents a found version check with the following fields:
- `file_path::String`: Path to the file containing the check
- `line_number::Int`: Line number where the check appears
- `line_content::String`: The actual line content
- `version::VersionNumber`: The Julia version being compared against
- `operator::String`: The comparison operator (>=, >, ==, <, <=)

## Usage Examples

### Basic File Search

Find version checks in a single file:

```julia
using OrgMaintenanceScripts

# Search with default minimum version (v"1.10")
checks = find_version_checks_in_file("src/myfile.jl")

# Search with custom minimum version
checks = find_version_checks_in_file("src/myfile.jl"; min_version=v"1.9")

# Display results
for check in checks
    println("Line $(check.line_number): $(check.line_content)")
    println("  Checking for VERSION $(check.operator) v\"$(check.version)\"")
end
```

### Repository-Wide Search

Search an entire repository for old version checks:

```julia
using OrgMaintenanceScripts

# Search repository
results = find_version_checks_in_repo("/path/to/MyPackage.jl")

# Display summary
for (file, checks) in results
    println("$file: $(length(checks)) old version checks")
    for check in checks
        println("  Line $(check.line_number): VERSION $(check.operator) v\"$(check.version)\"")
    end
end
```

### Organization-Wide Search

Search all repositories in a GitHub organization:

```julia
using OrgMaintenanceScripts

# Search with defaults (current LTS: v"1.10")
results = find_version_checks_in_org("JuliaLang")

# Search with custom settings
results = find_version_checks_in_org("MyOrg"; 
    min_version = v"1.9",
    auth_token = ENV["GITHUB_TOKEN"],
    max_repos = 50  # Limit for testing
)

# Pretty-print results
print_version_check_summary(results)
```

## Supported Patterns

The version check finder recognizes various patterns:

- `if VERSION >= v"1.6"`
- `@static if VERSION > v"1.8.0"`
- `VERSION <= v"1.9"`
- `VERSION == v"1.7"`
- `VERSION >= VersionNumber("1.6")`

It intelligently identifies only checks that compare against versions older than your specified minimum (default: v"1.10", the current LTS).

## Example Output

```
=== Old Version Checks Summary ===

📦 MyOrg/PackageA.jl (5 checks in 2 files)
  📄 src/compat.jl
    Line 10: if VERSION >= v"1.6"
      → Checking for VERSION >= v"1.6"
    Line 25: @static if VERSION > v"1.7"
      → Checking for VERSION > v"1.7"
  📄 test/runtests.jl
    Line 5: VERSION >= v"1.8" && include("new_tests.jl")
      → Checking for VERSION >= v"1.8"

📦 MyOrg/PackageB.jl (3 checks in 1 files)
  📄 src/utils.jl
    Line 100: const HAS_FEATURE = VERSION >= v"1.5"
      → Checking for VERSION >= v"1.5"

=== Summary Statistics ===
Total repositories with old checks: 2
Total files with old checks: 3
Total old version checks: 8
```

## Best Practices

1. **Start with a single repository**: Test the functionality on one repository before scanning an entire organization
2. **Use authentication for organizations**: Provide a GitHub token to avoid rate limits
3. **Review before removing**: Always review the found checks before removing them, as some might still be necessary
4. **Consider your minimum version**: The default v"1.10" (current LTS) might not match your needs

## Performance Considerations

- File searches are fast and can handle large codebases
- Repository searches use `walkdir` and skip common non-source directories
- Organization searches clone repositories with `--depth 1` for efficiency
- Use `max_repos` parameter when testing on large organizations

## Integration with CI/CD

You can integrate version check finding into your maintenance workflow:

```julia
# maintenance_script.jl
using OrgMaintenanceScripts

# Check for old version checks
results = find_version_checks_in_repo(".")
if !isempty(results)
    print_version_check_summary(results)
    println("\nConsider removing these outdated version checks!")
end
```

## Related Functions

- [`fix_repo_min_versions`](@ref): Fix minimum version bounds after removing old checks
- [`format_repository`](@ref): Format code after removing version checks
- [`bump_and_register_repo`](@ref): Bump versions when making breaking changes