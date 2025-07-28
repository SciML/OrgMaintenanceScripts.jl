#!/usr/bin/env julia

# Example usage of the invalidation analysis functionality

using OrgMaintenanceScripts

println("=== Invalidation Analysis Examples ===")

# Example 1: Analyze current repository
println("\n=== Example 1: Analyzing Current Repository ===")
current_repo = dirname(@__DIR__)  # OrgMaintenanceScripts.jl repo

try
    # Note: This will analyze the OrgMaintenanceScripts package itself
    report = analyze_repo_invalidations(current_repo)
    
    println("Analysis completed for: $(report.repo)")
    println("Total invalidations: $(report.total_invalidations)")
    println("Summary: $(report.summary)")
    
    if !isempty(report.major_invalidators)
        println("\nTop invalidators:")
        for (i, inv) in enumerate(report.major_invalidators[1:min(3, end)])
            println("  $i. $(inv.package) - $(inv.children_count) children")
        end
    end
    
catch e
    println("Note: Analysis failed - this is expected if SnoopCompileCore is not available")
    println("Error: $e")
end

# Example 2: Custom test script
println("\n=== Example 2: Custom Test Script ===")
custom_test_script = """
    # Custom analysis script
    using OrgMaintenanceScripts
    
    # Test specific functionality that might cause invalidations
    try
        # Test the version check finder
        checks = find_version_checks_in_repo(".")
        println("Found \$(length(checks)) version checks")
        
        # Test the formatting functionality  
        # (This is just an example - actual analysis would depend on package)
    catch e
        println("Custom test failed: \$e")
    end
"""

println("Example custom test script:")
println(custom_test_script)

# Example 3: Organization analysis (demonstration only)
println("\n=== Example 3: Organization Analysis (Demo) ===")
println("To analyze an entire organization:")
println("""
    # Set up authentication
    github_token = ENV["GITHUB_TOKEN"]
    
    # Analyze a small organization or subset
    results = analyze_org_invalidations("MyOrg", 
        auth_token=github_token,
        output_dir="invalidation_reports",
        max_repos=5  # Limit for testing
    )
    
    # Print summary
    for (repo, report) in results
        println("\$repo: \$(report.total_invalidations) invalidations")
    end
""")

# Example 4: Understanding the report structure
println("\n=== Example 4: Report Structure ===")
println("InvalidationReport contains:")
println("- repo: Repository name")
println("- total_invalidations: Total count of invalidations")
println("- major_invalidators: List of most problematic invalidations")
println("- packages_affected: Packages involved in invalidations")
println("- analysis_time: When analysis was performed")
println("- summary: Human-readable summary with status")
println("- recommendations: Actionable suggestions for improvement")

println("\nInvalidationEntry contains:")
println("- method: Method signature that was invalidated")
println("- file: Source file location")
println("- line: Line number")
println("- package: Package that owns the method")
println("- reason: Why this invalidation is problematic")
println("- children_count: Number of methods this invalidation affects")
println("- depth: Position in invalidation tree")

# Example 5: Integration with CI/CD
println("\n=== Example 5: CI/CD Integration ===")
println("Example CI script:")
ci_script = """
#!/usr/bin/env julia

using OrgMaintenanceScripts

# Analyze current repository
report = analyze_repo_invalidations(".")

# Set thresholds based on project requirements
max_invalidations = 20
warning_threshold = 10

if report.total_invalidations > max_invalidations
    println("❌ FAILED: Too many invalidations (\$(report.total_invalidations) > \$max_invalidations)")
    println("Summary: \$(report.summary)")
    exit(1)
elseif report.total_invalidations > warning_threshold
    println("⚠️  WARNING: Moderate invalidations (\$(report.total_invalidations))")
    println("Consider investigating before next release")
else
    println("✅ PASSED: Low invalidations (\$(report.total_invalidations))")
end

# Always print recommendations
println("\\nRecommendations:")
for rec in report.recommendations
    println("- \$rec")
end
"""

println(ci_script)

println("\n=== Analysis Complete ===")
println("For more information, see the documentation at:")
println("https://sciml.github.io/OrgMaintenanceScripts.jl/dev/invalidation_analysis/")