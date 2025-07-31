# Invalidation Analysis

The Invalidation Analysis functionality helps detect and analyze method invalidations that can significantly impact Julia package performance. This tool uses SnoopCompileCore to detect invalidations and provides detailed reports on the biggest performance problems.

## Overview

Method invalidations occur when Julia needs to recompile previously compiled methods due to new method definitions. This can significantly slow down package loading and runtime performance. This module helps you:

 1. Detect invalidations in your packages
 2. Identify the major invalidators causing the most problems
 3. Generate comprehensive reports with actionable recommendations
 4. Analyze entire organizations to find systemic issues

## Functions

### Single Repository Analysis

```julia
analyze_repo_invalidations(repo_path::String; test_script::String = "", output_file::String = "")
```

Analyze invalidations in a single repository and generate a comprehensive report.

**Parameters:**

  - `repo_path`: Path to the repository to analyze
  - `test_script`: Optional custom Julia code to run during analysis (defaults to loading the package and running tests)
  - `output_file`: Optional path to save detailed JSON report

**Returns:** `InvalidationReport` object with analysis results

### Organization-wide Analysis

```julia
analyze_org_invalidations(
    org::String; auth_token::String = "", work_dir::String = mktempdir(),
    test_script::String = "", output_dir::String = "", max_repos::Int = 0)
```

Analyze invalidations across all repositories in a GitHub organization.

**Parameters:**

  - `org`: GitHub organization name
  - `auth_token`: GitHub authentication token for API access
  - `work_dir`: Working directory for cloning repositories
  - `test_script`: Custom test script to run for each repository
  - `output_dir`: Directory to save individual and summary reports
  - `max_repos`: Maximum number of repositories to analyze (0 = no limit)

**Returns:** Dictionary mapping repository names to `InvalidationReport` objects

### Report Generation

```julia
generate_invalidation_report(repo_path::String, test_script::String = "")
```

Generate a detailed invalidation report for a repository without printing to console.

**Returns:** `InvalidationReport` object

## Data Structures

### InvalidationEntry

Represents a single invalidation with detailed information:

```julia
struct InvalidationEntry
    method::String          # Method signature that was invalidated
    file::String           # File where the method is defined
    line::Int              # Line number in the file
    package::String        # Package that owns the method
    reason::String         # Description of why it's problematic
    children_count::Int    # Number of methods invalidated by this one
    depth::Int            # Depth in the invalidation tree
end
```

### InvalidationReport

Comprehensive report for a repository:

```julia
struct InvalidationReport
    repo::String                           # Repository name
    total_invalidations::Int              # Total number of invalidations
    major_invalidators::Vector{InvalidationEntry}  # Top problematic invalidations
    packages_affected::Vector{String}     # List of packages involved
    analysis_time::DateTime              # When the analysis was performed
    summary::String                      # Human-readable summary
    recommendations::Vector{String}      # Actionable recommendations
end
```

## Usage Examples

### Analyze a Single Repository

```julia
using OrgMaintenanceScripts

# Basic analysis
report = analyze_repo_invalidations("/path/to/my/package")

# Analysis with custom test script and detailed output
custom_test = """
    using MyPackage
    # Run specific operations that might cause invalidations
    MyPackage.heavy_computation()
    MyPackage.type_unstable_function([1, 2, 3])
"""

report = analyze_repo_invalidations("/path/to/my/package";
    test_script = custom_test,
    output_file = "invalidation_report.json"
)
```

### Analyze an Entire Organization

```julia
# Set up GitHub authentication
github_token = ENV["GITHUB_TOKEN"]

# Analyze all repositories in the SciML organization
results = analyze_org_invalidations("SciML";
    auth_token = github_token,
    output_dir = "sciml_invalidation_reports",
    max_repos = 10  # Limit to first 10 repos for testing
)

# Print summary statistics
total_invalidations = sum(r.total_invalidations
for r in values(results) if r.total_invalidations >= 0)
println("Total invalidations across organization: $total_invalidations")
```

### Custom Analysis Script

For specialized analysis, you can provide custom test scripts:

```julia
# Custom script for a web framework package
web_test_script = """
    using MyWebFramework
    using HTTP
    
    # Test route handling (common source of invalidations)
    app = MyWebFramework.App()
    MyWebFramework.route!(app, "/test") do req
        return "Hello World"
    end
    
    # Test middleware chain
    MyWebFramework.use!(app, MyWebFramework.CORSMiddleware())
    MyWebFramework.use!(app, MyWebFramework.LoggingMiddleware())
"""

report = analyze_repo_invalidations("/path/to/web/framework";
    test_script = web_test_script
)
```

## Understanding the Results

### Summary Interpretations

  - ✅ **0 invalidations**: Excellent! Your package is well-optimized
  - ✅ **1-9 invalidations**: Good performance with minor issues
  - ⚠️ **10-49 invalidations**: Moderate performance impact, room for improvement
  - ❌ **50+ invalidations**: Significant performance problems requiring attention

### Major Invalidators

The report identifies invalidations with the highest impact based on:

  - **Children Count**: How many other methods this invalidation affects
  - **Package**: Which package is responsible (helps prioritize fixes)
  - **Depth**: Position in the invalidation tree

### Common Recommendations

 1. **Type Stability**: Ensure functions return consistent types
 2. **Method Definitions**: Avoid redefining methods in package loading
 3. **Dependencies**: Review packages that cause many invalidations
 4. **Specialization**: Use `@nospecialize` for arguments that don't need specialization

## Organization Reports

When analyzing entire organizations, additional summary reports are generated:

  - **Markdown Summary**: Overview of all repositories with rankings
  - **Individual JSON Reports**: Detailed data for each repository
  - **Action Items**: Prioritized list of improvements

## Best Practices

 1. **Run Early**: Analyze invalidations during development, not just before release
 2. **Monitor Trends**: Track invalidation counts over time
 3. **Focus on Impact**: Prioritize fixing invalidations with high children counts
 4. **Test Thoroughly**: Use realistic test scripts that exercise your package's main functionality
 5. **Organization Level**: Run periodic organization-wide analyses to identify systemic issues

## Integration with CI/CD

You can integrate invalidation analysis into your CI pipeline:

```julia
# In your CI script
using OrgMaintenanceScripts

report = analyze_repo_invalidations(".")

# Fail CI if invalidations exceed threshold
if report.total_invalidations > 20
    println("❌ Too many invalidations: $(report.total_invalidations)")
    exit(1)
end

println("✅ Invalidation check passed: $(report.total_invalidations) invalidations")
```

## Troubleshooting

### Common Issues

 1. **SnoopCompileCore not found**: Ensure SnoopCompileCore.jl is installed
 2. **Analysis fails**: Check that the repository has a valid Project.toml and can be loaded
 3. **Permission errors**: Ensure you have read access to repositories and write access to output directories
 4. **Memory issues**: For large organizations, use `max_repos` to limit analysis scope

### Performance Considerations

  - Analysis runs in separate Julia processes to avoid contamination
  - Large organizations may take significant time to analyze
  - Consider running analyses on powerful machines for better performance
  - Use `max_repos` parameter to test on subsets first
