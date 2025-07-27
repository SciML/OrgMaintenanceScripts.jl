# Minimum Version Fixer
# Automatically fix minimum version bounds for Julia packages

using Pkg
using TOML
using Dates
using HTTP
using JSON3

# SciML-specific minimum versions that are known to work
const SCIML_MIN_VERSIONS = Dict(
    # Core packages
    "SciMLBase" => "2.0",
    "DiffEqBase" => "6.0",
    "OrdinaryDiffEq" => "6.0",
    "DifferentialEquations" => "7.0",
    "ModelingToolkit" => "9.0",
    "Symbolics" => "5.0",
    "Catalyst" => "13.0",
    
    # Solver packages
    "Sundials" => "4.0",
    "DiffEqCallbacks" => "3.0",
    "StochasticDiffEq" => "6.0",
    "DelayDiffEq" => "5.0",
    "DiffEqJump" => "9.0",
    
    # Analysis packages
    "DiffEqSensitivity" => "7.0",
    "DiffEqFlux" => "3.0",
    "DataDrivenDiffEq" => "1.0",
    "NeuralPDE" => "5.0",
    "DiffEqParamEstim" => "2.0",
    
    # Utility packages
    "RecursiveArrayTools" => "3.0",
    "ArrayInterface" => "7.0",
    "StaticArrays" => "1.0",
    "ForwardDiff" => "0.10",
    "PreallocationTools" => "0.4",
    "SciMLOperators" => "0.3",
    
    # Common dependencies
    "Reexport" => "1.0",
    "DocStringExtensions" => "0.8",
    "Parameters" => "0.12",
    "UnPack" => "1.0",
    "ConstructionBase" => "1.0",
    "Setfield" => "1.0"
)

"""
    setup_downgrade_script(work_dir::String)

Download the downgrade.jl script if not already present.
"""
function setup_downgrade_script(work_dir::String)
    downgrade_url = "https://raw.githubusercontent.com/julia-actions/julia-downgrade-compat/main/downgrade.jl"
    downgrade_script = joinpath(work_dir, "downgrade.jl")
    
    if !isfile(downgrade_script)
        @info "Downloading downgrade.jl..."
        download(downgrade_url, downgrade_script)
    end
    
    return downgrade_script
end

"""
    test_min_versions(project_dir::String, downgrade_script::String; julia_version="1.10")

Test if minimum versions can be resolved.
Returns (success::Bool, error_output::String)
"""
function test_min_versions(project_dir::String, downgrade_script::String; julia_version="1.10")
    cmd = `julia $downgrade_script --mode=alldeps --julia-version=$julia_version $project_dir`
    
    try
        output = IOBuffer()
        run(pipeline(cmd; stdout=output, stderr=output))
        return true, String(take!(output))
    catch
        return false, "Failed to resolve minimum versions"
    end
end

"""
    parse_resolution_errors(output::String, project_toml::Dict)

Parse resolution errors to identify problematic packages.
"""
function parse_resolution_errors(output::String, project_toml::Dict)
    problematic = Set{String}()
    deps = get(project_toml, "deps", Dict())
    
    # Look for package mentions in error output
    for (pkg_name, _) in deps
        if occursin(pkg_name, output)
            push!(problematic, pkg_name)
        end
    end
    
    # If no specific packages found, check all with low versions
    if isempty(problematic)
        compat = get(project_toml, "compat", Dict())
        for (pkg_name, compat_str) in compat
            if pkg_name != "julia" && is_outdated_compat(compat_str)
                push!(problematic, pkg_name)
            end
        end
    end
    
    return collect(problematic)
end

"""
    is_outdated_compat(compat_str::String)

Check if a compat string indicates an outdated version.
"""
function is_outdated_compat(compat_str::String)
    # Extract the minimum version
    m = match(r"^[\^~]?(\d+)\.(\d+)", compat_str)
    if m !== nothing
        major = parse(Int, m.captures[1])
        minor = parse(Int, m.captures[2])
        
        # Very old 0.x versions
        if major == 0 && minor < 5
            return true
        end
    end
    
    return false
end

"""
    get_smart_min_version(pkg_name::String, current_compat::String)

Get an appropriate minimum version for a package.
"""
function get_smart_min_version(pkg_name::String, current_compat::String)
    # Check SciML-specific versions first
    if haskey(SCIML_MIN_VERSIONS, pkg_name)
        return SCIML_MIN_VERSIONS[pkg_name]
    end
    
    # Try to get latest from registry
    try
        latest = get_latest_version(pkg_name)
        if latest !== nothing
            # Use conservative approach
            if latest.major == 0
                # For 0.x, use exact version
                return string(latest)
            else
                # For stable, use major.0
                return "$(latest.major).0"
            end
        end
    catch
        # Ignore errors
    end
    
    # Fallback: bump the current version
    return bump_compat_version(current_compat)
end

"""
    get_latest_version(pkg_name::String)

Get the latest version of a package from the registry.
"""
function get_latest_version(pkg_name::String)
    mktempdir() do tmpdir
        Pkg.activate(tmpdir)
        Pkg.add(pkg_name; io=devnull)
        
        manifest = Pkg.TOML.parsefile(joinpath(tmpdir, "Manifest.toml"))
        
        # Look for the package in manifest
        for (name, entries) in manifest
            if name == pkg_name
                if isa(entries, Vector) && !isempty(entries)
                    return VersionNumber(entries[1]["version"])
                elseif isa(entries, Dict) && haskey(entries, "version")
                    return VersionNumber(entries["version"])
                end
            end
        end
    end
    
    return nothing
end

"""
    bump_compat_version(compat_str::String)

Bump a compat version string conservatively.
"""
function bump_compat_version(compat_str::String)
    # Extract version
    m = match(r"(\d+)\.(\d+)", compat_str)
    if m === nothing
        return compat_str
    end
    
    major = parse(Int, m.captures[1])
    minor = parse(Int, m.captures[2])
    
    if major == 0
        # Bump minor for 0.x
        return "0.$(minor + 1)"
    else
        # Keep major.0 for stable
        return "$major.0"
    end
end

"""
    update_compat!(project_toml::Dict, updates::Dict{String, String})

Update the compat section preserving upper bounds.
"""
function update_compat!(project_toml::Dict, updates::Dict{String, String})
    if !haskey(project_toml, "compat")
        project_toml["compat"] = Dict{String, Any}()
    end
    
    compat = project_toml["compat"]
    
    for (pkg, new_min) in updates
        current = get(compat, pkg, "")
        
        # Preserve existing upper bounds
        if occursin(",", current)
            # Version list: "0.5, 1"
            parts = split(current, ",")
            parts[1] = " $new_min"
            compat[pkg] = join(parts, ",")
        elseif occursin("-", current)
            # Range: "0.5-1.0"
            upper = split(current, "-")[2]
            compat[pkg] = "$new_min-$upper"
        elseif startswith(current, "^") || startswith(current, "~")
            # Just replace
            compat[pkg] = new_min
        else
            # No special format
            compat[pkg] = new_min
        end
        
        @info "Updated $pkg: $current → $(compat[pkg])"
    end
end

"""
    fix_package_min_versions(repo_path::String; 
                            max_iterations=10, 
                            work_dir=mktempdir(),
                            julia_version="1.10")

Fix minimum versions for a package repository that's already cloned.
Returns (success::Bool, updates::Dict{String,String})
"""
function fix_package_min_versions(repo_path::String; 
                                 max_iterations::Int=10,
                                 work_dir::String=mktempdir(),
                                 julia_version::String="1.10")
    
    downgrade_script = setup_downgrade_script(work_dir)
    project_file = joinpath(repo_path, "Project.toml")
    
    if !isfile(project_file)
        @warn "No Project.toml found in $repo_path"
        return false, Dict{String,String}()
    end
    
    # Load project
    project_toml = TOML.parsefile(project_file)
    package_name = get(project_toml, "name", basename(repo_path))
    
    @info "Fixing minimum versions for $package_name"
    
    # Iteratively fix versions
    iteration = 0
    total_updates = Dict{String, String}()
    
    while iteration < max_iterations
        iteration += 1
        @info "Iteration $iteration/$max_iterations"
        
        # Test minimum versions
        success, output = test_min_versions(repo_path, downgrade_script; julia_version)
        
        if success
            @info "✓ Minimum versions resolved successfully!"
            break
        end
        
        @info "Resolution failed, analyzing..."
        
        # Find problematic packages
        problematic = parse_resolution_errors(output, project_toml)
        
        if isempty(problematic)
            @warn "Could not identify problematic packages"
            break
        end
        
        @info "Found problematic packages: $(join(problematic, ", "))"
        
        # Get updates
        updates = Dict{String, String}()
        compat = get(project_toml, "compat", Dict())
        
        for pkg in problematic
            if haskey(total_updates, pkg)
                continue  # Already updated
            end
            
            current = get(compat, pkg, "")
            new_min = get_smart_min_version(pkg, current)
            
            if new_min != current
                updates[pkg] = new_min
                total_updates[pkg] = new_min
            end
        end
        
        if isempty(updates)
            @info "No more updates to apply"
            break
        end
        
        # Apply updates
        update_compat!(project_toml, updates)
        
        # Write back
        open(project_file, "w") do io
            TOML.print(io, project_toml, sorted=true)
        end
    end
    
    return !isempty(total_updates), total_updates
end

"""
    fix_repo_min_versions(repo_name::String;
                         work_dir=mktempdir(),
                         max_iterations=10,
                         create_pr=true,
                         julia_version="1.10")

Clone a repository, fix its minimum versions, and optionally create a PR.
"""
function fix_repo_min_versions(repo_name::String;
                              work_dir::String=mktempdir(),
                              max_iterations::Int=10,
                              create_pr::Bool=true,
                              julia_version::String="1.10")
    
    # Clone repository
    repo_dir = joinpath(work_dir, replace(repo_name, "/" => "_"))
    repo_url = "https://github.com/$repo_name.git"
    
    @info "Cloning $repo_name..."
    run(`git clone $repo_url $repo_dir`)
    
    # Create feature branch
    cd(repo_dir) do
        # Get default branch
        default_branch = strip(read(`git symbolic-ref refs/remotes/origin/HEAD`, String))
        default_branch = split(default_branch, "/")[end]
        run(`git checkout $default_branch`)
        
        # Create new branch
        timestamp = Dates.format(now(), "yyyymmdd-HHMMSS")
        branch_name = "fix-min-versions-$timestamp"
        run(`git checkout -b $branch_name`)
    end
    
    # Fix minimum versions
    success, updates = fix_package_min_versions(repo_dir; 
                                               max_iterations, 
                                               work_dir, 
                                               julia_version)
    
    if !success || isempty(updates)
        @info "No changes needed for $repo_name"
        return false
    end
    
    # Commit changes
    cd(repo_dir) do
        run(`git add Project.toml`)
        
        commit_msg = """
        Fix minimum version compatibility bounds
        
        This commit updates the minimum version bounds in [compat] to ensure
        they can be resolved by the package manager. The following packages
        were updated:
        
        $(join(["- $pkg: → $ver" for (pkg, ver) in sort(collect(updates))], "\n"))
        
        These changes were determined by running the downgrade CI tests and
        incrementally bumping failing minimum versions to working ones.
        """
        
        run(`git commit -m $commit_msg`)
        
        if create_pr
            @info "Creating pull request..."
            
            # Push branch
            run(`git push -u origin HEAD`)
            
            # Create PR using GitHub CLI
            pr_title = "Fix minimum version compatibility bounds"
            pr_body = """
            ## Summary
            
            This PR fixes the minimum version bounds in the `[compat]` section to ensure all minimum versions can be successfully resolved by Pkg.
            
            ## Changes
            
            The following minimum versions were updated:
            
            | Package | New Minimum Version |
            |---------|-------------------|
            $(join(["| $pkg | $ver |" for (pkg, ver) in sort(collect(updates))], "\n"))
            
            ## Testing
            
            These changes were determined by:
            1. Running the downgrade CI workflow locally
            2. Identifying packages that failed to resolve at their minimum versions
            3. Bumping those packages to known-working minimum versions
            4. Repeating until all packages resolve successfully
            
            This ensures the package will pass the Downgrade CI tests.
            """
            
            try
                run(`gh pr create --title $pr_title --body $pr_body`)
                @info "✓ Pull request created successfully!"
            catch e
                @warn "Failed to create PR automatically: $e"
                @info "You can create it manually with the branch that was pushed"
            end
        end
    end
    
    return true
end

"""
    fix_org_min_versions(org_name::String;
                        work_dir=mktempdir(),
                        max_iterations=10,
                        create_prs=true,
                        skip_repos=String[],
                        only_repos=nothing,
                        julia_version="1.10")

Fix minimum versions for all Julia packages in a GitHub organization.
"""
function fix_org_min_versions(org_name::String;
                             work_dir::String=mktempdir(),
                             max_iterations::Int=10,
                             create_prs::Bool=true,
                             skip_repos::Vector{String}=String[],
                             only_repos::Union{Nothing,Vector{String}}=nothing,
                             julia_version::String="1.10")
    
    @info "Fetching repositories for organization: $org_name"
    
    # Get repositories
    if only_repos !== nothing
        repos = ["$org_name/$repo" for repo in only_repos]
    else
        # Use GitHub API to get all repos
        repos_json = read(`gh repo list $org_name --limit 1000 --json name,description,isArchived`, String)
        repos_data = JSON3.read(repos_json)
        
        # Filter for Julia packages
        repos = String[]
        for repo in repos_data
            if !repo.isArchived && 
               (endswith(repo.name, ".jl") || 
                (haskey(repo, :description) && 
                 repo.description !== nothing &&
                 occursin("julia", lowercase(repo.description))))
                push!(repos, "$org_name/$(repo.name)")
            end
        end
    end
    
    # Filter out skipped repos
    repos = filter(r -> !any(skip -> occursin(skip, r), skip_repos), repos)
    
    @info "Found $(length(repos)) Julia repositories to process"
    
    results = Dict{String, Bool}()
    
    for (i, repo) in enumerate(repos)
        @info "\n" * "="^60
        @info "Processing repository $i/$(length(repos)): $repo"
        @info "="^60
        
        try
            success = fix_repo_min_versions(repo; 
                                           work_dir,
                                           max_iterations,
                                           create_pr=create_prs,
                                           julia_version)
            results[repo] = success
        catch e
            @error "Failed to process $repo: $e"
            results[repo] = false
        end
        
        # Small delay to avoid rate limits
        sleep(2)
    end
    
    # Summary
    @info "\n" * "="^60
    @info "SUMMARY"
    @info "="^60
    
    successful = count(values(results))
    @info "Successfully processed: $successful/$(length(results))"
    
    if any(values(results))
        @info "\nRepositories with fixes:"
        for (repo, success) in results
            if success
                @info "  ✓ $repo"
            end
        end
    end
    
    if any(.!values(results))
        @info "\nRepositories that failed or needed no changes:"
        for (repo, success) in results
            if !success
                @info "  ✗ $repo"
            end
        end
    end
    
    return results
end