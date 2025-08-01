# Documentation Cleanup

The documentation cleanup functionality addresses the common problem of repository bloat caused by large HTML files with embedded SVG plots from documentation builds.

## Problem Description

Julia packages with documentation often generate very large HTML files (30+ MB) when:
- Tutorials contain complex plots rendered as SVG
- Multiple documentation versions are preserved 
- CI builds create preview/development versions
- Large embedded plots are stored inline in HTML

This leads to:
- Gigabyte-sized repositories that are slow to clone
- Poor developer experience for contributors
- Wasted storage and bandwidth
- Slow documentation website loading

## Functions

### `cleanup_gh_pages_docs`

```julia
cleanup_gh_pages_docs(repo_path::String; 
                     preserve_latest::Bool=true, 
                     dry_run::Bool=false, 
                     size_threshold_mb::Float64=5.0)
```

Clean up bloated documentation in a repository's gh-pages branch.

**Arguments:**
- `repo_path`: Path to the Git repository
- `preserve_latest`: Whether to preserve the latest version documentation (default: true)
- `dry_run`: If true, only show what would be cleaned without making changes (default: false)
- `size_threshold_mb`: Remove files larger than this threshold in MB (default: 5.0)

**Returns:** A named tuple with cleanup statistics including files removed, size saved, and success status.

**Example:**
```julia
# Safe dry run first
result = cleanup_gh_pages_docs("/path/to/repo", dry_run=true)
println("Would save: $(result.size_saved_mb) MB")

# Actual cleanup
result = cleanup_gh_pages_docs("/path/to/repo")
if result.success
    println("Cleaned $(result.files_removed) files")
    println("⚠️  Run: git push --force origin gh-pages")
end
```

### `analyze_gh_pages_bloat`

```julia
analyze_gh_pages_bloat(repo_path::String)
```

Analyze documentation bloat without making changes. Perfect for understanding the scope of the problem before cleanup.

**Returns:** Analysis results including total size, large files list, and detailed report.

**Example:**
```julia
analysis = analyze_gh_pages_bloat("/path/to/repo")
println("Repository has $(analysis.total_size_mb) MB of bloat")
println("Largest files:")
for file in analysis.large_files[1:5]
    println("  $(file.size_mb) MB - $(file.path)")
end
```

### `cleanup_org_gh_pages_docs`

```julia
cleanup_org_gh_pages_docs(org_repos::Vector{String}; 
                          preserve_latest::Bool=true,
                          dry_run::Bool=false, 
                          size_threshold_mb::Float64=5.0,
                          working_dir::String=mktempdir())
```

Clean up documentation bloat across multiple repositories in an organization.

**Example:**
```julia
repos = [
    "https://github.com/SciML/DifferentialEquations.jl.git",
    "https://github.com/SciML/JumpProcesses.jl.git"
]

results = cleanup_org_gh_pages_docs(repos, dry_run=true)
total_savings = sum(r.size_saved_mb for r in results if r.success)
println("Organization could save $(total_savings) MB")
```

## Safety Features

The documentation cleanup functions are designed with safety in mind:

- **Dry-run mode**: Test what would be cleaned without making changes
- **Latest version preservation**: Automatically detects and preserves the most recent documentation
- **Branch isolation**: Only operates on gh-pages branch, never touches code branches or tags
- **Error handling**: Comprehensive validation and error recovery
- **Git cleanup**: Proper garbage collection to reclaim space

## Common Workflow

1. **Analyze the problem:**
   ```julia
   analysis = analyze_gh_pages_bloat("/path/to/repo")
   ```

2. **Test the cleanup safely:**
   ```julia
   result = cleanup_gh_pages_docs("/path/to/repo", dry_run=true)
   ```

3. **Perform the cleanup:**
   ```julia
   result = cleanup_gh_pages_docs("/path/to/repo")
   ```

4. **Force push the changes:**
   ```bash
   git push --force origin gh-pages
   ```

5. **Notify contributors** about the history rewrite

## What Gets Cleaned

The cleanup process identifies and removes:

- **Old version directories**: `v1.0.0/`, `v1.1.0/`, etc. (except latest)
- **Development builds**: `dev/`, `previews/`, `preview-*/`
- **Large files**: Files exceeding the size threshold (default 5MB)
- **Git objects**: Runs garbage collection to reclaim space

## Best Practices

1. **Always run analysis first** to understand the scope
2. **Use dry-run mode** before actual cleanup
3. **Backup important repositories** before running
4. **Coordinate with team** before rewriting Git history
5. **Run during low-activity periods** to minimize disruptions
6. **Combine with PNG plot fixes** for comprehensive solution

## Integration with Other Tools

The documentation cleanup works best when combined with:

- **PNG plot forcing**: Prevent future SVG bloat in documentation builds
- **Size limits**: Set `example_size_threshold` in Documenter.jl
- **CI optimizations**: Limit preview builds and retention periods
- **Regular maintenance**: Schedule periodic cleanup for active repositories

## Example Output

```
Documentation Cleanup Tool - Analysis Results:
  Total documentation size: 6074.5 MB
  Number of versions: 15
  Latest version: v2.1.0
  Large files found: 415

Top 5 largest files:
    37.8 MB - previews/PR345/tutorials/example/index.html
    37.8 MB - dev/tutorials/example/index.html  
    37.6 MB - v1.5.0/tutorials/example/index.html
    35.2 MB - v1.4.0/tutorials/example/index.html
    34.9 MB - v1.3.0/tutorials/example/index.html

DRY RUN - Would remove:
  160 large files (5366.8 MB)
  12 old version directories
    - v1.0.0/
    - v1.1.0/
    - v1.2.0/
    - dev/
    - previews/
    - preview-123/
```

This functionality can dramatically reduce repository sizes and improve the developer experience across the SciML ecosystem.