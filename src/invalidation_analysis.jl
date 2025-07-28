using Dates
using LibGit2
using Distributed
using HTTP
using JSON3

struct InvalidationEntry
    method::String
    file::String
    line::Int
    package::String
    reason::String
    children_count::Int
    depth::Int
end

struct InvalidationReport
    repo::String
    total_invalidations::Int
    major_invalidators::Vector{InvalidationEntry}
    packages_affected::Vector{String}
    analysis_time::DateTime
    summary::String
    recommendations::Vector{String}
end

"""
    analyze_invalidations_in_process(repo_path::String, test_script::String="")

Run invalidation analysis in a separate Julia process to avoid contaminating the current session.
Returns invalidation data that can be analyzed to find major invalidators.
"""
function analyze_invalidations_in_process(repo_path::String, test_script::String="")
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end
    
    # Create a temporary script to run the invalidation analysis
    analysis_script = joinpath(tempdir(), "invalidation_analysis_$(randstring(8)).jl")
    
    # Default test script that loads the package and runs basic operations
    default_test = """
        using Pkg
        Pkg.activate(".")
        Pkg.instantiate()
        
        # Try to load the main package
        project = Pkg.TOML.parsefile("Project.toml")
        if haskey(project, "name")
            pkg_name = project["name"]
            try
                @eval using \$(Symbol(pkg_name))
                println("Successfully loaded \$pkg_name")
            catch e
                println("Failed to load \$pkg_name: \$e")
            end
        end
        
        # Run any additional user tests
        if isfile("test/runtests.jl")
            try
                include("test/runtests.jl")
            catch e
                println("Test execution failed: \$e")
            end
        end
    """
    
    test_code = isempty(test_script) ? default_test : test_script
    
    write(analysis_script, """
        using SnoopCompileCore
        import SnoopCompileCore: InferenceTimingNode, InfTiming
        
        # Change to repository directory
        cd("$repo_path")
        
        println("Starting invalidation analysis for: $repo_path")
        
        # Start monitoring invalidations
        invalidations = @snoopr begin
            $test_code
        end
        
        println("Captured \$(length(invalidations)) invalidations")
        
        # Analyze invalidation tree
        trees = invalidation_trees(invalidations)
        
        # Extract detailed information about each invalidation
        invalidation_data = []
        
        function extract_invalidation_info(node, depth=0)
            for child in node.children
                method_info = string(child.method)
                
                # Extract file and line information if available
                file = "unknown"
                line = 0
                package = "unknown"
                
                try
                    if hasfield(typeof(child.method), :file) && hasfield(typeof(child.method), :line)
                        file = string(child.method.file)
                        line = child.method.line
                        
                        # Try to determine package from file path
                        if contains(file, ".julia/packages/")
                            pkg_match = match(r"\\.julia/packages/([^/]+)", file)
                            if pkg_match !== nothing
                                package = pkg_match.captures[1]
                            end
                        elseif contains(file, "src/")
                            # Local package
                            package = "local"
                        end
                    end
                catch e
                    # Fallback if we can't extract file info
                end
                
                children_count = length(child.children)
                
                push!(invalidation_data, Dict(
                    "method" => method_info,
                    "file" => file,
                    "line" => line,
                    "package" => package,
                    "children_count" => children_count,
                    "depth" => depth
                ))
                
                # Recursively process children
                extract_invalidation_info(child, depth + 1)
            end
        end
        
        for tree in trees
            extract_invalidation_info(tree)
        end
        
        # Save results as JSON
        results = Dict(
            "total_invalidations" => length(invalidations),
            "tree_count" => length(trees),
            "invalidation_details" => invalidation_data
        )
        
        # Output JSON directly to stdout for the main process to capture
        println("===JSON_START===")
        JSON3.pretty(stdout, results)
        println("\n===JSON_END===")
    """)
    
    # Run the analysis in a separate process
    try
        @info "Running invalidation analysis in separate process..."
        result = read(`julia --project=$repo_path $analysis_script`, String)
        
        # Extract JSON from output
        json_start = findfirst("===JSON_START===", result)
        json_end = findfirst("===JSON_END===", result)
        
        if isnothing(json_start) || isnothing(json_end)
            error("Could not find JSON output markers in result")
        end
        
        # Extract just the JSON portion
        json_str = result[last(json_start)+1:first(json_end)-1]
        
        # Parse JSON directly
        results = JSON3.read(json_str)
        
        # Clean up temporary files
        rm(analysis_script; force=true)
        
        return results
        
    catch e
        # Clean up on error
        rm(analysis_script; force=true)
        rethrow(e)
    end
end

"""
    analyze_major_invalidators(invalidation_data::Dict)

Analyze invalidation data to identify the major invalidators.
Returns a list of the most problematic invalidations.
"""
function analyze_major_invalidators(invalidation_data::Dict)
    invalidations = invalidation_data["invalidation_details"]
    
    # Sort by children count (invalidations that trigger many others are worse)
    sorted_by_impact = sort(invalidations, by=x -> x["children_count"], rev=true)
    
    # Group by package to identify problematic packages
    package_stats = Dict{String, Dict{String, Any}}()
    for inv in invalidations
        pkg = inv["package"]
        if !haskey(package_stats, pkg)
            package_stats[pkg] = Dict(
                "count" => 0,
                "total_children" => 0,
                "max_children" => 0,
                "methods" => Set{String}()
            )
        end
        package_stats[pkg]["count"] += 1
        package_stats[pkg]["total_children"] += inv["children_count"]
        package_stats[pkg]["max_children"] = max(package_stats[pkg]["max_children"], inv["children_count"])
        push!(package_stats[pkg]["methods"], inv["method"])
    end
    
    # Convert to vector and sort by impact
    package_impact = [(pkg, stats["total_children"], stats["count"]) 
                     for (pkg, stats) in package_stats]
    sort!(package_impact, by=x -> x[2], rev=true)
    
    major_invalidators = []
    for inv in sorted_by_impact[1:min(20, end)]  # Top 20 invalidators
        push!(major_invalidators, InvalidationEntry(
            inv["method"],
            inv["file"],
            inv["line"],
            inv["package"],
            "High-impact invalidation ($(inv["children_count"]) children)",
            inv["children_count"],
            inv["depth"]
        ))
    end
    
    return major_invalidators, package_impact
end

"""
    generate_invalidation_report(repo_path::String, test_script::String="")

Generate a comprehensive invalidation report for a repository.
"""
function generate_invalidation_report(repo_path::String, test_script::String="")
    @info "Analyzing invalidations for: $repo_path"
    
    start_time = now()
    
    try
        # Run invalidation analysis
        invalidation_data = analyze_invalidations_in_process(repo_path, test_script)
        
        # Analyze the results
        major_invalidators, package_impact = analyze_major_invalidators(invalidation_data)
        
        # Extract package names
        packages_affected = [pkg for (pkg, _, _) in package_impact]
        
        # Generate summary
        total_invalidations = invalidation_data["total_invalidations"]
        summary = if total_invalidations == 0
            "✅ No invalidations detected - excellent!"
        elseif total_invalidations < 10
            "✅ Low invalidation count ($total_invalidations) - good performance"
        elseif total_invalidations < 50
            "⚠️  Moderate invalidation count ($total_invalidations) - room for improvement"
        else
            "❌ High invalidation count ($total_invalidations) - significant performance impact"
        end
        
        # Generate recommendations
        recommendations = String[]
        
        if total_invalidations > 0
            # Top problematic packages
            if length(package_impact) > 0
                top_pkg, top_impact, top_count = package_impact[1]
                if top_impact > 10
                    push!(recommendations, "Focus on package '$top_pkg' - it causes $top_impact invalidations ($top_count instances)")
                end
            end
            
            # Type stability recommendations
            if any(inv -> inv.children_count > 5, major_invalidators)
                push!(recommendations, "Consider improving type stability in methods with high invalidation counts")
            end
            
            # Dependency recommendations
            if length(packages_affected) > 5
                push!(recommendations, "Review dependencies - $(length(packages_affected)) packages are involved in invalidations")
            end
            
            # General recommendations
            push!(recommendations, "Run `@time_imports using YourPackage` to identify slow-loading dependencies")
            push!(recommendations, "Consider using `@nospecialize` for arguments that don't need to be specialized")
            push!(recommendations, "Profile with `@profile` to identify performance bottlenecks")
        else
            push!(recommendations, "Great job! No invalidations detected. Your package is well-optimized.")
        end
        
        return InvalidationReport(
            basename(repo_path),
            total_invalidations,
            major_invalidators,
            packages_affected,
            start_time,
            summary,
            recommendations
        )
        
    catch e
        @error "Failed to analyze invalidations for $repo_path" exception=(e, catch_backtrace())
        return InvalidationReport(
            basename(repo_path),
            -1,  # Indicates error
            InvalidationEntry[],
            String[],
            start_time,
            "❌ Analysis failed: $(string(e))",
            ["Check that the repository has a valid Project.toml and can be loaded successfully"]
        )
    end
end

"""
    analyze_repo_invalidations(repo_path::String; test_script::String="", output_file::String="")

Analyze invalidations in a single repository and optionally save a report.
"""
function analyze_repo_invalidations(repo_path::String; test_script::String="", output_file::String="")
    report = generate_invalidation_report(repo_path, test_script)
    
    # Print summary to console
    println("\\n" * "="^60)
    println("INVALIDATION ANALYSIS REPORT")
    println("Repository: $(report.repo)")
    println("Analysis Time: $(report.analysis_time)")
    println("="^60)
    println(report.summary)
    println("\\nTotal Invalidations: $(report.total_invalidations)")
    
    if report.total_invalidations > 0
        println("\\nPackages Affected: $(length(report.packages_affected))")
        if !isempty(report.packages_affected)
            for (i, pkg) in enumerate(report.packages_affected[1:min(10, end)])
                println("  $i. $pkg")
            end
        end
        
        println("\\nTop Invalidators:")
        for (i, inv) in enumerate(report.major_invalidators[1:min(10, end)])
            println("  $i. $(inv.method)")
            println("     File: $(inv.file):$(inv.line)")
            println("     Package: $(inv.package)")
            println("     Impact: $(inv.children_count) children")
            println()
        end
    end
    
    println("\\nRecommendations:")
    for (i, rec) in enumerate(report.recommendations)
        println("  $i. $rec")
    end
    println("="^60)
    
    # Save detailed report if requested
    if !isempty(output_file)
        write_invalidation_report(report, output_file)
        @info "Detailed report saved to: $output_file"
    end
    
    return report
end

"""
    analyze_org_invalidations(org::String; auth_token::String="", work_dir::String=mktempdir(), 
                             test_script::String="", output_dir::String="", max_repos::Int=0)

Analyze invalidations across all repositories in a GitHub organization.
"""
function analyze_org_invalidations(org::String; 
                                 auth_token::String="",
                                 work_dir::String=mktempdir(),
                                 test_script::String="",
                                 output_dir::String="",
                                 max_repos::Int=0)
    
    @info "Analyzing invalidations for organization: $org"
    
    # Get all repositories
    repos = OrgMaintenanceScripts.get_org_repos(org; auth_token)
    
    if isempty(repos)
        @warn "No repositories found for organization: $org"
        return Dict{String, InvalidationReport}()
    end
    
    if max_repos > 0
        repos = repos[1:min(max_repos, end)]
    end
    
    @info "Found $(length(repos)) repositories to analyze"
    
    results = Dict{String, InvalidationReport}()
    
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
            
            # Analyze invalidations
            report = generate_invalidation_report(repo_dir, test_script)
            results[repo_name] = report
            
            # Save individual report if output directory specified
            if !isempty(output_dir)
                mkpath(output_dir)
                repo_report_file = joinpath(output_dir, "$(basename(repo_name))_invalidations.json")
                write_invalidation_report(report, repo_report_file)
            end
            
        catch e
            @error "Failed to process $repo_name" exception=(e, catch_backtrace())
            results[repo_name] = InvalidationReport(
                repo_name,
                -1,
                InvalidationEntry[],
                String[],
                now(),
                "❌ Analysis failed: $(string(e))",
                ["Repository could not be cloned or analyzed"]
            )
        finally
            # Clean up
            rm(repo_dir; force=true, recursive=true)
        end
    end
    
    # Generate organization summary report
    generate_org_summary_report(org, results, output_dir)
    
    return results
end

"""
    write_invalidation_report(report::InvalidationReport, output_file::String)

Write a detailed invalidation report to a JSON file.
"""
function write_invalidation_report(report::InvalidationReport, output_file::String)
    report_data = Dict(
        "repository" => report.repo,
        "analysis_time" => string(report.analysis_time),
        "total_invalidations" => report.total_invalidations,
        "summary" => report.summary,
        "packages_affected" => report.packages_affected,
        "recommendations" => report.recommendations,
        "major_invalidators" => [
            Dict(
                "method" => inv.method,
                "file" => inv.file,
                "line" => inv.line,
                "package" => inv.package,
                "reason" => inv.reason,
                "children_count" => inv.children_count,
                "depth" => inv.depth
            ) for inv in report.major_invalidators
        ]
    )
    
    open(output_file, "w") do io
        JSON3.pretty(io, report_data)
    end
end

"""
    generate_org_summary_report(org::String, results::Dict{String, InvalidationReport}, output_dir::String)

Generate a summary report for the entire organization.
"""
function generate_org_summary_report(org::String, results::Dict{String, InvalidationReport}, output_dir::String)
    if isempty(output_dir)
        output_dir = tempdir()
    end
    
    # Calculate summary statistics
    total_repos = length(results)
    successful_analyses = count(r -> r.total_invalidations >= 0, values(results))
    failed_analyses = total_repos - successful_analyses
    
    total_invalidations = sum(r.total_invalidations for r in values(results) if r.total_invalidations >= 0)
    avg_invalidations = successful_analyses > 0 ? total_invalidations / successful_analyses : 0
    
    # Find worst repositories
    worst_repos = sort([(name, report.total_invalidations) for (name, report) in results if report.total_invalidations > 0], 
                      by=x -> x[2], rev=true)
    
    # Aggregate package problems
    all_packages = Set{String}()
    for report in values(results)
        if report.total_invalidations >= 0
            union!(all_packages, report.packages_affected)
        end
    end
    
    # Generate markdown report
    summary_file = joinpath(output_dir, "$(org)_invalidation_summary.md")
    open(summary_file, "w") do io
        println(io, "# Invalidation Analysis Report for $org")
        println(io, "Generated on: $(now())")
        println(io)
        
        println(io, "## Summary")
        println(io, "- **Total Repositories Analyzed**: $total_repos")
        println(io, "- **Successful Analyses**: $successful_analyses")
        println(io, "- **Failed Analyses**: $failed_analyses")
        println(io, "- **Total Invalidations Found**: $total_invalidations")
        println(io, "- **Average Invalidations per Repo**: $(round(avg_invalidations, digits=1))")
        println(io, "- **Unique Packages Involved**: $(length(all_packages))")
        println(io)
        
        if !isempty(worst_repos)
            println(io, "## Repositories with Most Invalidations")
            for (i, (repo, count)) in enumerate(worst_repos[1:min(10, end)])
                println(io, "$i. **$repo**: $count invalidations")
            end
            println(io)
        end
        
        println(io, "## Recommendations for $org")
        
        if total_invalidations == 0
            println(io, "🎉 Excellent! No invalidations detected across the organization.")
        elseif avg_invalidations < 5
            println(io, "✅ Good performance overall. Focus on the worst repositories for further improvements.")
        elseif avg_invalidations < 20
            println(io, "⚠️ Moderate invalidation levels. Consider organization-wide performance initiatives.")
        else
            println(io, "❌ High invalidation levels detected. Immediate attention recommended.")
        end
        
        println(io)
        println(io, "### Action Items")
        println(io, "1. Focus on repositories with >20 invalidations")
        packages_list = join(collect(all_packages)[1:min(10, end)], ", ")
        println(io, "2. Review common problematic packages: $packages_list")
        println(io, "3. Consider creating organization-wide coding guidelines for type stability")
        println(io, "4. Set up CI checks for invalidation regression testing")
        println(io)
        
        println(io, "## Detailed Results")
        for (repo, report) in sort(collect(results), by=x -> x[2].total_invalidations, rev=true)
            println(io, "### $repo")
            status = report.total_invalidations >= 0 ? "✅ Success" : "❌ Failed"
            println(io, "- **Status**: $status")
            if report.total_invalidations >= 0
                println(io, "- **Invalidations**: $(report.total_invalidations)")
                println(io, "- **Packages Affected**: $(length(report.packages_affected))")
            end
            println(io, "- **Summary**: $(report.summary)")
            println(io)
        end
    end
    
    @info "Organization summary report saved to: $summary_file"
    return summary_file
end