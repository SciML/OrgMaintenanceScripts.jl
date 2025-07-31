# Explicit Imports Fixing

The explicit imports fixer uses [ExplicitImports.jl](https://github.com/ericphanson/ExplicitImports.jl) to automatically detect and fix import issues in Julia packages. It iteratively runs checks and applies fixes until all explicit import best practices are satisfied.

ExplicitImports.jl is included as a direct dependency of OrgMaintenanceScripts, so no additional setup is required.

## Features

  - **Automatic Detection**: Uses ExplicitImports.jl to find implicit imports and unused explicit imports
  - **Iterative Fixing**: Repeatedly applies fixes and re-checks until all issues are resolved
  - **Safe Modifications**: Verifies the package still loads after each round of fixes
  - **Pull Request Creation**: Automatically creates PRs with detailed explanations of changes
  - **Organization-wide Processing**: Can process entire GitHub organizations

## Usage

### Fix a Single Package

```julia
using OrgMaintenanceScripts

# Fix explicit imports in a local package
success, iterations, report = fix_explicit_imports("/path/to/MyPackage.jl")

if success
    println("✓ All explicit import checks pass after $iterations iterations!")
else
    println("Some issues remain after $iterations iterations")
    println(report)
end
```

### Fix a Repository

```julia
# Clone, fix, and create a PR for a repository
success = fix_repo_explicit_imports("MyOrg/MyPackage.jl";
    create_pr = true,
    max_iterations = 10
)
```

### Fix an Entire Organization

```julia
# Process all Julia packages in an organization
results = fix_org_explicit_imports("MyOrg";
    create_prs = true,
    skip_repos = ["DeprecatedPackage.jl"],
    only_repos = nothing  # Process all repos
)

# Summary of results
for (repo, success) in results
    println("$repo: ", success ? "✓ Fixed" : "✗ Failed/No changes")
end
```

## How It Works

The fixer follows this iterative process:

 1. **Run ExplicitImports.jl checks** on the package
 2. **Parse the output** to identify specific issues:
    
      + Missing explicit imports (e.g., using `println` without `using Base: println`)
      + Unused explicit imports (e.g., `using Base: push!` when `push!` is never used)
 3. **Apply fixes** to the source files:
    
      + Add missing imports at appropriate locations
      + Remove unused imports while preserving other imports
 4. **Verify the package** still loads correctly
 5. **Repeat** until all checks pass or maximum iterations reached

## Example Fixes

### Missing Import

Before:

```julia
module MyModule

function greet(name)
    println("Hello, $name!")  # println used implicitly
end

end
```

After:

```julia
module MyModule

using Base: println

function greet(name)
    println("Hello, $name!")
end

end
```

### Unused Import

Before:

```julia
module MyModule

using Base: println, push!, filter  # push! is never used

function process(items)
    filtered = filter(x -> x > 0, items)
    println("Processed $(length(filtered)) items")
end

end
```

After:

```julia
module MyModule

using Base: println, filter

function process(items)
    filtered = filter(x -> x > 0, items)
    println("Processed $(length(filtered)) items")
end

end
```

## Options

### `fix_explicit_imports`

  - `package_path`: Path to the package directory
  - `max_iterations`: Maximum number of fix/check cycles (default: 10)
  - `verbose`: Show detailed output during processing (default: true)

### `fix_repo_explicit_imports`

  - `repo_name`: GitHub repository name (e.g., "MyOrg/Package.jl")
  - `work_dir`: Temporary directory for cloning (default: mktempdir())
  - `max_iterations`: Maximum number of fix/check cycles (default: 10)
  - `create_pr`: Whether to create a pull request (default: true)
  - `verbose`: Show detailed output (default: true)

### `fix_org_explicit_imports`

  - `org_name`: GitHub organization name
  - `work_dir`: Temporary directory for processing (default: mktempdir())
  - `max_iterations`: Maximum iterations per package (default: 10)
  - `create_prs`: Whether to create pull requests (default: true)
  - `skip_repos`: Array of repository names to skip
  - `only_repos`: Process only these repositories (default: all)
  - `verbose`: Show detailed output (default: true)

## Benefits

Using explicit imports provides several benefits:

 1. **Clarity**: Makes dependencies explicit and clear
 2. **Performance**: Can improve load times by avoiding unnecessary imports
 3. **Maintainability**: Easier to track what external functions are used
 4. **Stability**: Reduces risk of name conflicts when packages export new names
 5. **Static Analysis**: Better compatibility with tools that analyze code

## Limitations

  - Requires ExplicitImports.jl to be installable in the package environment
  - May not catch all edge cases that require manual review
  - Some packages may have legitimate reasons for implicit imports
  - Complex macro usage might not be handled perfectly

## Best Practices

 1. **Review Changes**: Always review the automated changes before merging
 2. **Run Tests**: Ensure your test suite passes after fixes
 3. **Incremental Adoption**: For large packages, consider fixing one module at a time
 4. **Document Exceptions**: If you need implicit imports, document why

## Troubleshooting

If the fixer encounters issues:

 1. **Check Package Loads**: Ensure your package loads without the fixes
 2. **Update Dependencies**: Make sure all dependencies are up to date
 3. **Manual Review**: Some complex cases may need manual intervention
 4. **Report Issues**: File issues for packages that can't be automatically fixed
