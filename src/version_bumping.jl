using Pkg
using TOML
using LibGit2
using HTTP
using JSON3

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
    register_package(package_dir::String; registry_url="https://github.com/JuliaRegistries/General")

Register a Julia package to the specified registry.
"""
function register_package(package_dir::String; registry_url = "https://github.com/JuliaRegistries/General")
    # This is a placeholder - actual registration requires LocalRegistry.jl
    # and proper authentication/permissions
    @info "Would register package at $package_dir to $registry_url"

    # In practice, this would use:
    # using LocalRegistry
    # register(package_dir; registry=registry_url)

    return true
end

"""
    bump_and_register_repo(repo_path::String; registry_url="https://github.com/JuliaRegistries/General")

Bump minor versions and register all packages in a repository.
This handles the main Project.toml and all lib/*/Project.toml files.
"""
function bump_and_register_repo(repo_path::String; registry_url = "https://github.com/JuliaRegistries/General")
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end

    registered_packages = String[]
    failed_packages = String[]

    # Handle main Project.toml
    main_project = joinpath(repo_path, "Project.toml")
    if isfile(main_project)
        result = update_project_version(main_project)
        if !isnothing(result)
            try
                register_package(repo_path; registry_url)
                push!(registered_packages, basename(repo_path))
            catch e
                @error "Failed to register main package" exception=(e, catch_backtrace())
                push!(failed_packages, basename(repo_path))
            end
        end
    end

    # Handle lib/*/Project.toml files
    lib_dir = joinpath(repo_path, "lib")
    if isdir(lib_dir)
        for subdir in readdir(lib_dir; join = false)
            subdir_path = joinpath(lib_dir, subdir)
            if !isdir(subdir_path)
                continue
            end

            project_path = joinpath(subdir_path, "Project.toml")
            if isfile(project_path)
                result = update_project_version(project_path)
                if !isnothing(result)
                    try
                        register_package(subdir_path; registry_url)
                        push!(registered_packages, subdir)
                    catch e
                        @error "Failed to register $subdir" exception=(e, catch_backtrace())
                        push!(failed_packages, subdir)
                    end
                end
            end
        end
    end

    # Commit changes if any packages were updated
    if !isempty(registered_packages) || !isempty(failed_packages)
        repo = LibGit2.GitRepo(repo_path)
        try
            LibGit2.add!(repo, ".")
            sig = LibGit2.Signature("OrgMaintenanceScripts", "noreply@sciml.ai")
            msg = "Bump minor versions for registration\n\nPackages: $(join(vcat(registered_packages, failed_packages), ", "))"
            LibGit2.commit(repo, msg; author = sig, committer = sig)
            @info "Committed version bumps"
        finally
            close(repo)
        end
    end

    return (registered = registered_packages, failed = failed_packages)
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
                         registry_url="https://github.com/JuliaRegistries/General",
                         auth_token::String="",
                         work_dir::String=mktempdir())

Bump minor versions and register all packages in all repositories of a GitHub organization.
"""
function bump_and_register_org(org::String;
        registry_url = "https://github.com/JuliaRegistries/General",
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
            result = bump_and_register_repo(repo_dir; registry_url)
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
