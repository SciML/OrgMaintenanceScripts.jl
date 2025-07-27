using Pkg
using TOML
using HTTP
using JSON3

"""
    VersionCheck

Represents a VERSION check found in code.
"""
struct VersionCheck
    file_path::String
    line_number::Int
    line_content::String
    version::VersionNumber
    operator::String  # >=, >, ==, <, <=
end

"""
    parse_version_check(line::String) -> Union{Nothing, Tuple{VersionNumber, String}}

Parse a line to extract VERSION comparison information.
Returns (version, operator) or nothing if no valid VERSION check found.
"""
function parse_version_check(line::String)
    # Match patterns like: if VERSION >= v"1.6", VERSION > v"1.10.0", etc.
    # Also handle @static if VERSION >= v"1.6"
    patterns = [
        r"VERSION\s*([><=]+)\s*v\"([0-9]+(?:\.[0-9]+)*)\""i,
        r"VERSION\s*([><=]+)\s*v([0-9]+(?:\.[0-9]+)*)"i,
        r"VERSION\s*([><=]+)\s*VersionNumber\(\"([0-9]+(?:\.[0-9]+)*)\"\)"i
    ]
    
    for pattern in patterns
        m = match(pattern, line)
        if !isnothing(m)
            operator = m.captures[1]
            version_str = m.captures[2]
            try
                version = VersionNumber(version_str)
                return (version, operator)
            catch
                # Invalid version string
                continue
            end
        end
    end
    
    return nothing
end

"""
    find_version_checks_in_file(file_path::String; min_version::VersionNumber=v"1.10")

Find all VERSION checks in a file that compare against versions older than min_version.
"""
function find_version_checks_in_file(file_path::String; min_version::VersionNumber=v"1.10")
    checks = VersionCheck[]
    
    if !isfile(file_path) || !endswith(file_path, ".jl")
        return checks
    end
    
    try
        lines = readlines(file_path)
        for (line_num, line) in enumerate(lines)
            result = parse_version_check(line)
            if !isnothing(result)
                version, operator = result
                # Check if this version check is for an old version
                if operator in [">=", ">"] && version < min_version
                    push!(checks, VersionCheck(file_path, line_num, strip(line), version, operator))
                elseif operator == "==" && version < min_version
                    push!(checks, VersionCheck(file_path, line_num, strip(line), version, operator))
                end
            end
        end
    catch e
        @warn "Error reading file $file_path: $e"
    end
    
    return checks
end

"""
    find_version_checks_in_repo(repo_path::String; min_version::VersionNumber=v"1.10", include_subpackages::Bool=true)

Find all VERSION checks in a repository that compare against versions older than min_version.
Now includes support for searching in /lib subdirectories when include_subpackages is true.
Returns a Dict mapping file paths to arrays of VersionCheck objects.
"""
function find_version_checks_in_repo(repo_path::String; min_version::VersionNumber=v"1.10", include_subpackages::Bool=true)
    all_checks = Dict{String, Vector{VersionCheck}}()
    
    if !isdir(repo_path)
        @error "Repository path does not exist: $repo_path"
        return all_checks
    end
    
    # Find all Julia files
    for (root, dirs, files) in walkdir(repo_path)
        # Skip hidden directories and common non-source directories
        filter!(d -> !startswith(d, ".") && d ∉ ["node_modules", "vendor", "build", "dist"], dirs)
        
        # Skip lib directory if not including subpackages
        if !include_subpackages
            filter!(d -> d != "lib", dirs)
        end
        
        for file in files
            if endswith(file, ".jl")
                file_path = joinpath(root, file)
                
                # Skip files in lib if not including subpackages
                if !include_subpackages && is_subpackage(file_path, repo_path)
                    continue
                end
                
                checks = find_version_checks_in_file(file_path; min_version)
                if !isempty(checks)
                    # Store relative path for better readability
                    rel_path = relpath(file_path, repo_path)
                    all_checks[rel_path] = checks
                end
            end
        end
    end
    
    return all_checks
end

"""
    find_version_checks_in_org(org::String; 
                              min_version::VersionNumber=v"1.10",
                              auth_token::String="",
                              work_dir::String=mktempdir(),
                              max_repos::Union{Nothing,Int}=nothing,
                              include_subpackages::Bool=true)

Find all VERSION checks across all repositories in a GitHub organization.
Returns a Dict mapping repository names to their version check results.

# Arguments
- `org`: GitHub organization name
- `min_version`: Minimum Julia version to check against (default: v"1.10" - current LTS)
- `auth_token`: GitHub auth token for API access
- `work_dir`: Temporary directory for cloning repos
- `max_repos`: Maximum number of repositories to process (for testing)
- `include_subpackages`: Whether to include subpackages in /lib directories
"""
function find_version_checks_in_org(org::String; 
                                   min_version::VersionNumber=v"1.10",
                                   auth_token::String="",
                                   work_dir::String=mktempdir(),
                                   max_repos::Union{Nothing,Int}=nothing,
                                   include_subpackages::Bool=true)
    
    @info "Fetching repositories for organization: $org"
    repos = get_org_repos(org; auth_token)
    
    if isempty(repos)
        @warn "No repositories found for organization: $org"
        return Dict{String, Any}()
    end
    
    # Limit repos if specified
    if !isnothing(max_repos) && length(repos) > max_repos
        repos = repos[1:max_repos]
        @info "Processing first $max_repos repositories"
    else
        @info "Found $(length(repos)) repositories"
    end
    
    results = Dict{String, Any}()
    
    for (idx, repo_name) in enumerate(repos)
        @info "Processing repository $idx/$(length(repos)): $repo_name"
        
        # Clone repository
        repo_dir = joinpath(work_dir, basename(repo_name))
        repo_url = "https://github.com/$repo_name.git"
        
        try
            # Clone with minimal depth
            run(`git clone --depth 1 --quiet $repo_url $repo_dir`)
            
            # Check if it's a Julia package
            if !isfile(joinpath(repo_dir, "Project.toml"))
                @debug "Skipping $repo_name - no Project.toml found"
                continue
            end
            
            # Find version checks
            checks = find_version_checks_in_repo(repo_dir; min_version, include_subpackages)
            
            if !isempty(checks)
                results[repo_name] = checks
                total_checks = sum(length(v) for v in values(checks))
                @info "Found $total_checks version checks in $repo_name"
            end
            
        catch e
            @error "Failed to process $repo_name" exception=(e, catch_backtrace())
            results[repo_name] = Dict("error" => string(e))
        finally
            # Clean up
            rm(repo_dir; force=true, recursive=true)
        end
    end
    
    return results
end

"""
    print_version_check_summary(results::Dict; io::IO=stdout)

Print a formatted summary of version check findings.
"""
function print_version_check_summary(results::Dict; io::IO=stdout)
    if isempty(results)
        println(io, "No old version checks found.")
        return
    end
    
    println(io, "\n=== Old Version Checks Summary ===\n")
    
    total_repos = 0
    total_files = 0
    total_checks = 0
    
    # Sort only by keys (repo names) to avoid comparing different value types
    sorted_repos = sort(collect(keys(results)))
    
    for repo_name in sorted_repos
        repo_results = results[repo_name]
        
        # Handle error case
        if isa(repo_results, Dict) && haskey(repo_results, "error")
            println(io, "❌ $repo_name: $(repo_results["error"])")
            continue
        end
        
        repo_total_checks = sum(length(v) for v in values(repo_results))
        if repo_total_checks > 0
            total_repos += 1
            total_files += length(repo_results)
            total_checks += repo_total_checks
            
            println(io, "📦 $repo_name ($repo_total_checks checks in $(length(repo_results)) files)")
            
            for (file_path, checks) in sort(collect(repo_results), by=first)
                println(io, "  📄 $file_path")
                for check in checks
                    println(io, "    Line $check.line_number: $check.line_content")
                    println(io, "      → Checking for VERSION $check.operator v\"$check.version\"")
                end
            end
            println(io)
        end
    end
    
    println(io, "\n=== Summary Statistics ===")
    println(io, "Total repositories with old checks: $total_repos")
    println(io, "Total files with old checks: $total_files")
    println(io, "Total old version checks: $total_checks")
end

# get_org_repos is already defined in the main module, so we don't need to redefine it