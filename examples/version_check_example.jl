#!/usr/bin/env julia

# Example usage of the version check finder functionality

using OrgMaintenanceScripts

# Example 1: Find version checks in a single file
println("=== Example 1: Finding version checks in a single file ===")
example_file = joinpath(@__DIR__, "..", "test", "version_check_finder_tests.jl")
if isfile(example_file)
    checks = find_version_checks_in_file(example_file)
    println("Found $(length(checks)) version checks in test file")
    for (i, check) in enumerate(checks[1:min(3, end)])
        println("  $i. Line $(check.line_number): $(check.pattern_match) (v$(check.version))")
    end
end

# Example 2: Find version checks in a repository
println("\n=== Example 2: Finding version checks in a repository ===")
repo_path = dirname(@__DIR__)  # OrgMaintenanceScripts.jl repo
checks = find_version_checks_in_repo(repo_path)
println("Found $(length(checks)) total version checks in repository")

# Example 3: Write results to a script
if !isempty(checks)
    println("\n=== Example 3: Writing results to a script ===")
    script_file = tempname() * "_version_checks.jl"
    write_version_checks_to_script(checks[1:min(5, end)], script_file)
    println("Script written to: $script_file")
    println("First few lines of the script:")
    for line in readlines(script_file)[1:10]
        println("  ", line)
    end
end

# Example 4: Demonstrate parallel fixing (dry run)
println("\n=== Example 4: Parallel fixing demonstration ===")
println("To fix version checks in parallel across an organization:")
println("""
    # Set your GitHub token
    github_token = ENV["GITHUB_TOKEN"]
    
    # Fix all obsolete version checks in the SciML organization
    results = fix_org_version_checks_parallel("SciML", 4; 
        github_token=github_token,
        min_version=v"1.10"
    )
""")

println("\nNote: The parallel fixing will create PRs to remove obsolete version checks.")
println("Each PR will be handled by Claude to ensure proper code changes.")
