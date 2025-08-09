using Pkg
using TOML
using LibGit2
using HTTP
using JSON3
using LocalRegistry

"""
    bump_minor_version(version_str::String) -> String

Bump the minor version of a semantic version string.
"""
function bump_minor_version(version_str::String)
    parts = split(version_str, '.')
    if length(parts) != 3
        error("Invalid version format: $version_str")
    end
    major = parse(Int, parts[1])
    minor = parse(Int, parts[2])
    return "$major.$(minor + 1).0"
end

"""
    update_project_versions_all(repo_path::String; include_subpackages::Bool=true)

Update the version in all Project.toml files in a repository by bumping the minor version.
Supports repositories with subpackages in /lib directories.
Returns a Dict mapping relative paths to (old_version, new_version) tuples.
"""
function update_project_versions_all(repo_path::String; include_subpackages::Bool = true)
    # Find all Project.toml files
    project_files = find_all_project_tomls(repo_path)

    if isempty(project_files)
        @warn "No Project.toml files found in $repo_path"
        return Dict{String, Tuple{String, String}}()
    end

    if !include_subpackages
        # Filter out subpackages
        project_files = filter(p -> !is_subpackage(p, repo_path), project_files)
    end

    updates = Dict{String, Tuple{String, String}}()

    for project_path in project_files
        rel_path = get_relative_project_path(project_path, repo_path)
        result = update_project_version(project_path)

        if !isnothing(result)
            updates[rel_path] = result
        end
    end

    return updates
end

"""
    update_project_version(project_path::String)

Update the version in a Project.toml file by bumping the minor version.
"""
function update_project_version(project_path::String)
    if !isfile(project_path)
        @warn "Project.toml not found at $project_path"
        return nothing
    end

    project = TOML.parsefile(project_path)
    if !haskey(project, "version")
        @warn "No version field in $project_path"
        return nothing
    end

    old_version = project["version"]
    new_version = bump_minor_version(old_version)
    project["version"] = new_version

    open(project_path, "w") do io
        TOML.print(io, project)
    end

    @info "Updated version in $project_path: $old_version → $new_version"
    return (old_version, new_version)
end

"""
    register_package(package_dir::String; registry="General", push::Bool=false)

Register a Julia package to the specified registry using LocalRegistry.

# Arguments
- `package_dir::String`: Path to the directory containing the package to register
- `registry`: Name or path to the registry (default: "General")
- `push::Bool`: Whether to push the registration to the remote registry (default: false)

# Returns
- `Bool`: `true` if registration succeeded, `false` otherwise

# Examples
```julia
# Register a package to the General registry
register_package("/path/to/MyPackage")

# Register to a custom registry with push
register_package("/path/to/MyPackage"; registry="MyRegistry", push=true)
```
"""
function register_package(package_dir::String; registry = "General", push::Bool = false)
    try
        LocalRegistry.register(package_dir; registry = registry, push = push)
        @info "Successfully registered package at $package_dir"
        return true
    catch e
        if e isa ErrorException
            @error "Failed to register package at $package_dir: $(e.msg)"
        else
            @error "Failed to register package at $package_dir" exception=(e, catch_backtrace())
        end
        return false
    end
end

"""
    bump_and_register_repo(repo_path::String; registry="General", push::Bool=false)

Bump minor versions and register all packages in a repository (monorepo).

This function handles both single-package repositories and monorepos with multiple packages.
It automatically bumps the minor version of all packages found (main package and lib/* subpackages),
then registers them in dependency order using a brute-force approach.

# Arguments
- `repo_path::String`: Path to the repository root directory
- `registry`: Name or path to the registry (default: "General")
- `push::Bool`: Whether to push the registration to the remote registry (default: false)

# Returns
A NamedTuple with:
- `registered::Vector{String}`: Names of successfully registered packages
- `failed::Vector{String}`: Names of packages that failed to register

# Behavior
1. Bumps minor versions of all Project.toml files found
2. Collects all package directories (main + lib/*)
3. Attempts to register packages iteratively until all succeed or no progress
4. Automatically commits version bumps if any packages were processed
5. Handles dependency ordering by retrying failed registrations

# Examples
```julia
# Bump and register all packages in a repository
result = bump_and_register_repo("/path/to/repo")
println("Registered: ", result.registered)
println("Failed: ", result.failed)

# Use custom registry with push
bump_and_register_repo("/path/to/repo"; registry="MyRegistry", push=true)
```
"""
function bump_and_register_repo(repo_path::String; registry = "General", push::Bool = false)
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end

    # First, bump all versions
    @info "Bumping versions for all packages in $repo_path"
    version_updates = update_project_versions_all(repo_path)
    
    if isempty(version_updates)
        @info "No packages found to update"
        return (registered = String[], failed = String[])
    end
    
    # Collect all package directories
    package_dirs = String[]
    
    # Main package
    if isfile(joinpath(repo_path, "Project.toml"))
        push!(package_dirs, repo_path)
    end
    
    # Subpackages in lib/
    lib_dir = joinpath(repo_path, "lib")
    if isdir(lib_dir)
        for subdir in readdir(lib_dir; join = false)
            subdir_path = joinpath(lib_dir, subdir)
            if isdir(subdir_path) && isfile(joinpath(subdir_path, "Project.toml"))
                push!(package_dirs, subdir_path)
            end
        end
    end
    
    # Register packages using brute-force dependency resolution
    registered = Set{String}()
    
    while true
        one_succeed = false
        
        for package_dir in package_dirs
            package_name = basename(package_dir)
            package_name in registered && continue
            
            @info "Trying to register $package_name"
            # We need to register the packages in the correct order so we just brute force try
            # one by one until it succeeds
            try
                LocalRegistry.register(package_dir; registry = registry, push = push)
                push!(registered, package_name)
                one_succeed = true
                @info "Successfully registered $package_name"
            catch e
                if e isa ErrorException
                    # Expected error when dependencies aren't registered yet
                    @debug "Could not register $package_name yet: $(e.msg)"
                else
                    # Unexpected error - log but continue
                    @error "Unexpected error registering $package_name" exception=(e, catch_backtrace())
                end
            end
        end
        
        if !one_succeed
            # No more packages can be registered
            break
        end
    end
    
    # Identify failed packages
    failed_packages = String[]
    for package_dir in package_dirs
        package_name = basename(package_dir)
        if !(package_name in registered)
            push!(failed_packages, package_name)
        end
    end
    
    if !isempty(failed_packages)
        @error "Could not register the following packages: $(join(failed_packages, ", "))"
    end

    # Commit changes if any packages were updated
    if !isempty(registered) || !isempty(failed_packages)
        repo = LibGit2.GitRepo(repo_path)
        try
            LibGit2.add!(repo, ".")
            sig = LibGit2.Signature("OrgMaintenanceScripts", "noreply@sciml.ai")
            msg = "Bump minor versions for registration\n\nPackages: $(join(vcat(collect(registered), failed_packages), ", "))"
            LibGit2.commit(repo, msg; author = sig, committer = sig)
            @info "Committed version bumps"
        finally
            close(repo)
        end
    end

    return (registered = collect(registered), failed = failed_packages)
end

"""
    register_monorepo_packages(repo_path::String; registry="General", push::Bool=false)

Register all packages in a monorepo without bumping versions.

This function is similar to `bump_and_register_repo` but only performs registration
without modifying package versions. Useful when versions have already been bumped
or when you want to register packages at their current versions.

# Arguments
- `repo_path::String`: Path to the repository root directory
- `registry`: Name or path to the registry (default: "General")
- `push::Bool`: Whether to push the registration to the remote registry (default: false)

# Returns
A NamedTuple with:
- `registered::Vector{String}`: Names of successfully registered packages
- `failed::Vector{String}`: Names of packages that failed to register

# Behavior
1. Scans for all packages (main Project.toml and lib/*/Project.toml)
2. Uses brute-force dependency resolution by repeatedly attempting registration
3. Continues until all packages are registered or no more progress is possible
4. Handles circular dependencies and complex dependency graphs
5. Does NOT modify any Project.toml files or create commits

# Examples
```julia
# Register all packages in a monorepo at current versions
result = register_monorepo_packages("/path/to/repo")
println("Successfully registered: ", length(result.registered), " packages")

# Register with custom registry
register_monorepo_packages("/path/to/repo"; registry="MyRegistry", push=true)
```

# See Also
- [`bump_and_register_repo`](@ref): For bumping versions before registration
- [`register_package`](@ref): For registering a single package
"""
function register_monorepo_packages(repo_path::String; registry = "General", push::Bool = false)
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end
    
    # Collect all package directories
    package_dirs = String[]
    
    # Main package
    if isfile(joinpath(repo_path, "Project.toml"))
        push!(package_dirs, repo_path)
    end
    
    # Subpackages in lib/
    lib_dir = joinpath(repo_path, "lib")
    if isdir(lib_dir)
        for subdir in readdir(lib_dir; join = false)
            subdir_path = joinpath(lib_dir, subdir)
            if isdir(subdir_path) && isfile(joinpath(subdir_path, "Project.toml"))
                push!(package_dirs, subdir_path)
            end
        end
    end
    
    if isempty(package_dirs)
        @info "No packages found to register"
        return (registered = String[], failed = String[])
    end
    
    @info "Found $(length(package_dirs)) packages to register"
    
    # Register packages using brute-force dependency resolution
    registered = Set{String}()
    
    while true
        one_succeed = false
        
        for package_dir in package_dirs
            package_name = basename(package_dir)
            package_name in registered && continue
            
            @info "Trying to register $package_name"
            # We need to register the packages in the correct order so we just brute force try
            # one by one until it succeeds
            try
                LocalRegistry.register(package_dir; registry = registry, push = push)
                push!(registered, package_name)
                one_succeed = true
                @info "Successfully registered $package_name"
            catch e
                if e isa ErrorException
                    # Expected error when dependencies aren't registered yet
                    @debug "Could not register $package_name yet: $(e.msg)"
                else
                    # Unexpected error - log but continue
                    @error "Unexpected error registering $package_name" exception=(e, catch_backtrace())
                end
            end
        end
        
        if !one_succeed
            @info "Could not register any more packages"
            break
        end
    end
    
    # Identify failed packages
    failed_packages = String[]
    for package_dir in package_dirs
        package_name = basename(package_dir)
        if !(package_name in registered)
            push!(failed_packages, package_name)
        end
    end
    
    if !isempty(failed_packages)
        @error "Could not register the following packages: $(join(failed_packages, ", "))"
    end
    
    return (registered = collect(registered), failed = failed_packages)
end

"""
    get_org_repos(org::String; auth_token::String="")

Get all repositories for a GitHub organization.
"""
function get_org_repos(org::String; auth_token::String = "")
    repos = String[]
    page = 1

    headers = ["Accept" => "application/vnd.github.v3+json"]
    if !isempty(auth_token)
        push!(headers, "Authorization" => "token $auth_token")
    end

    while true
        url = "https://api.github.com/orgs/$org/repos?page=$page&per_page=100"

        try
            response = HTTP.get(url, headers)
            repos_data = JSON3.read(String(response.body))

            if isempty(repos_data)
                break
            end

            for repo in repos_data
                push!(repos, repo.full_name)
            end

            page += 1
        catch e
            @error "Failed to fetch repos" page exception=(e, catch_backtrace())
            break
        end
    end

    return repos
end

"""
    bump_and_register_org(org::String; 
                         registry="General",
                         push::Bool=false,
                         auth_token::String="",
                         work_dir::String=mktempdir())

Process all repositories in a GitHub organization: bump versions and register packages.

This function automates the version bumping and registration process across an entire
GitHub organization. It clones each repository, processes Julia packages found within,
and handles both single-package repos and monorepos.

# Arguments
- `org::String`: GitHub organization name (e.g., "JuliaLang", "SciML")
- `registry`: Name or path to the registry (default: "General")
- `push::Bool`: Whether to push registrations to the remote registry (default: false)
- `auth_token::String`: GitHub authentication token for API access (optional but recommended for rate limits)
- `work_dir::String`: Directory for cloning repositories (default: temporary directory)

# Returns
A `Dict{String, Any}` mapping repository names to their results:
- Each entry contains `registered` and `failed` arrays
- May include an `error` field if repository processing failed

# Behavior
1. Fetches all repositories from the GitHub organization using the API
2. Clones each repository (shallow clone for efficiency)
3. Skips non-Julia repositories (no Project.toml)
4. For each Julia repository:
   - Bumps minor versions of all packages
   - Registers packages in dependency order
   - Commits and pushes changes to the repository
5. Cleans up cloned repositories after processing

# Examples
```julia
# Process all repos in an organization
results = bump_and_register_org("MyOrg")
for (repo, result) in results
    println(repo, ": registered ", length(result.registered), " packages")
end

# With authentication and custom registry
results = bump_and_register_org("MyOrg"; 
    auth_token=ENV["GITHUB_TOKEN"],
    registry="MyRegistry",
    push=true
)
```

# Notes
- Requires appropriate permissions to push to repositories
- GitHub API rate limits apply (higher with authentication token)
- Repositories are processed sequentially to avoid overwhelming the registry
- Temporary clones are automatically cleaned up even if errors occur

# See Also
- [`bump_and_register_repo`](@ref): For processing a single repository
- [`get_org_repos`](@ref): For fetching organization repository list
"""
function bump_and_register_org(org::String;
        registry = "General",
        push::Bool = false,
        auth_token::String = "",
        work_dir::String = mktempdir())
    @info "Fetching repositories for organization: $org"
    repos = get_org_repos(org; auth_token)

    if isempty(repos)
        @warn "No repositories found for organization: $org"
        return nothing
    end

    @info "Found $(length(repos)) repositories"

    results = Dict{String, Any}()

    for repo_name in repos
        @info "Processing repository: $repo_name"

        # Clone repository
        repo_dir = joinpath(work_dir, basename(repo_name))
        repo_url = "https://github.com/$repo_name.git"

        try
            run(`git clone --depth 1 $repo_url $repo_dir`)

            # Check if it's a Julia package
            if !isfile(joinpath(repo_dir, "Project.toml"))
                @info "Skipping $repo_name - no Project.toml found"
                continue
            end

            # Bump versions and register
            result = bump_and_register_repo(repo_dir; registry = registry, push = push)
            results[repo_name] = result

            # Push changes if any
            if !isempty(result.registered) || !isempty(result.failed)
                cd(repo_dir) do
                    run(`git push origin main`)
                end
            end

        catch e
            @error "Failed to process $repo_name" exception=(e, catch_backtrace())
            results[repo_name] = (
                registered = String[], failed = String[], error = string(e))
        finally
            # Clean up
            rm(repo_dir; force = true, recursive = true)
        end
    end

    return results
end

# Keep the placeholder functions for backward compatibility
function update_manifests()
    @warn "update_manifests is deprecated. Use bump_and_register_repo or bump_and_register_org instead."
end

function update_project_tomls()
    @warn "update_project_tomls is deprecated. Use bump_and_register_repo or bump_and_register_org instead."
end
