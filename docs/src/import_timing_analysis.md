# Import Timing Analysis

The Import Timing Analysis functionality helps identify and analyze package import latency using Julia's built-in `@time_imports` macro. This tool provides detailed insights into which dependencies are causing slow package loading times and offers actionable recommendations for optimization.

## Overview

Package import time significantly affects user experience, especially for interactive Julia usage. This module helps you:

1. Measure import timing for individual packages and their dependencies
2. Identify the major contributors to slow loading times
3. Generate comprehensive reports with optimization recommendations
4. Analyze entire organizations to find systemic performance issues
5. Track import time regressions over time

## Functions

### Single Repository Analysis

```julia
analyze_repo_import_timing(repo_path::String; package_name::String="", output_file::String="")
```

Analyze import timing for a single repository and generate a comprehensive report.

**Parameters:**
- `repo_path`: Path to the repository to analyze
- `package_name`: Package name to analyze (auto-detected from Project.toml if not provided)
- `output_file`: Optional path to save detailed JSON report

**Returns:** `ImportTimingReport` object with analysis results

### Organization-wide Analysis

```julia
analyze_org_import_timing(org::String; auth_token::String="", work_dir::String=mktempdir(), 
                         output_dir::String="", max_repos::Int=0)
```

Analyze import timing across all repositories in a GitHub organization.

**Parameters:**
- `org`: GitHub organization name
- `auth_token`: GitHub authentication token for API access
- `work_dir`: Working directory for cloning repositories
- `output_dir`: Directory to save individual and summary reports
- `max_repos`: Maximum number of repositories to analyze (0 = no limit)

**Returns:** Dictionary mapping repository names to `ImportTimingReport` objects

### Report Generation

```julia
generate_import_timing_report(repo_path::String, package_name::String="")
```

Generate a detailed import timing report without printing to console.

**Returns:** `ImportTimingReport` object

## Data Structures

### ImportTiming

Represents timing information for a single package:

```julia
struct ImportTiming
    package_name::String        # Name of the package
    total_time::Float64        # Total import time in seconds
    precompile_time::Float64   # Time spent in precompilation
    load_time::Float64         # Time spent loading (excluding precompilation)
    dependencies::Vector{String}  # Direct dependencies
    dep_count::Int            # Number of dependencies
    is_local::Bool            # Whether this is the local package being analyzed
end
```

### ImportTimingReport

Comprehensive report for a repository:

```julia
struct ImportTimingReport
    repo::String                    # Repository name
    package_name::String           # Package being analyzed
    total_import_time::Float64     # Total time to import the package
    major_contributors::Vector{ImportTiming}  # Packages contributing most to import time
    dependency_chain::Vector{String}  # Order in which dependencies are loaded
    analysis_time::DateTime        # When the analysis was performed
    summary::String               # Human-readable summary
    recommendations::Vector{String}  # Actionable recommendations
    raw_output::String            # Raw @time_imports output for debugging
end
```

## Usage Examples

### Analyze a Single Repository

```julia
using OrgMaintenanceScripts

# Basic analysis (auto-detects package name)
report = analyze_repo_import_timing("/path/to/my/package")

# Analysis with specific package name and detailed output
report = analyze_repo_import_timing("/path/to/my/package"; 
    package_name="MyPackage",
    output_file="import_timing_report.json"
)

# View the results
println("Total import time: $(report.total_import_time) seconds")
for contributor in report.major_contributors[1:5]  # Top 5
    println("$(contributor.package_name): $(contributor.total_time)s")
end
```

### Analyze an Entire Organization

```julia
# Set up GitHub authentication
github_token = ENV["GITHUB_TOKEN"]

# Analyze all repositories in the SciML organization
results = analyze_org_import_timing("SciML"; 
    auth_token=github_token,
    output_dir="import_timing_reports",
    max_repos=10  # Limit to first 10 repos for testing
)

# Find the slowest loading packages
slowest = sort([(name, r.total_import_time) for (name, r) in results], by=x->x[2], rev=true)
println("Slowest packages:")
for (name, time) in slowest[1:5]
    println("$name: $(round(time, digits=2))s")
end
```

### Custom Analysis for Specific Scenarios

```julia
# Analyze a web framework for startup time optimization
web_report = analyze_repo_import_timing("/path/to/web/framework")

# Focus on dependencies taking >0.5 seconds
slow_deps = filter(t -> t.total_time > 0.5 && !t.is_local, web_report.major_contributors)
println("Dependencies to optimize:")
for dep in slow_deps
    println("- $(dep.package_name): $(round(dep.total_time, digits=2))s")
    if dep.precompile_time > dep.load_time
        println("  → High precompilation time, consider PackageCompiler.jl")
    end
end
```

## Understanding the Results

### Import Time Classifications

- ✅ **< 1 second**: Excellent user experience
- ✅ **1-3 seconds**: Good performance, acceptable for most use cases
- ⚠️ **3-10 seconds**: Moderate delay, room for improvement
- ❌ **> 10 seconds**: Poor user experience, immediate optimization needed

### Major Contributors Analysis

The analysis identifies packages that contribute significantly to import time:

1. **Total Time**: Overall impact on import performance
2. **Precompile vs Load Time**: Helps identify optimization strategies
3. **Dependency Chain**: Shows the order dependencies are loaded
4. **Local vs External**: Distinguishes your package from dependencies

### Common Optimization Strategies

Based on timing patterns, the tool suggests:

1. **High Precompilation Time**: Use PackageCompiler.jl for system images
2. **Slow Dependencies**: Consider alternatives or lazy loading
3. **Many Dependencies**: Reduce dependency count if possible
4. **Large Packages**: Use package extensions or conditional loading

## Organization Reports

When analyzing entire organizations, additional insights are provided:

- **Average Import Time**: Organization-wide performance metric
- **Slowest Packages**: Ranking of packages by import time
- **Problematic Dependencies**: Dependencies that slow down multiple packages
- **Performance Distribution**: Understanding of organization-wide patterns

## Best Practices

### Development Workflow

1. **Baseline Measurement**: Measure import time early in development
2. **Dependency Review**: Carefully evaluate new dependencies
3. **Regular Monitoring**: Track import time as part of CI/CD
4. **User Testing**: Consider import time in user experience planning

### Optimization Techniques

1. **Lazy Loading**: Use `Requires.jl` for optional dependencies
2. **Package Extensions**: Use Julia 1.9+ package extensions for conditional features
3. **Precompilation**: Optimize precompile statements
4. **System Images**: Use PackageCompiler.jl for deployment scenarios

### CI/CD Integration

```julia
# Example CI script for import time monitoring
using OrgMaintenanceScripts

report = analyze_repo_import_timing(".")

# Set thresholds based on package type
max_import_time = 5.0  # seconds
warning_threshold = 2.0

if report.total_import_time > max_import_time
    println("❌ FAILED: Import time too slow ($(report.total_import_time)s > $(max_import_time)s)")
    exit(1)
elseif report.total_import_time > warning_threshold
    println("⚠️ WARNING: Import time increasing ($(report.total_import_time)s)")
else
    println("✅ PASSED: Good import performance ($(report.total_import_time)s)")
end
```

## Advanced Usage

### Custom Timing Analysis

For specialized analysis needs:

```julia
# Generate report without console output
report = generate_import_timing_report("/path/to/package")

# Access raw @time_imports output for custom parsing
raw_output = report.raw_output
println("Raw timing data:")
println(raw_output)

# Analyze specific patterns
precompile_heavy = filter(t -> t.precompile_time > t.load_time, report.major_contributors)
load_heavy = filter(t -> t.load_time > t.precompile_time, report.major_contributors)
```

### Trend Analysis

Combine with version control for regression detection:

```julia
# Compare import times across git commits
function analyze_import_trend(repo_path, commits)
    results = []
    for commit in commits
        run(`git -C $repo_path checkout $commit`)
        report = generate_import_timing_report(repo_path)
        push!(results, (commit, report.total_import_time))
    end
    return results
end
```

## Troubleshooting

### Common Issues

1. **Analysis Fails**: Ensure the package can be imported successfully
2. **Missing Dependencies**: Run `Pkg.instantiate()` in the target repository
3. **Permission Errors**: Ensure read access to repositories
4. **Timeout Issues**: Some packages may take very long to import

### Performance Considerations

- Analysis runs in separate Julia processes to ensure clean timing
- Large organizations may take significant time to analyze
- Consider using `max_repos` parameter for initial testing
- Network speed affects repository cloning time

### Interpreting Results

- **Precompilation Time**: Usually one-time cost, optimizable with system images
- **Load Time**: Runtime cost for every import, focus optimization here
- **Dependency Chain**: Earlier dependencies affect later ones
- **Local vs External**: You can only directly optimize local package timing

## Integration Examples

### GitHub Actions

```yaml
name: Import Time Check
on: [push, pull_request]
jobs:
  import-timing:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: julia-actions/setup-julia@v1
      - name: Analyze Import Timing
        run: |
          julia -e '
            using Pkg; Pkg.add("OrgMaintenanceScripts")
            using OrgMaintenanceScripts
            report = analyze_repo_import_timing(".")
            if report.total_import_time > 5.0
              error("Import time too slow: $(report.total_import_time)s")
            end
          '
```

### Organization Monitoring

```julia
# Weekly organization analysis
function weekly_import_analysis(org)
    results = analyze_org_import_timing(org; 
        auth_token=ENV["GITHUB_TOKEN"],
        output_dir="weekly_reports/$(today())"
    )
    
    # Generate alerts for regressions
    slow_packages = [name for (name, report) in results if report.total_import_time > 10.0]
    
    if !isempty(slow_packages)
        println("⚠️ Slow packages detected:")
        for pkg in slow_packages
            println("- $pkg: $(results[pkg].total_import_time)s")
        end
    end
    
    return results
end
```