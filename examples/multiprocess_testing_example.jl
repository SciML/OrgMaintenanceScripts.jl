"""
Example usage of the multiprocess testing functionality in OrgMaintenanceScripts.jl

This example demonstrates how to use the new multiprocess testing features to run
tests locally in parallel, similar to GitHub Actions CI workflows.
"""

using OrgMaintenanceScripts
using Distributed

# Example 1: Test a repository directly from its URL
function example_test_from_repo()
    println("Example 1: Testing OrdinaryDiffEq.jl from repository")
    
    # This will clone the repo (if needed) and run all test groups in parallel
    summary = run_tests_from_repo(
        "https://github.com/SciML/OrdinaryDiffEq.jl",
        branch="master",
        workflow_path=".github/workflows/CI.yml",
        log_dir="ordinarily_diffeq_test_logs"
    )
    
    # Print summary
    print_test_summary(summary)
    
    # Generate detailed report
    report = generate_test_summary_report(summary, "ordinarily_diffeq_test_report.txt")
    println("Detailed report saved to: ordinarily_diffeq_test_report.txt")
    
    return summary
end

# Example 2: Test a local repository
function example_test_local_repo()
    println("Example 2: Testing a local repository")
    
    # Assume we have a local clone of a repository
    project_path = "./SomePackage.jl"  # Path to your local Julia package
    workflow_file = joinpath(project_path, ".github/workflows/CI.yml")
    
    if isfile(workflow_file)
        summary = run_multiprocess_tests(
            workflow_file,
            project_path,
            log_dir="local_test_logs",
            max_workers=4  # Limit to 4 parallel processes
        )
        
        print_test_summary(summary)
        return summary
    else
        println("No CI workflow file found at: $workflow_file")
        return nothing
    end
end

# Example 3: Parse CI workflow and examine test groups
function example_parse_workflow()
    println("Example 3: Parsing CI workflow file")
    
    workflow_file = ".github/workflows/CI.yml"  # Assuming we're in a repo directory
    
    if isfile(workflow_file)
        test_groups = parse_ci_workflow(workflow_file)
        
        println("Found $(length(test_groups)) test groups:")
        for (i, group) in enumerate(test_groups)
            println("  $i. $(group.name)")
            if !isempty(group.env_vars)
                println("     Environment: $(group.env_vars)")
            end
            if group.continue_on_error
                println("     Continue on error: true")
            end
        end
        
        return test_groups
    else
        println("No CI workflow file found")
        return TestGroup[]
    end
end

# Example 4: Run specific test groups only
function example_run_specific_groups()
    println("Example 4: Running specific test groups")
    
    # Create test groups manually
    test_groups = [
        TestGroup("InterfaceI", env_vars=Dict("GROUP" => "InterfaceI")),
        TestGroup("InterfaceII", env_vars=Dict("GROUP" => "InterfaceII")),
        TestGroup("OrdinaryDiffEqCore", env_vars=Dict("GROUP" => "OrdinaryDiffEqCore"))
    ]
    
    project_path = "./OrdinaryDiffEq.jl"  # Assuming local clone
    log_dir = "specific_groups_logs"
    
    if isdir(project_path)
        # Set up environment
        setup_test_environment(project_path)
        
        # Run tests in parallel using pmap
        results = pmap(test_groups) do group
            run_single_test_group(group, project_path, log_dir)
        end
        
        # Create summary
        start_time = minimum(r.start_time for r in results)
        end_time = maximum(r.end_time for r in results)
        total_duration = (end_time - start_time).value / 1000.0
        
        summary = TestSummary(
            length(test_groups),
            count(r -> r.success, results),
            count(r -> !r.success, results),
            total_duration,
            results,
            start_time,
            end_time
        )
        
        print_test_summary(summary)
        return summary
    else
        println("Project directory not found: $project_path")
        return nothing
    end
end

# Example 5: Claude-friendly testing function
function claude_run_tests(repo_url_or_path::String; max_parallel::Int=4)
    """
    Simplified function for Claude to easily run multiprocess tests.
    
    Args:
        repo_url_or_path: Either a GitHub URL or local path to a Julia package
        max_parallel: Maximum number of parallel test processes
    
    Returns:
        A tuple of (success::Bool, summary::TestSummary, failed_groups::Vector{String})
    """
    
    try
        if startswith(repo_url_or_path, "http")
            # It's a URL, use run_tests_from_repo
            summary = run_tests_from_repo(repo_url_or_path, log_dir="claude_test_logs")
        else
            # It's a local path
            workflow_file = joinpath(repo_url_or_path, ".github/workflows/CI.yml")
            if !isfile(workflow_file)
                @error "No CI workflow file found at: $workflow_file"
                return (false, nothing, ["No CI workflow file"])
            end
            
            summary = run_multiprocess_tests(
                workflow_file, 
                repo_url_or_path, 
                log_dir="claude_test_logs",
                max_workers=max_parallel
            )
        end
        
        # Print results
        print_test_summary(summary)
        
        # Generate report
        report_file = "claude_test_report_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")).txt"
        generate_test_summary_report(summary, report_file)
        
        # Extract failed group names
        failed_groups = [r.group.name for r in summary.results if !r.success]
        
        overall_success = summary.failed_groups == 0
        
        return (overall_success, summary, failed_groups)
        
    catch e
        @error "Error running tests" exception=e
        return (false, nothing, [string(e)])
    end
end

# Main function to run all examples
function run_all_examples()
    println("="^80)
    println("MULTIPROCESS TESTING EXAMPLES")
    println("="^80)
    
    # Add some worker processes for parallel execution
    if nprocs() == 1
        addprocs(2)
        @everywhere using OrgMaintenanceScripts
    end
    
    # Run examples (comment out as needed)
    # example_parse_workflow()
    # example_test_local_repo()  
    # example_run_specific_groups()
    # example_test_from_repo()  # This will actually clone and test - use carefully!
    
    println("Examples completed. Uncomment specific examples in run_all_examples() to try them.")
end

# Quick test function for immediate use
function quick_test_demo()
    """
    A quick demo that doesn't require external repositories.
    Creates a minimal test scenario to demonstrate the functionality.
    """
    
    println("Quick demo of multiprocess testing structures:")
    
    # Create sample test groups
    sample_groups = [
        TestGroup("FastTests", env_vars=Dict("GROUP" => "FastTests")),
        TestGroup("SlowTests", env_vars=Dict("GROUP" => "SlowTests")),
        TestGroup("Integration", env_vars=Dict("GROUP" => "Integration"), continue_on_error=true)
    ]
    
    println("Sample test groups:")
    for (i, group) in enumerate(sample_groups)
        println("  $i. $(group.name)")
        println("     Env: $(group.env_vars)")
        println("     Continue on error: $(group.continue_on_error)")
    end
    
    # Show what a test result would look like
    sample_result = TestResult(
        sample_groups[1],
        true,  # success
        45.2,  # duration
        "test_logs/FastTests.log",
        nothing,  # no error
        now(),
        now() + Dates.Second(45)
    )
    
    println("\nSample test result structure:")
    println("  Group: $(sample_result.group.name)")
    println("  Success: $(sample_result.success)")
    println("  Duration: $(sample_result.duration)s")
    println("  Log file: $(sample_result.log_file)")
    
    return sample_groups
end

if abspath(PROGRAM_FILE) == @__FILE__
    # Run the quick demo if this file is executed directly
    quick_test_demo()
end