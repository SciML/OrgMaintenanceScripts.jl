using Dates
using LibGit2
using Distributed
using HTTP
using JSON3
using TOML
using Random
using Statistics

struct ImportTiming
    package_name::String
    total_time::Float64        # Total compilation time in seconds
    precompile_time::Float64   # Time spent in precompilation
    load_time::Float64         # Time spent loading (excluding precompilation)
    dependencies::Vector{String}  # Direct dependencies
    dep_count::Int            # Number of dependencies
    is_local::Bool            # Whether this is the local package being analyzed
end

struct ImportTimingReport
    repo::String
    package_name::String
    total_import_time::Float64
    major_contributors::Vector{ImportTiming}
    dependency_chain::Vector{String}
    analysis_time::DateTime
    summary::String
    recommendations::Vector{String}
    raw_output::String        # Raw @time_imports output for debugging
end

"""
    analyze_import_timing_in_process(repo_path::String, package_name::String="")

Run import timing analysis in a separate Julia process using @time_imports.
Returns timing data for all packages involved in the import.
"""
function analyze_import_timing_in_process(repo_path::String, package_name::String="")
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end
    
    # Auto-detect package name if not provided
    if isempty(package_name)
        project_path = joinpath(repo_path, "Project.toml")
        if isfile(project_path)
            project = TOML.parsefile(project_path)
            if haskey(project, "name")
                package_name = project["name"]
            else
                error("Could not determine package name from Project.toml")
            end
        else
            error("No Project.toml found in repository")
        end
    end
    
    # Create a simple command to run @time_imports
    @info "Running import timing analysis in separate process..."
    
    # Use a simpler approach: run julia directly with --time-imports flag
    cmd = `julia --project=$repo_path --startup-file=no --time-imports -e "using Pkg; Pkg.activate(\".\"); Pkg.instantiate(); using $package_name"`
    
    # Run and capture output
    try
        output = read(cmd, String)
        
        # Parse the timing output to extract structured data
        timing_data = []
        
        # Split into lines and parse each timing entry
        lines = split(output, '\n')
        
        for line in lines
            line = strip(line)
            if isempty(line) || !contains(line, "ms")
                continue
            end
            
            # Parse timing line format: "  123.4 ms  PackageName"
            # or "  123.4 ms  ✓ PackageName"
            timing_match = match(r"^\s*(\d+\.?\d*)\s*ms\s*([✓]?)\s*(.+)$", line)
            if timing_match !== nothing
                time_ms = parse(Float64, timing_match.captures[1])
                success_marker = timing_match.captures[2]
                pkg_name = strip(timing_match.captures[3])
                
                # Determine if this is precompilation or loading
                is_precompile = isempty(success_marker)  # No checkmark means precompilation
                
                push!(timing_data, Dict(
                    "package" => pkg_name,
                    "time_ms" => time_ms,
                    "time_seconds" => time_ms / 1000.0,
                    "is_precompile" => is_precompile,
                    "is_local" => (pkg_name == package_name),
                    "line" => line
                ))
            end
        end
        
        # Create results
        results = Dict(
            "package_name" => package_name,
            "timing_entries" => timing_data,
            "raw_output" => output,
            "total_entries" => length(timing_data)
        )
        
        return results
        
    catch e
        # If the command failed, rethrow with more context
        if isa(e, Base.IOError) || isa(e, Base.ProcessFailedException)
            error("Failed to run import timing analysis: $e")
        else
            rethrow(e)
        end
    end
end

"""
    parse_import_timings(timing_data::Dict)

Parse the raw timing data and create structured ImportTiming objects.
"""
function parse_import_timings(timing_data::Dict)
    timing_entries = timing_data["timing_entries"]
    
    # Group by package name and aggregate precompile vs load times
    package_timings = Dict{String, Dict{String, Any}}()
    
    for entry in timing_entries
        pkg_name = entry["package"]
        time_seconds = entry["time_seconds"]
        is_precompile = entry["is_precompile"]
        is_local = entry["is_local"]
        
        if !haskey(package_timings, pkg_name)
            package_timings[pkg_name] = Dict(
                "total_time" => 0.0,
                "precompile_time" => 0.0,
                "load_time" => 0.0,
                "is_local" => is_local,
                "dependencies" => String[]  # We'll infer this from order
            )
        end
        
        package_timings[pkg_name]["total_time"] += time_seconds
        
        if is_precompile
            package_timings[pkg_name]["precompile_time"] += time_seconds
        else
            package_timings[pkg_name]["load_time"] += time_seconds
        end
    end
    
    # Convert to ImportTiming objects
    import_timings = ImportTiming[]
    
    for (pkg_name, timing_info) in package_timings
        push!(import_timings, ImportTiming(
            pkg_name,
            timing_info["total_time"],
            timing_info["precompile_time"],
            timing_info["load_time"],
            timing_info["dependencies"],  # TODO: Could be enhanced to detect actual deps
            0,  # TODO: Could count dependencies
            timing_info["is_local"]
        ))
    end
    
    # Sort by total time (descending)
    sort!(import_timings, by=t -> t.total_time, rev=true)
    
    return import_timings
end

"""
    generate_import_timing_report(repo_path::String, package_name::String="")

Generate a comprehensive import timing report for a repository.
"""
function generate_import_timing_report(repo_path::String, package_name::String="")
    @info "Analyzing import timing for: $repo_path"
    
    start_time = now()
    
    try
        # Run timing analysis
        timing_data = analyze_import_timing_in_process(repo_path, package_name)
        
        # Parse the results
        import_timings = parse_import_timings(timing_data)
        
        # Calculate total import time
        total_time = sum(t.total_time for t in import_timings)
        
        # Get major contributors (top contributors or those taking >100ms)
        major_contributors = filter(t -> t.total_time > 0.1 || length(import_timings) <= 10, import_timings)
        if length(major_contributors) > 10
            major_contributors = import_timings[1:10]  # Top 10
        end
        
        # Create dependency chain (ordered by appearance in timing)
        dependency_chain = [t.package_name for t in import_timings if !t.is_local]
        
        # Determine package name
        actual_package_name = timing_data["package_name"]
        
        # Generate summary
        summary = if total_time < 1.0
            "✅ Fast import ($(round(total_time, digits=2))s) - excellent performance"
        elseif total_time < 3.0
            "✅ Good import time ($(round(total_time, digits=2))s) - acceptable performance"
        elseif total_time < 10.0
            "⚠️  Moderate import time ($(round(total_time, digits=2))s) - room for improvement"
        else
            "❌ Slow import time ($(round(total_time, digits=2))s) - significant impact on user experience"
        end
        
        # Generate recommendations
        recommendations = String[]
        
        if total_time > 1.0
            # Find slowest dependencies
            slow_deps = filter(t -> !t.is_local && t.total_time > 0.5, import_timings)
            if !isempty(slow_deps)
                slowest = slow_deps[1]
                push!(recommendations, "Consider reducing dependency on '$(slowest.package_name)' ($(round(slowest.total_time, digits=2))s)")
            end
            
            # Precompilation recommendations
            high_precompile = filter(t -> t.precompile_time > 1.0, import_timings)
            if !isempty(high_precompile)
                push!(recommendations, "High precompilation times detected - consider using PackageCompiler.jl for system images")
            end
            
            # General recommendations
            if length(import_timings) > 10
                push!(recommendations, "Large number of dependencies ($(length(import_timings))) - consider reducing if possible")
            end
            
            if total_time > 5.0
                push!(recommendations, "Consider lazy loading with Requires.jl or package extensions")
                push!(recommendations, "Profile individual dependencies to identify specific bottlenecks")
            end
            
            push!(recommendations, "Use `@time_imports` locally to identify regression sources")
        else
            push!(recommendations, "Excellent import performance! No action needed.")
        end
        
        return ImportTimingReport(
            basename(repo_path),
            actual_package_name,
            total_time,
            major_contributors,
            dependency_chain,
            start_time,
            summary,
            recommendations,
            timing_data["raw_output"]
        )
        
    catch e
        @error "Failed to analyze import timing for $repo_path" exception=(e, catch_backtrace())
        return ImportTimingReport(
            basename(repo_path),
            package_name,
            -1.0,  # Indicates error
            ImportTiming[],
            String[],
            start_time,
            "❌ Analysis failed: $(string(e))",
            ["Check that the repository has a valid Project.toml and the package can be imported successfully"],
            ""
        )
    end
end

"""
    analyze_repo_import_timing(repo_path::String; package_name::String="", output_file::String="")

Analyze import timing in a single repository and optionally save a report.
"""
function analyze_repo_import_timing(repo_path::String; package_name::String="", output_file::String="")
    report = generate_import_timing_report(repo_path, package_name)
    
    # Print summary to console
    println("\\n" * "="^60)
    println("IMPORT TIMING ANALYSIS REPORT")
    println("Repository: $(report.repo)")
    println("Package: $(report.package_name)")
    println("Analysis Time: $(report.analysis_time)")
    println("="^60)
    println(report.summary)
    println("\\nTotal Import Time: $(round(report.total_import_time, digits=2)) seconds")
    
    if report.total_import_time > 0
        println("\\nMajor Contributors:")
        for (i, timing) in enumerate(report.major_contributors)
            local_marker = timing.is_local ? " (LOCAL)" : ""
            println("  $i. $(timing.package_name)$local_marker")
            println("     Total: $(round(timing.total_time, digits=2))s")
            if timing.precompile_time > 0.01
                println("     Precompile: $(round(timing.precompile_time, digits=2))s, Load: $(round(timing.load_time, digits=2))s")
            end
            println()
        end
        
        if !isempty(report.dependency_chain)
            println("\\nDependency Load Order:")
            for (i, dep) in enumerate(report.dependency_chain[1:min(10, end)])
                println("  $i. $dep")
            end
            if length(report.dependency_chain) > 10
                println("  ... and $(length(report.dependency_chain) - 10) more")
            end
        end
    end
    
    println("\\nRecommendations:")
    for (i, rec) in enumerate(report.recommendations)
        println("  $i. $rec")
    end
    println("="^60)
    
    # Save detailed report if requested
    if !isempty(output_file)
        write_import_timing_report(report, output_file)
        @info "Detailed report saved to: $output_file"
    end
    
    return report
end

"""
    analyze_org_import_timing(org::String; auth_token::String="", work_dir::String=mktempdir(), 
                             output_dir::String="", max_repos::Int=0)

Analyze import timing across all repositories in a GitHub organization.
"""
function analyze_org_import_timing(org::String; 
                                 auth_token::String="",
                                 work_dir::String=mktempdir(),
                                 output_dir::String="",
                                 max_repos::Int=0)
    
    @info "Analyzing import timing for organization: $org"
    
    # Get all repositories
    repos = OrgMaintenanceScripts.get_org_repos(org; auth_token)
    
    if isempty(repos)
        @warn "No repositories found for organization: $org"
        return Dict{String, ImportTimingReport}()
    end
    
    if max_repos > 0
        repos = repos[1:min(max_repos, end)]
    end
    
    @info "Found $(length(repos)) repositories to analyze"
    
    results = Dict{String, ImportTimingReport}()
    
    for (i, repo_name) in enumerate(repos)
        @info "Processing repository $i/$(length(repos)): $repo_name"
        
        repo_dir = joinpath(work_dir, basename(repo_name))
        repo_url = "https://github.com/$repo_name.git"
        
        try
            # Clone repository
            run(`git clone --depth 1 $repo_url $repo_dir`)
            
            # Check if it's a Julia package
            if !isfile(joinpath(repo_dir, "Project.toml"))
                @info "Skipping $repo_name - no Project.toml found"
                continue
            end
            
            # Analyze import timing
            report = generate_import_timing_report(repo_dir)
            results[repo_name] = report
            
            # Save individual report if output directory specified
            if !isempty(output_dir)
                mkpath(output_dir)
                repo_report_file = joinpath(output_dir, "$(basename(repo_name))_import_timing.json")
                write_import_timing_report(report, repo_report_file)
            end
            
        catch e
            @error "Failed to process $repo_name" exception=(e, catch_backtrace())
            results[repo_name] = ImportTimingReport(
                repo_name,
                "",
                -1.0,
                ImportTiming[],
                String[],
                now(),
                "❌ Analysis failed: $(string(e))",
                ["Repository could not be cloned or analyzed"],
                ""
            )
        finally
            # Clean up
            rm(repo_dir; force=true, recursive=true)
        end
    end
    
    # Generate organization summary report
    generate_org_import_summary_report(org, results, output_dir)
    
    return results
end

"""
    write_import_timing_report(report::ImportTimingReport, output_file::String)

Write a detailed import timing report to a JSON file.
"""
function write_import_timing_report(report::ImportTimingReport, output_file::String)
    report_data = Dict(
        "repository" => report.repo,
        "package_name" => report.package_name,
        "analysis_time" => string(report.analysis_time),
        "total_import_time" => report.total_import_time,
        "summary" => report.summary,
        "dependency_chain" => report.dependency_chain,
        "recommendations" => report.recommendations,
        "raw_output" => report.raw_output,
        "major_contributors" => [
            Dict(
                "package_name" => timing.package_name,
                "total_time" => timing.total_time,
                "precompile_time" => timing.precompile_time,
                "load_time" => timing.load_time,
                "dependencies" => timing.dependencies,
                "dep_count" => timing.dep_count,
                "is_local" => timing.is_local
            ) for timing in report.major_contributors
        ]
    )
    
    open(output_file, "w") do io
        JSON3.pretty(io, report_data)
    end
end

"""
    generate_org_import_summary_report(org::String, results::Dict{String, ImportTimingReport}, output_dir::String)

Generate a summary report for import timing across the entire organization.
"""
function generate_org_import_summary_report(org::String, results::Dict{String, ImportTimingReport}, output_dir::String)
    if isempty(output_dir)
        output_dir = tempdir()
    end
    
    # Calculate summary statistics
    total_repos = length(results)
    successful_analyses = count(r -> r.total_import_time >= 0, values(results))
    failed_analyses = total_repos - successful_analyses
    
    successful_reports = [r for r in values(results) if r.total_import_time >= 0]
    total_import_time = sum(r.total_import_time for r in successful_reports)
    avg_import_time = successful_analyses > 0 ? total_import_time / successful_analyses : 0
    
    # Find slowest repositories
    slowest_repos = sort([(name, report.total_import_time) for (name, report) in results if report.total_import_time > 0], 
                        by=x -> x[2], rev=true)
    
    # Aggregate slow dependencies across organization
    all_dependencies = Dict{String, Vector{Float64}}()
    for report in successful_reports
        for timing in report.major_contributors
            if !timing.is_local && timing.total_time > 0.1  # Only significant contributors
                if !haskey(all_dependencies, timing.package_name)
                    all_dependencies[timing.package_name] = Float64[]
                end
                push!(all_dependencies[timing.package_name], timing.total_time)
            end
        end
    end
    
    # Calculate average time per dependency across all repos
    dependency_stats = [(dep, mean(times), length(times)) for (dep, times) in all_dependencies]
    sort!(dependency_stats, by=x -> x[2], rev=true)  # Sort by average time
    
    # Generate markdown report
    summary_file = joinpath(output_dir, "$(org)_import_timing_summary.md")
    open(summary_file, "w") do io
        println(io, "# Import Timing Analysis Report for $org")
        println(io, "Generated on: $(now())")
        println(io)
        
        println(io, "## Summary")
        println(io, "- **Total Repositories Analyzed**: $total_repos")
        println(io, "- **Successful Analyses**: $successful_analyses")
        println(io, "- **Failed Analyses**: $failed_analyses")
        println(io, "- **Average Import Time**: $(round(avg_import_time, digits=2)) seconds")
        println(io, "- **Total Import Time Across Org**: $(round(total_import_time, digits=2)) seconds")
        println(io)
        
        if !isempty(slowest_repos)
            println(io, "## Slowest Loading Packages")
            for (i, (repo, time)) in enumerate(slowest_repos[1:min(15, end)])
                status = if time < 1.0
                    "✅"
                elseif time < 3.0
                    "⚠️"
                else
                    "❌"
                end
                println(io, "$i. $status **$repo**: $(round(time, digits=2))s")
            end
            println(io)
        end
        
        if !isempty(dependency_stats)
            println(io, "## Most Problematic Dependencies")
            println(io, "Dependencies that consistently slow down imports across multiple repositories:")
            println(io)
            for (i, (dep, avg_time, repo_count)) in enumerate(dependency_stats[1:min(10, end)])
                println(io, "$i. **$dep**")
                println(io, "   - Average impact: $(round(avg_time, digits=2))s")
                println(io, "   - Affects $repo_count repositories")
                println(io)
            end
        end
        
        println(io, "## Recommendations for $org")
        
        if avg_import_time < 1.0
            println(io, "🎉 Excellent! Average import times are very good across the organization.")
        elseif avg_import_time < 3.0
            println(io, "✅ Good import performance overall. Focus on the slowest packages for improvements.")
        elseif avg_import_time < 8.0
            println(io, "⚠️ Moderate import times. Consider organization-wide optimization initiatives.")
        else
            println(io, "❌ Slow import times detected. Immediate attention recommended for user experience.")
        end
        
        println(io)
        println(io, "### Action Items")
        println(io, "1. **Priority**: Focus on packages with >5s import time")
        
        if !isempty(dependency_stats)
            worst_dep = dependency_stats[1][1]
            println(io, "2. **Dependency Review**: Investigate organization's usage of '$worst_dep' and similar slow dependencies")
        end
        
        println(io, "3. **Best Practices**: Share optimization techniques from fast-loading packages")
        println(io, "4. **Monitoring**: Set up CI checks to prevent import time regressions")
        println(io, "5. **User Experience**: Consider lazy loading for packages with >3s import time")
        println(io)
        
        println(io, "## Detailed Results")
        for (repo, report) in sort(collect(results), by=x -> x[2].total_import_time, rev=true)
            println(io, "### $repo")
            status = report.total_import_time >= 0 ? "✅ Success" : "❌ Failed"
            println(io, "- **Status**: $status")
            if report.total_import_time >= 0
                println(io, "- **Import Time**: $(round(report.total_import_time, digits=2))s")
                println(io, "- **Package**: $(report.package_name)")
                if !isempty(report.major_contributors)
                    slowest_dep = report.major_contributors[1]
                    if !slowest_dep.is_local
                        println(io, "- **Slowest Dependency**: $(slowest_dep.package_name) ($(round(slowest_dep.total_time, digits=2))s)")
                    end
                end
            end
            println(io, "- **Summary**: $(report.summary)")
            println(io)
        end
    end
    
    @info "Organization import timing summary saved to: $summary_file"
    return summary_file
end