module MultiprocessTesting

using Distributed
using Dates
using YAML
using Pkg
using Logging
using Printf

export TestGroup, TestResult, TestSummary
export parse_ci_workflow, setup_test_environment, run_single_test_group
export run_multiprocess_tests, generate_test_summary_report, print_test_summary
export run_tests_from_repo, claude_run_tests

struct TestGroup
    name::String
    env_vars::Dict{String, String}
    continue_on_error::Bool
    
    function TestGroup(name::String; env_vars=Dict{String, String}(), continue_on_error=false)
        new(name, env_vars, continue_on_error)
    end
end

struct TestResult
    group::TestGroup
    success::Bool
    duration::Float64
    log_file::String
    error_message::Union{String, Nothing}
    start_time::DateTime
    end_time::DateTime
end

struct TestSummary
    total_groups::Int
    passed_groups::Int
    failed_groups::Int
    total_duration::Float64
    results::Vector{TestResult}
    start_time::DateTime
    end_time::DateTime
end

function parse_ci_workflow(workflow_file::String)
    if !isfile(workflow_file)
        error("Workflow file not found: $workflow_file")
    end
    
    yaml_content = YAML.load_file(workflow_file)
    test_groups = TestGroup[]
    
    jobs = get(yaml_content, "jobs", Dict())
    test_job = get(jobs, "test", Dict())
    strategy = get(test_job, "strategy", Dict())
    matrix = get(strategy, "matrix", Dict())
    
    groups = get(matrix, "group", String[])
    
    continue_on_error_expr = get(test_job, "continue-on-error", false)
    
    for group_name in groups
        continue_on_error = false
        if isa(continue_on_error_expr, String) && contains(continue_on_error_expr, "matrix.group")
            continue_on_error = contains(continue_on_error_expr, "'$group_name'")
        end
        
        env_vars = Dict("GROUP" => group_name)
        
        push!(test_groups, TestGroup(group_name; env_vars=env_vars, continue_on_error=continue_on_error))
    end
    
    return test_groups
end

function setup_test_environment(project_path::String)
    if !isdir(project_path)
        error("Project path not found: $project_path")
    end
    
    cd(project_path)
    
    Pkg.activate(".")
    
    try
        Pkg.resolve()
        @info "Project environment activated and resolved" project_path
    catch e
        @warn "Failed to resolve project environment" exception=e
        rethrow(e)
    end
end

function run_single_test_group(group::TestGroup, project_path::String, log_dir::String)
    start_time = now()
    log_file = joinpath(log_dir, "$(group.name).log")
    
    mkpath(log_dir)
    
    io = open(log_file, "w")
    logger = SimpleLogger(io)
    
    success = false
    error_message = nothing
    
    try
        with_logger(logger) do
            @info "Starting test group: $(group.name)" timestamp=start_time
            @info "Project path: $project_path"
            @info "Environment variables: $(group.env_vars)"
            
            for (key, value) in group.env_vars
                ENV[key] = value
                @info "Set environment variable: $key = $value"
            end
            
            cd(project_path)
            
            @info "Running Pkg.test()..."
            
            redirect_stdout(io) do
                redirect_stderr(io) do
                    try
                        Pkg.test()
                        @info "Test completed successfully"
                        success = true
                    catch e
                        @error "Test failed with exception" exception=e
                        error_message = string(e)
                        if !group.continue_on_error
                            rethrow(e)
                        end
                    end
                end
            end
        end
    catch e
        error_message = string(e)
        with_logger(logger) do
            @error "Fatal error during test execution" exception=e
        end
    finally
        close(io)
        
        for key in keys(group.env_vars)
            delete!(ENV, key)
        end
    end
    
    end_time = now()
    duration = (end_time - start_time).value / 1000.0
    
    return TestResult(group, success, duration, log_file, error_message, start_time, end_time)
end

function run_multiprocess_tests(workflow_file::String, project_path::String; 
                               log_dir::String="test_logs", max_workers::Int=4)
    
    start_time = now()
    
    @info "Parsing CI workflow file: $workflow_file"
    test_groups = parse_ci_workflow(workflow_file)
    @info "Found $(length(test_groups)) test groups"
    
    @info "Setting up test environment"
    setup_test_environment(project_path)
    
    log_dir = abspath(log_dir)
    mkpath(log_dir)
    @info "Logs will be written to: $log_dir"
    
    current_workers = nprocs() - 1
    needed_workers = min(max_workers, length(test_groups)) - current_workers
    
    if needed_workers > 0
        @info "Adding $needed_workers worker processes"
        addprocs(needed_workers)
        
        @everywhere using Pkg, Dates, Logging
    end
    
    @info "Running tests with $(nprocs() - 1) worker processes"
    
    results = pmap(test_groups) do group
        run_single_test_group(group, project_path, log_dir)
    end
    
    end_time = now()
    total_duration = (end_time - start_time).value / 1000.0
    
    passed_groups = count(r -> r.success, results)
    failed_groups = length(results) - passed_groups
    
    summary = TestSummary(
        length(test_groups),
        passed_groups,
        failed_groups,
        total_duration,
        results,
        start_time,
        end_time
    )
    
    return summary
end

function generate_test_summary_report(summary::TestSummary, output_file::Union{String, Nothing}=nothing)
    io = IOBuffer()
    
    println(io, "="^80)
    println(io, "MULTIPROCESS TEST SUMMARY REPORT")
    println(io, "="^80)
    println(io)
    
    println(io, "Start Time: $(summary.start_time)")
    println(io, "End Time: $(summary.end_time)")
    println(io, "Total Duration: $(@sprintf("%.2f", summary.total_duration)) seconds")
    println(io)
    
    println(io, "Test Results:")
    println(io, "  Total Groups: $(summary.total_groups)")
    println(io, "  Passed: $(summary.passed_groups)")
    println(io, "  Failed: $(summary.failed_groups)")
    println(io, "  Success Rate: $(@sprintf("%.1f", (summary.passed_groups / summary.total_groups) * 100))%")
    println(io)
    
    sorted_results = sort(summary.results, by=r -> r.duration, rev=true)
    
    println(io, "Individual Test Group Results:")
    println(io, "-"^80)
    
    for result in sorted_results
        status = result.success ? "✓ PASS" : "✗ FAIL"
        duration_str = @sprintf("%8.2fs", result.duration)
        
        println(io, "$status $duration_str $(result.group.name)")
        
        if !result.success && result.error_message !== nothing
            error_preview = length(result.error_message) > 100 ? 
                            result.error_message[1:100] * "..." : 
                            result.error_message
            println(io, "    Error: $error_preview")
        end
        
        println(io, "    Log: $(result.log_file)")
        println(io)
    end
    
    failed_results = filter(r -> !r.success, summary.results)
    if !isempty(failed_results)
        println(io, "FAILED GROUPS SUMMARY:")
        println(io, "-"^40)
        for result in failed_results
            println(io, "• $(result.group.name)")
            println(io, "  Log: $(result.log_file)")
            if result.error_message !== nothing
                println(io, "  Error: $(result.error_message)")
            end
            println(io)
        end
    end
    
    report = String(take!(io))
    
    if output_file !== nothing
        open(output_file, "w") do f
            write(f, report)
        end
        @info "Test summary report written to: $output_file"
    end
    
    return report
end

function print_test_summary(summary::TestSummary)
    println()
    println("="^60)
    println("TEST SUMMARY")
    println("="^60)
    
    success_rate = (summary.passed_groups / summary.total_groups) * 100
    
    status_color = summary.failed_groups == 0 ? :green : :red
    
    printstyled("Total: $(summary.total_groups) | ", color=:blue)
    printstyled("Passed: $(summary.passed_groups) | ", color=:green)  
    printstyled("Failed: $(summary.failed_groups) | ", color=:red)
    printstyled(@sprintf("Success: %.1f%%", success_rate), color=status_color)
    println()
    
    printstyled(@sprintf("Duration: %.2f seconds", summary.total_duration), color=:blue)
    println()
    
    if summary.failed_groups > 0
        println("\nFailed Groups:")
        for result in filter(r -> !r.success, summary.results)
            printstyled("  • $(result.group.name)", color=:red)
            println(" ($(result.log_file))")
        end
    end
    
    println("="^60)
end

function run_tests_from_repo(repo_url::String; branch::String="master", 
                            workflow_path::String=".github/workflows/CI.yml",
                            log_dir::String="test_logs")
    
    repo_name = split(repo_url, "/")[end]
    if endswith(repo_name, ".git")
        repo_name = repo_name[1:end-4]
    end
    
    if !isdir(repo_name)
        @info "Cloning repository: $repo_url"
        run(`git clone -b $branch $repo_url $repo_name`)
    else
        @info "Repository already exists: $repo_name"
        cd(repo_name) do
            run(`git pull origin $branch`)
        end
    end
    
    project_path = abspath(repo_name)
    workflow_file = joinpath(project_path, workflow_path)
    
    return run_multiprocess_tests(workflow_file, project_path; log_dir=log_dir)
end

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
            summary = run_tests_from_repo(repo_url_or_path, log_dir="claude_test_logs")
        else
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
        
        print_test_summary(summary)
        
        report_file = "claude_test_report_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")).txt"
        generate_test_summary_report(summary, report_file)
        
        failed_groups = [r.group.name for r in summary.results if !r.success]
        
        overall_success = summary.failed_groups == 0
        
        return (overall_success, summary, failed_groups)
        
    catch e
        @error "Error running tests" exception=e
        return (false, nothing, [string(e)])
    end
end

end # module