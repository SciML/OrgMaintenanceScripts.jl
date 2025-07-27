# Compat bumping functionality for SciML repositories

using Pkg
using TOML
using Dates
using LibGit2

"""
    CompatUpdate

Struct to hold information about a potential compat update.
"""
struct CompatUpdate
    package_name::String
    current_compat::String
    latest_version::String
    is_major_update::Bool
end

"""
    get_available_compat_updates(project_path::String)

Check for available compat updates in a Project.toml file.
Returns a vector of CompatUpdate structs.
"""
function get_available_compat_updates(project_path::String)
    if !isfile(project_path)
        error("Project.toml not found at $project_path")
    end
    
    project = TOML.parsefile(project_path)
    
    if !haskey(project, "compat")
        @info "No compat section found in $project_path"
        return CompatUpdate[]
    end
    
    updates = CompatUpdate[]
    
    # Get the registry to check latest versions
    registry_path = joinpath(DEPOT_PATH[1], "registries", "General")
    if !isdir(registry_path)
        @warn "General registry not found. Running Pkg.Registry.update()..."
        Pkg.Registry.update()
    end
    
    for (pkg_name, compat_spec) in project["compat"]
        if pkg_name == "julia"
            continue
        end
        
        try
            # Get latest version from registry
            latest_version = get_latest_package_version(pkg_name)
            if isnothing(latest_version)
                continue
            end
            
            # Parse current compat
            current_compat = compat_spec
            
            # Check if it's a major version update
            is_major = is_major_version_update(current_compat, latest_version)
            
            if is_major
                push!(updates, CompatUpdate(pkg_name, current_compat, latest_version, true))
            end
        catch e
            @warn "Failed to check updates for $pkg_name" exception=e
        end
    end
    
    return updates
end

"""
    get_latest_package_version(package_name::String)

Get the latest version of a package from the General registry.
"""
function get_latest_package_version(package_name::String)
    registry_path = joinpath(DEPOT_PATH[1], "registries", "General")
    
    # Find the package in the registry
    first_letter = uppercase(first(package_name))
    pkg_path = joinpath(registry_path, string(first_letter), package_name)
    
    if !isdir(pkg_path)
        # Try lowercase first letter
        pkg_path = joinpath(registry_path, lowercase(string(first_letter)), package_name)
        if !isdir(pkg_path)
            @debug "Package $package_name not found in registry"
            return nothing
        end
    end
    
    versions_file = joinpath(pkg_path, "Versions.toml")
    if !isfile(versions_file)
        @debug "Versions.toml not found for $package_name"
        return nothing
    end
    
    versions = TOML.parsefile(versions_file)
    version_numbers = [VersionNumber(v) for v in keys(versions)]
    
    if isempty(version_numbers)
        return nothing
    end
    
    return string(maximum(version_numbers))
end

"""
    is_major_version_update(current_compat::String, latest_version::String)

Check if the latest version is a major version update compared to current compat.
"""
function is_major_version_update(current_compat::String, latest_version::String)
    # Parse the current compat to get the upper bound
    compat_upper = parse_compat_upper_bound(current_compat)
    if isnothing(compat_upper)
        return false
    end
    
    latest_v = VersionNumber(latest_version)
    compat_v = VersionNumber(compat_upper)
    
    # Check if major version is different
    return latest_v.major > compat_v.major
end

"""
    parse_compat_upper_bound(compat_spec::String)

Parse a compat specification to extract the upper bound version.
"""
function parse_compat_upper_bound(compat_spec::String)
    # Remove spaces
    spec = replace(compat_spec, " " => "")
    
    # Handle different compat formats
    if occursin(",", spec)
        # Range like "1.5, 2"
        parts = split(spec, ",")
        return parts[end]
    elseif startswith(spec, "^")
        # Caret notation like "^1.5"
        return spec[2:end]
    elseif startswith(spec, "~")
        # Tilde notation like "~1.5"
        return spec[2:end]
    elseif occursin("-", spec)
        # Range like "1.0-2.0"
        parts = split(spec, "-")
        return parts[end]
    else
        # Single version
        return spec
    end
end

"""
    bump_compat_entry(project_path::String, package_name::String, new_version::String)

Bump a single compat entry in Project.toml to allow the new version.
"""
function bump_compat_entry(project_path::String, package_name::String, new_version::String)
    project = TOML.parsefile(project_path)
    
    if !haskey(project, "compat") || !haskey(project["compat"], package_name)
        error("Package $package_name not found in compat section")
    end
    
    # Parse new version
    new_v = VersionNumber(new_version)
    
    # Create new compat entry that includes the new major version
    new_compat = "$(new_v.major)"
    
    # Update the compat entry
    project["compat"][package_name] = new_compat
    
    # Write back to file
    open(project_path, "w") do io
        TOML.print(io, project)
    end
    
    @info "Updated $package_name compat to $new_compat"
end

"""
    bump_compat_and_test(repo_path::String;
                        package_name::Union{String,Nothing} = nothing,
                        bump_all::Bool = false,
                        create_pr::Bool = true,
                        fork_user::String = "")

Bump compat entries for major version updates and run tests.
If tests pass, optionally create a PR.

# Arguments
- `repo_path`: Path to the repository
- `package_name`: Specific package to bump (if nothing, check all)
- `bump_all`: Whether to bump all available updates or just one
- `create_pr`: Whether to create a PR if tests pass
- `fork_user`: GitHub username for creating PRs (required if create_pr=true)

# Returns
- `(success::Bool, message::String, pr_url::Union{String,Nothing}, bumped_packages::Vector{String})`
"""
function bump_compat_and_test(repo_path::String;
                             package_name::Union{String,Nothing} = nothing,
                             bump_all::Bool = false,
                             create_pr::Bool = true,
                             fork_user::String = "")
    
    if create_pr && isempty(fork_user)
        return (false, "fork_user must be provided when create_pr=true", nothing, String[])
    end
    
    project_path = joinpath(repo_path, "Project.toml")
    if !isfile(project_path)
        return (false, "Project.toml not found in repository", nothing, String[])
    end
    
    # Get available updates
    updates = get_available_compat_updates(project_path)
    
    if isempty(updates)
        return (true, "No major version updates available", nothing, String[])
    end
    
    # Filter updates if specific package requested
    if !isnothing(package_name)
        updates = filter(u -> u.package_name == package_name, updates)
        if isempty(updates)
            return (false, "No major version update available for $package_name", nothing, String[])
        end
    end
    
    # Determine which updates to apply
    updates_to_apply = bump_all ? updates : [first(updates)]
    
    # Create branch if not on one
    cd(repo_path) do
        current_branch = strip(read(`git branch --show-current`, String))
        if current_branch in ["main", "master"]
            branch_name = "compat-bump-$(join([u.package_name for u in updates_to_apply], "-"))"
            run(`git checkout -b $branch_name`)
        end
    end
    
    # Apply updates
    bumped_packages = String[]
    for update in updates_to_apply
        try
            @info "Bumping compat for $(update.package_name) from $(update.current_compat) to allow $(update.latest_version)"
            bump_compat_entry(project_path, update.package_name, update.latest_version)
            push!(bumped_packages, update.package_name)
        catch e
            @error "Failed to bump $(update.package_name)" exception=e
        end
    end
    
    if isempty(bumped_packages)
        return (false, "Failed to bump any packages", nothing, String[])
    end
    
    # Update manifest
    cd(repo_path) do
        try
            run(`julia --project=. -e "using Pkg; Pkg.update()"`)
        catch e
            @warn "Failed to update manifest" exception=e
        end
    end
    
    # Run tests
    @info "Running tests..."
    test_passed = run_package_tests(repo_path)
    
    if !test_passed
        @warn "Tests failed after bumping compat"
        return (false, "Tests failed after bumping compat", nothing, bumped_packages)
    end
    
    @info "Tests passed!"
    
    # Commit changes
    cd(repo_path) do
        run(`git add Project.toml Manifest.toml`)
        
        commit_message = if length(bumped_packages) == 1
            """
            CompatHelper: bump compat for $(bumped_packages[1])

            - Bumped $(bumped_packages[1]) to allow latest major version
            - Tests pass with updated dependency
            
            🤖 Generated by OrgMaintenanceScripts.jl
            """
        else
            """
            CompatHelper: bump compat for multiple packages

            Bumped compat for:
            $(join(["- $pkg" for pkg in bumped_packages], "\n"))

            All tests pass with updated dependencies.
            
            🤖 Generated by OrgMaintenanceScripts.jl
            """
        end
        
        run(`git config user.email "sciml-bot@julialang.org"`)
        run(`git config user.name "SciML Bot"`)
        
        open("commit_msg.txt", "w") do f
            print(f, commit_message)
        end
        run(`git commit -F commit_msg.txt`)
        rm("commit_msg.txt")
    end
    
    # Create PR if requested
    pr_url = nothing
    if create_pr
        pr_url = create_compat_pr(repo_path, bumped_packages, fork_user)
    end
    
    return (true, "Successfully bumped compat and tests passed", pr_url, bumped_packages)
end

"""
    run_package_tests(repo_path::String; timeout_minutes::Int = 30)

Run tests for a Julia package and return whether they passed.
"""
function run_package_tests(repo_path::String; timeout_minutes::Int = 30)
    try
        cd(repo_path) do
            # First instantiate the project
            run(`julia --project=. -e "using Pkg; Pkg.instantiate()"`)
            
            # Run tests with timeout
            test_cmd = `julia --project=. -e "using Pkg; Pkg.test()"`
            test_process = run(pipeline(test_cmd; stdout=stdout, stderr=stderr); wait=false)
            
            # Wait for tests with timeout
            test_start = time()
            timeout_seconds = timeout_minutes * 60
            
            while !process_exited(test_process) && (time() - test_start) < timeout_seconds
                sleep(1)
            end
            
            if process_exited(test_process) && success(test_process)
                return true
            else
                if !process_exited(test_process)
                    kill(test_process)
                    @warn "Tests timed out after $timeout_minutes minutes"
                end
                return false
            end
        end
    catch e
        @error "Error running tests" exception=e
        return false
    end
end

"""
    create_compat_pr(repo_path::String, bumped_packages::Vector{String}, fork_user::String)

Create a pull request for compat updates.
"""
function create_compat_pr(repo_path::String, bumped_packages::Vector{String}, fork_user::String)
    cd(repo_path) do
        # Get repo info
        remote_url = strip(read(`git remote get-url origin`, String))
        m = match(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$", remote_url)
        if m === nothing
            @error "Could not parse repository URL"
            return nothing
        end
        org, repo = m.captures
        
        # Push to fork
        current_branch = strip(read(`git branch --show-current`, String))
        fork_url = "https://github.com/$fork_user/$repo.git"
        
        try
            run(`git remote add fork $fork_url`)
        catch
            # Fork remote might already exist
        end
        
        run(`git push fork $current_branch --force`)
        
        # Create PR
        pr_title = if length(bumped_packages) == 1
            "CompatHelper: bump compat for $(bumped_packages[1]) to latest major version"
        else
            "CompatHelper: bump compat for $(length(bumped_packages)) packages"
        end
        
        pr_body = """
        ## Summary
        This PR updates compat entries to allow the latest major versions of dependencies.
        
        ### Updated packages:
        $(join(["- **$pkg**" for pkg in bumped_packages], "\n"))
        
        ## Testing
        ✅ All tests pass with the updated dependencies
        
        ## Notes
        - This update was generated automatically by OrgMaintenanceScripts.jl
        - The compat entries have been updated to allow the latest major versions
        - The Manifest.toml has been updated accordingly
        
        🤖 Generated by OrgMaintenanceScripts.jl
        """
        
        open("pr_body.txt", "w") do f
            print(f, pr_body)
        end
        
        try
            pr_output = read(`gh pr create --repo $org/$repo --head $fork_user:$current_branch --title "$pr_title" --body-file pr_body.txt`, String)
            rm("pr_body.txt")
            return strip(pr_output)
        catch e
            rm("pr_body.txt")
            @error "Failed to create PR" exception=e
            return nothing
        end
    end
end

"""
    bump_compat_org_repositories(org::String = "SciML";
                                package_name::Union{String,Nothing} = nothing,
                                bump_all::Bool = false,
                                create_pr::Bool = true,
                                fork_user::String = "",
                                limit::Int = 100,
                                log_file::String = "")

Bump compat entries for all repositories in a GitHub organization.

# Arguments
- `org`: GitHub organization name (default: "SciML")
- `package_name`: Specific package to bump across all repos (if nothing, check all)
- `bump_all`: Whether to bump all available updates or just one per repo
- `create_pr`: Whether to create PRs if tests pass
- `fork_user`: GitHub username for creating PRs (required if create_pr=true)
- `limit`: Maximum number of repositories to process
- `log_file`: Path to save results log (default: auto-generated)

# Returns
- `(successes::Vector{String}, failures::Vector{String}, pr_urls::Vector{String})`
"""
function bump_compat_org_repositories(org::String = "SciML";
                                     package_name::Union{String,Nothing} = nothing,
                                     bump_all::Bool = false,
                                     create_pr::Bool = true,
                                     fork_user::String = "",
                                     limit::Int = 100,
                                     log_file::String = "")
    
    if create_pr && isempty(fork_user)
        error("fork_user must be provided when create_pr=true")
    end
    
    # Set up logging
    if isempty(log_file)
        log_dir = joinpath(pwd(), "compat_bump_logs")
        mkpath(log_dir)
        log_file = joinpath(log_dir, "compat_bump_$(org)_$(Dates.format(now(), "yyyy-mm-dd_HHMMSS")).log")
    end
    
    @info "Starting organization-wide compat bumping" org=org log_file=log_file
    
    # Get repositories
    @info "Fetching repositories from $org..."
    repos = try
        cmd = `gh repo list $org --limit $limit --json name,isArchived --jq '.[] | select(.isArchived == false and (.name | endswith(".jl"))) | .name'`
        output = read(cmd, String)
        filter(!isempty, split(strip(output), '\n'))
    catch e
        @error "Failed to fetch repositories" exception=e
        return (String[], String[], String[])
    end
    
    @info "Found $(length(repos)) Julia repositories to process"
    
    # Process repositories
    successes = String[]
    failures = String[]
    pr_urls = String[]
    
    working_dir = mktempdir()
    
    open(log_file, "w") do log_io
        println(log_io, "# SciML Organization Compat Bump Log")
        println(log_io, "# Generated: $(Dates.now())")
        println(log_io, "# Organization: $org")
        println(log_io, "# Total repositories: $(length(repos))")
        println(log_io, "# Target package: $(isnothing(package_name) ? "all" : package_name)")
        println(log_io, "# Bump all: $bump_all")
        println(log_io, "#" * "="^60)
        println(log_io)
        
        for (i, repo) in enumerate(repos)
            @info "Processing repository" repo=repo progress="$i/$(length(repos))"
            println(log_io, "\n[$i/$(length(repos))] Processing $repo...")
            
            repo_url = "https://github.com/$org/$repo.git"
            repo_path = joinpath(working_dir, repo)
            
            try
                # Clone repository
                run(`git clone --depth 1 $repo_url $repo_path`)
                
                # Check for Julia package
                if !isfile(joinpath(repo_path, "Project.toml"))
                    println(log_io, "⚠️  SKIPPED: Not a Julia package (no Project.toml)")
                    continue
                end
                
                # Bump compat and test
                success, message, pr_url, bumped = bump_compat_and_test(
                    repo_path;
                    package_name = package_name,
                    bump_all = bump_all,
                    create_pr = create_pr,
                    fork_user = fork_user
                )
                
                if success && !isempty(bumped)
                    push!(successes, repo)
                    if !isnothing(pr_url)
                        push!(pr_urls, pr_url)
                        println(log_io, "✓ SUCCESS: $message")
                        println(log_io, "  Bumped: $(join(bumped, ", "))")
                        println(log_io, "  PR: $pr_url")
                    else
                        println(log_io, "✓ SUCCESS: $message")
                        println(log_io, "  Bumped: $(join(bumped, ", "))")
                    end
                elseif success && isempty(bumped)
                    println(log_io, "⚠️  SKIPPED: $message")
                else
                    push!(failures, repo)
                    println(log_io, "✗ FAILED: $message")
                end
                
            catch e
                push!(failures, repo)
                println(log_io, "✗ ERROR: $(sprint(showerror, e))")
            finally
                # Clean up
                rm(repo_path; force=true, recursive=true)
            end
            
            flush(log_io)
            
            # Rate limiting
            sleep(2)
        end
        
        # Write summary
        println(log_io, "\n" * "="^60)
        println(log_io, "SUMMARY")
        println(log_io, "="^60)
        println(log_io, "Total processed: $(length(repos))")
        println(log_io, "Successful: $(length(successes))")
        println(log_io, "Failed: $(length(failures))")
        println(log_io, "PRs created: $(length(pr_urls))")
        
        if !isempty(pr_urls)
            println(log_io, "\nPull Requests:")
            for url in pr_urls
                println(log_io, "  - $url")
            end
        end
    end
    
    rm(working_dir; force=true, recursive=true)
    
    @info "Organization compat bumping complete" successes=length(successes) failures=length(failures) prs=length(pr_urls)
    
    return (successes, failures, pr_urls)
end