#!/usr/bin/env julia

# Example usage of the import timing analysis functionality

using OrgMaintenanceScripts

println("=== Import Timing Analysis Examples ===")

# Example 1: Analyze current repository
println("\n=== Example 1: Analyzing Current Repository ===")
current_repo = dirname(@__DIR__)  # OrgMaintenanceScripts.jl repo

try
    # Note: This will analyze the OrgMaintenanceScripts package itself
    report = analyze_repo_import_timing(current_repo)
    
    println("Analysis completed for: $(report.repo)")
    println("Package: $(report.package_name)")
    println("Total import time: $(round(report.total_import_time, digits=2)) seconds")
    println("Summary: $(report.summary)")
    
    if !isempty(report.major_contributors)
        println("\nTop import contributors:")
        for (i, timing) in enumerate(report.major_contributors[1:min(5, end)])
            local_marker = timing.is_local ? " (LOCAL)" : ""
            println("  $i. $(timing.package_name)$local_marker - $(round(timing.total_time, digits=2))s")
        end
    end
    
    if !isempty(report.dependency_chain)
        println("\nDependency load order (first 5):")
        for (i, dep) in enumerate(report.dependency_chain[1:min(5, end)])
            println("  $i. $dep")
        end
    end
    
catch e
    println("Note: Analysis failed - this might happen if the package structure is complex")
    println("Error: $e")
end

# Example 2: Understanding the data structures
println("\n=== Example 2: Understanding Import Timing Data ===")
println("ImportTiming structure contains:")
println("- package_name: Name of the package")
println("- total_time: Total import time in seconds")
println("- precompile_time: Time spent in precompilation")
println("- load_time: Time spent loading (excluding precompilation)")
println("- dependencies: Direct dependencies")
println("- dep_count: Number of dependencies")
println("- is_local: Whether this is the local package being analyzed")

println("\nImportTimingReport structure contains:")
println("- repo: Repository name")
println("- package_name: Package being analyzed")
println("- total_import_time: Total time to import the package")
println("- major_contributors: Packages contributing most to import time")
println("- dependency_chain: Order in which dependencies are loaded")
println("- analysis_time: When the analysis was performed")
println("- summary: Human-readable summary with performance classification")
println("- recommendations: Actionable suggestions for optimization")
println("- raw_output: Raw @time_imports output for debugging")

# Example 3: Organization analysis (demonstration only)
println("\n=== Example 3: Organization Analysis (Demo) ===")
println("To analyze an entire organization:")
println("""
    # Set up authentication
    github_token = ENV["GITHUB_TOKEN"]
    
    # Analyze a small organization or subset
    results = analyze_org_import_timing("MyOrg", 
        auth_token=github_token,
        output_dir="import_timing_reports",
        max_repos=5  # Limit for testing
    )
    
    # Find slowest packages
    slowest = sort([(name, r.total_import_time) for (name, r) in results], 
                   by=x->x[2], rev=true)
    
    println("Slowest packages:")
    for (name, time) in slowest[1:5]
        println("\$name: \$(round(time, digits=2))s")
    end
""")

# Example 4: Interpreting results and optimization strategies
println("\n=== Example 4: Import Time Optimization Strategies ===")
println("Based on import timing patterns:")
println()
println("📊 Performance Classifications:")
println("✅ < 1s:    Excellent user experience")
println("✅ 1-3s:    Good performance, acceptable for most use cases")
println("⚠️  3-10s:   Moderate delay, room for improvement")
println("❌ > 10s:   Poor user experience, immediate optimization needed")
println()
println("🔧 Common Optimization Techniques:")
println("1. High Precompilation Time:")
println("   → Use PackageCompiler.jl to create system images")
println("   → Optimize precompile statements")
println()
println("2. Slow Dependencies:")
println("   → Consider alternative packages with better performance")
println("   → Use lazy loading with Requires.jl")
println("   → Implement package extensions (Julia 1.9+)")
println()
println("3. Many Dependencies:")
println("   → Reduce dependency count if possible")
println("   → Split package into smaller, focused modules")
println()
println("4. Large Load Times:")
println("   → Profile package initialization code")
println("   → Defer expensive computations until needed")

# Example 5: CI/CD Integration
println("\n=== Example 5: CI/CD Integration ===")
println("Example CI script for import time monitoring:")
ci_script = """
#!/usr/bin/env julia

using OrgMaintenanceScripts

# Analyze current repository
report = analyze_repo_import_timing(".")

# Set thresholds based on package type
max_import_time = 5.0     # seconds - hard limit
warning_threshold = 2.0   # seconds - warning level

println("Import Time Analysis Results:")
println("Package: \$(report.package_name)")
println("Total import time: \$(round(report.total_import_time, digits=2))s")

if report.total_import_time > max_import_time
    println("❌ FAILED: Import time too slow (\$(report.total_import_time)s > \$(max_import_time)s)")
    println("This will negatively impact user experience.")
    exit(1)
elseif report.total_import_time > warning_threshold
    println("⚠️  WARNING: Import time is increasing (\$(report.total_import_time)s)")
    println("Consider optimizing before the next release.")
else
    println("✅ PASSED: Good import performance (\$(report.total_import_time)s)")
end

# Always print top contributors for optimization insights
println("\\nTop import contributors:")
for (i, timing) in enumerate(report.major_contributors[1:min(3, end)])
    println("\$i. \$(timing.package_name): \$(round(timing.total_time, digits=2))s")
end

# Print recommendations
println("\\nRecommendations:")
for rec in report.recommendations
    println("- \$rec")
end
"""

println(ci_script)

# Example 6: Advanced usage patterns
println("\n=== Example 6: Advanced Usage Patterns ===")
println("Custom analysis for different scenarios:")
println()
println("🌐 Web Framework Analysis:")
println("# Focus on startup time for web applications")
println("report = analyze_repo_import_timing(\"/path/to/web/framework\")")
println("startup_critical = filter(t -> t.total_time > 0.5, report.major_contributors)")
println()
println("📊 Data Science Package Analysis:")
println("# Identify heavy computational dependencies")
println("report = analyze_repo_import_timing(\"/path/to/data/package\")")
println("heavy_deps = filter(t -> t.precompile_time > 2.0, report.major_contributors)")
println()
println("🔄 Trend Analysis:")
println("# Compare import times across versions")
println("function analyze_import_trend(repo_path, versions)")
println("    results = []")
println("    for version in versions")
println("        run(`git -C \$repo_path checkout \$version`)")
println("        report = generate_import_timing_report(repo_path)")
println("        push!(results, (version, report.total_import_time))")
println("    end")
println("    return results")
println("end")

println("\n=== Analysis Complete ===")
println("For more information, see the documentation at:")
println("https://sciml.github.io/OrgMaintenanceScripts.jl/dev/import_timing_analysis/")