# Minimum Version Fixer
# Automatically fix minimum version bounds for Julia packages

using Pkg
using TOML
using Dates
using HTTP
using JSON3

"""
    setup_resolver(work_dir::String)

Clone and setup Resolver.jl if not already present.
Returns the path to Resolver.jl.
"""
function setup_resolver(work_dir::String)
    resolver_url = "https://github.com/StefanKarpinski/Resolver.jl.git"
    resolver_path = joinpath(work_dir, "Resolver.jl")

    if !isdir(resolver_path)
        @info "Cloning Resolver.jl to $resolver_path..."
        run(`git clone $resolver_url $resolver_path`)

        # Build Resolver.jl
        @info "Building Resolver.jl dependencies..."
        cd(resolver_path) do
            run(`julia --project=. -e 'using Pkg; Pkg.instantiate()'`)
        end
    else
        @info "Using existing Resolver.jl at $resolver_path"
    end

    # Verify resolver is set up correctly
    resolve_script = joinpath(resolver_path, "bin", "resolve.jl")
    if !isfile(resolve_script)
        error("Resolver setup failed: resolve.jl script not found at $resolve_script")
    end

    return resolver_path
end

"""
    downgrade_to_minimum_versions(project_dir::String; julia_version="1.10", mode="alldeps", work_dir=mktempdir())

Downgrade all dependencies to their minimum compatible versions using Resolver.jl.
This uses the same approach as julia-actions/julia-downgrade-compat.
Returns (success::Bool, output::String)
"""
function downgrade_to_minimum_versions(project_dir::String; julia_version = "1.10",
        mode = "alldeps", work_dir = mktempdir())
    project_file = joinpath(project_dir, "Project.toml")
    if !isfile(project_file)
        # Also check for JuliaProject.toml
        project_file = joinpath(project_dir, "JuliaProject.toml")
        if !isfile(project_file)
            return false, "No Project.toml or JuliaProject.toml found in $project_dir"
        end
    end

    # Setup Resolver.jl
    resolver_path = setup_resolver(work_dir)

    # Run resolver to downgrade to minimum versions
    cmd = `julia --project=$resolver_path/bin $resolver_path/bin/resolve.jl $project_dir --min=@$mode --julia=$julia_version`

    @info "Running resolver command: $cmd"

    try
        output = IOBuffer()
        error_output = IOBuffer()
        process = run(pipeline(cmd; stdout = output, stderr = error_output), wait = false)
        wait(process)

        stdout_str = String(take!(output))
        stderr_str = String(take!(error_output))

        if process.exitcode == 0
            @info "Resolver succeeded with output:\n$stdout_str"
            return true, stdout_str
        else
            combined_output = "STDOUT:\n$stdout_str\n\nSTDERR:\n$stderr_str\n\nExit code: $(process.exitcode)"
            @error "Resolver failed:\n$combined_output"
            return false, combined_output
        end
    catch e
        error_msg = sprint(showerror, e, catch_backtrace())
        @error "Exception while running resolver:\n$error_msg"
        return false, "Exception: $error_msg"
    end
end

"""
    test_min_versions(project_dir::String; julia_version="1.10", mode="alldeps", work_dir=mktempdir())

Test if minimum versions can be resolved using Resolver.jl.
Returns (success::Bool, error_output::String)
"""
function test_min_versions(
        project_dir::String; julia_version = "1.10", mode = "alldeps", work_dir = mktempdir())
    @info "Testing minimum versions for $project_dir with Julia $julia_version and mode $mode"

    success,
    output = downgrade_to_minimum_versions(project_dir; julia_version, mode, work_dir)

    if success
        @info "✓ Successfully resolved minimum versions"
        return true, "Successfully resolved minimum versions"
    else
        @error "✗ Failed to resolve minimum versions"
        return false, output
    end
end

"""
    parse_resolution_errors(output::String, project_toml::Dict)

Parse resolution errors to identify problematic packages.
"""
function parse_resolution_errors(output::String, project_toml::Dict)
    problematic = Set{String}()
    deps = get(project_toml, "deps", Dict())

    @info "Parsing resolution errors from output"

    # Common patterns in resolver errors
    error_patterns = [
        r"ERROR: Unsatisfiable requirements detected for package (\w+)",
        r"no version of (\w+) satisfies",
        r"(\w+) \[[\w-]+\]: no versions left",
        r"restricted by compatibility requirements with (\w+)",
        r"package (\w+) has no versions",
        r"Cannot resolve package (\w+)",
        r"Unsatisfiable requirements for (\w+)"
    ]

    # Look for specific error patterns
    for pattern in error_patterns
        for match in eachmatch(pattern, output)
            pkg_name = match.captures[1]
            if haskey(deps, pkg_name)
                @info "Found problematic package from error pattern: $pkg_name"
                push!(problematic, pkg_name)
            end
        end
    end

    # Also look for simple package mentions in error lines
    for line in split(output, '\n')
        if occursin("ERROR", line) || occursin("WARN", line) ||
           occursin("unsatisfiable", lowercase(line))
            for (pkg_name, _) in deps
                if occursin(pkg_name, line)
                    @info "Found problematic package in error line: $pkg_name"
                    push!(problematic, pkg_name)
                end
            end
        end
    end

    # If no specific packages found, check all with low versions
    if isempty(problematic)
        @info "No specific packages found in errors, checking for outdated compat entries"
        compat = get(project_toml, "compat", Dict())
        for (pkg_name, compat_str) in compat
            if pkg_name != "julia" && is_outdated_compat(compat_str, pkg_name)
                @info "Found outdated compat for $pkg_name: $compat_str"
                push!(problematic, pkg_name)
            end
        end
    end

    return collect(problematic)
end

"""
    is_outdated_compat(compat_str::String, pkg_name::String)

Check if a compat string indicates an outdated version by comparing to the latest release.
"""
function is_outdated_compat(compat_str::String, pkg_name::String)
    if isempty(compat_str)
        return true  # No compat is outdated
    end

    # Extract the minimum version from compat
    min_version = extract_min_version_from_compat(compat_str)
    if min_version === nothing
        return false  # Can't parse, assume it's ok
    end

    # Get the latest version
    latest_version = get_latest_version(pkg_name)
    if latest_version === nothing
        # Can't determine latest, fall back to heuristic
        # Very old 0.x versions
        if min_version.major == 0 && min_version.minor < 5
            return true
        end
        return false
    end

    # Check if the minimum version is significantly behind the latest
    if min_version.major < latest_version.major
        return true  # Major version behind
    elseif min_version.major == latest_version.major &&
           min_version.minor < latest_version.minor
        # For 0.x packages, being behind on minor is significant
        if min_version.major == 0
            return true
        end
        # For stable packages, only flag if significantly behind (e.g., more than 5 minor versions)
        if latest_version.minor - min_version.minor > 5
            return true
        end
    end

    return false
end

"""
    extract_min_version_from_compat(compat_str::String)

Extract the minimum version from a compat string.
"""
function extract_min_version_from_compat(compat_str::String)
    # Remove leading ^ or ~
    compat_str = lstrip(compat_str, ['^', '~'])

    # Handle comma-separated ranges (take first)
    if occursin(",", compat_str)
        compat_str = strip(split(compat_str, ",")[1])
    end

    # Handle dash ranges (take lower bound)
    if occursin("-", compat_str)
        compat_str = strip(split(compat_str, "-")[1])
    end

    # Parse version
    try
        # Add .0 if needed to make valid version
        parts = split(compat_str, ".")
        if length(parts) == 1
            compat_str *= ".0.0"
        elseif length(parts) == 2
            compat_str *= ".0"
        end

        return VersionNumber(compat_str)
    catch
        return nothing
    end
end

"""
    get_smart_min_version(pkg_name::String, current_compat::String)

Get an appropriate minimum version for a package.
"""
function get_smart_min_version(pkg_name::String, current_compat::String)
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
    return bump_compat_version(current_compat, pkg_name)
end

"""
    get_latest_version(pkg_name::String)

Get the latest version of a package from the registry.
"""
function get_latest_version(pkg_name::String)
    try
        mktempdir() do tmpdir
            Pkg.activate(tmpdir)
            Pkg.add(pkg_name; io = devnull)

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
    catch e
        # Package not found in registry or other error
        return nothing
    end

    return nothing
end

"""
    bump_compat_version(compat_str::String, pkg_name::String)

Bump a compat version string conservatively, ensuring we don't go above the current release.
"""
function bump_compat_version(compat_str::String, pkg_name::String)
    # Extract current minimum version
    current_min = extract_min_version_from_compat(compat_str)
    if current_min === nothing
        # Can't parse, try to get latest
        latest = get_latest_version(pkg_name)
        if latest !== nothing
            if latest.major == 0
                return string(latest)
            else
                return "$(latest.major).0"
            end
        end
        return compat_str
    end

    # Get the latest version
    latest_version = get_latest_version(pkg_name)
    if latest_version === nothing
        # Can't get latest, bump conservatively
        if current_min.major == 0
            return "0.$(current_min.minor + 1)"
        else
            return "$(current_min.major).0"
        end
    end

    # Determine the new version
    new_version = if current_min.major == 0
        # For 0.x packages, bump to next minor or latest, whichever is lower
        next_minor = VersionNumber("0.$(current_min.minor + 1).0")
        if next_minor <= latest_version
            string(next_minor)
        else
            string(latest_version)
        end
    else
        # For stable packages, use major.0 or latest, whichever is lower
        major_zero = VersionNumber("$(current_min.major).0.0")
        if major_zero <= latest_version
            "$(current_min.major).0"
        else
            # If we're already at or above latest, just use latest
            string(latest_version)
        end
    end

    return new_version
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
    fix_package_min_versions_all(repo_path::String;
                                max_iterations=10,
                                work_dir=mktempdir(),
                                julia_version="1.10",
                                include_subpackages=true)

Fix minimum versions for all Project.toml files in a repository.
Supports repositories with subpackages in the /lib directory.
Returns (success::Bool, all_updates::Dict{String,Dict{String,String}})
"""
function fix_package_min_versions_all(repo_path::String;
        max_iterations::Int = 10,
        work_dir::String = mktempdir(),
        julia_version::String = "1.10",
        include_subpackages::Bool = true)

    # Find all Project.toml files
    project_files = find_all_project_tomls(repo_path)

    if isempty(project_files)
        @warn "No Project.toml files found in $repo_path"
        return false, Dict{String, Dict{String, String}}()
    end

    if !include_subpackages
        # Filter out subpackages
        project_files = filter(p -> !is_subpackage(p, repo_path), project_files)
    end

    all_updates = Dict{String, Dict{String, String}}()
    all_success = true

    for project_file in project_files
        rel_path = get_relative_project_path(project_file, repo_path)
        project_dir = dirname(project_file)

        @info "Fixing minimum versions for $rel_path"

        # Fix minimum versions for this project
        success,
        updates = fix_package_min_versions(project_dir;
            max_iterations,
            work_dir,
            julia_version)

        if !isempty(updates)
            all_updates[rel_path] = updates
        end

        if !success
            all_success = false
        end
    end

    return all_success, all_updates
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
        max_iterations::Int = 10,
        work_dir::String = mktempdir(),
        julia_version::String = "1.10")
    project_file = joinpath(repo_path, "Project.toml")

    if !isfile(project_file)
        @warn "No Project.toml found in $repo_path"
        return false, Dict{String, String}()
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
        success, output = test_min_versions(repo_path; julia_version, work_dir)

        if success
            @info "✓ Minimum versions resolved successfully!"
            break
        end

        @info "Resolution failed, analyzing error output..."
        @info "Full error output:\n$output"

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
            TOML.print(io, project_toml, sorted = true)
        end
    end

    return !isempty(total_updates), total_updates
end

"""
    fix_repo_min_versions(repo_name::String;
                         work_dir=mktempdir(),
                         max_iterations=10,
                         create_pr=true,
                         julia_version="1.10",
                         include_subpackages=true)

Clone a repository, fix its minimum versions, and optionally create a PR.
Now supports repositories with subpackages in /lib directories.
"""
function fix_repo_min_versions(repo_name::String;
        work_dir::String = mktempdir(),
        max_iterations::Int = 10,
        create_pr::Bool = true,
        julia_version::String = "1.10",
        include_subpackages::Bool = true)

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

    # Check if this repo has multiple Project.toml files
    project_files = find_all_project_tomls(repo_dir)
    use_multi = include_subpackages && length(project_files) > 1

    if use_multi
        # Fix minimum versions for all projects
        success,
        all_updates = fix_package_min_versions_all(repo_dir;
            max_iterations,
            work_dir,
            julia_version,
            include_subpackages)

        if !success || isempty(all_updates)
            @info "No changes needed for $repo_name"
            return false
        end

        # Commit changes
        cd(repo_dir) do
            run(`git add -A`)

            commit_msg = """
            Fix minimum version compatibility bounds across multiple packages

            This commit updates the minimum version bounds in [compat] sections to ensure
            they can be resolved by the package manager. Updates were made in:

            """

            for (rel_path, updates) in sort(collect(all_updates))
                commit_msg *= "\n$rel_path:\n"
                for (pkg, ver) in sort(collect(updates))
                    commit_msg *= "  - $pkg: → $ver\n"
                end
            end

            commit_msg *= """

            These changes were determined by running the downgrade CI tests and
            incrementally bumping failing minimum versions to working ones.
            """

            run(`git commit -m $commit_msg`)
        end
    else
        # Fix minimum versions for single project
        success,
        updates = fix_package_min_versions(repo_dir;
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
        end
    end

    if create_pr
        @info "Creating pull request..."

        # Push branch to origin
        cd(repo_dir) do
            run(`git push -u origin HEAD`)
        end

        # Create PR using GitHub CLI - need to handle multi-project case
        if use_multi && !isempty(all_updates)
            pr_title = "Fix minimum version compatibility bounds across multiple packages"
            pr_body = """
            ## Summary

            This PR fixes the minimum version bounds in the `[compat]` sections to ensure all minimum versions can be successfully resolved by Pkg.

            ## Changes

            Updates were made in the following Project.toml files:

            """

            for (rel_path, updates) in sort(collect(all_updates))
                pr_body *= "\n### $rel_path\n\n"
                pr_body *= "| Package | New Minimum Version |\n"
                pr_body *= "|---------|-------------------|\n"
                for (pkg, ver) in sort(collect(updates))
                    pr_body *= "| $pkg | $ver |\n"
                end
            end

            pr_body *= """

            ## Testing

            These changes were determined by:
            1. Running the downgrade CI workflow locally
            2. Identifying packages that failed to resolve at their minimum versions
            3. Bumping those packages to known-working minimum versions
            4. Repeating until all packages resolve successfully

            This ensures all packages will pass the Downgrade CI tests.
            """
        elseif !use_multi && !isempty(updates)
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
        else
            # No updates made
            @info "No PR created as no updates were made"
            return true
        end

        cd(repo_dir) do
            try
                run(`gh pr create --title "$pr_title" --body "$pr_body"`)
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
                        julia_version="1.10",
                        include_subpackages=true)

Fix minimum versions for all Julia packages in a GitHub organization.
Now supports repositories with subpackages in /lib directories.
"""
function fix_org_min_versions(org_name::String;
        work_dir::String = mktempdir(),
        max_iterations::Int = 10,
        create_prs::Bool = true,
        skip_repos::Vector{String} = String[],
        only_repos::Union{Nothing, Vector{String}} = nothing,
        julia_version::String = "1.10",
        include_subpackages::Bool = true)
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
                create_pr = create_prs,
                julia_version,
                include_subpackages)
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
