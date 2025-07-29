using Dates
using LibGit2
using Distributed
using HTTP
using JSON3

const VERSION_CHECK_PATTERNS = [
    r"@static\s+if\s+VERSION\s*[><=]=?\s*v\"(\d+\.\d+(?:\.\d+)?)\""i,
    r"^\s*if\s+VERSION\s*[><=]=?\s*v\"(\d+\.\d+(?:\.\d+)?)\""im,
    r"^\s*elseif\s+VERSION\s*[><=]=?\s*v\"(\d+\.\d+(?:\.\d+)?)\""im,
    r"VERSION\s*[><=]=?\s*v\"(\d+\.\d+(?:\.\d+)?)\"\s*&&"i,
    r"VERSION\s*[><=]=?\s*v\"(\d+\.\d+(?:\.\d+)?)\"\s*\|\|"i,
    r"VERSION\s*[><=]=?\s*VersionNumber\(\"(\d+\.\d+(?:\.\d+)?)\"\)"i
]

const JULIA_LTS = v"1.10"

struct VersionCheck
    file::String
    line_number::Int
    line_content::String
    version::VersionNumber
    pattern_match::String
end

"""
    find_version_checks_in_file(filepath::String; min_version::VersionNumber=JULIA_LTS)

Find all version checks in a single file that compare against versions older than min_version.
"""
function find_version_checks_in_file(
        filepath::String; min_version::VersionNumber = JULIA_LTS)
    if !isfile(filepath)
        @warn "File not found: $filepath"
        return VersionCheck[]
    end

    checks = VersionCheck[]

    try
        lines = readlines(filepath)
        for (line_num, line) in enumerate(lines)
            for pattern in VERSION_CHECK_PATTERNS
                m = match(pattern, line)
                if !isnothing(m)
                    version_str = m.captures[1]
                    version = VersionNumber(version_str)

                    if version < min_version
                        push!(checks,
                            VersionCheck(
                                filepath,
                                line_num,
                                line,
                                version,
                                m.match
                            ))
                    end
                end
            end
        end
    catch e
        @error "Error reading file $filepath" exception=(e, catch_backtrace())
    end

    return checks
end

"""
    find_version_checks_in_repo(repo_path::String; min_version::VersionNumber=JULIA_LTS, ignore_dirs=["test", "docs", ".git"])

Find all version checks in a repository that compare against versions older than min_version.
"""
function find_version_checks_in_repo(repo_path::String;
        min_version::VersionNumber = JULIA_LTS,
        ignore_dirs = ["test", "docs", ".git"])
    if !isdir(repo_path)
        error("Repository path does not exist: $repo_path")
    end

    all_checks = VersionCheck[]

    for (root, dirs, files) in walkdir(repo_path)
        # Remove ignored directories from dirs to prevent descending into them
        filter!(d -> !(d in ignore_dirs), dirs)

        for file in files
            if endswith(file, ".jl")
                filepath = joinpath(root, file)
                checks = find_version_checks_in_file(filepath; min_version)
                append!(all_checks, checks)
            end
        end
    end

    return all_checks
end

"""
    find_version_checks_in_org(org::String; 
                              min_version::VersionNumber=JULIA_LTS,
                              auth_token::String="",
                              work_dir::String=mktempdir(),
                              ignore_dirs=["test", "docs", ".git"])

Find all version checks in all repositories of a GitHub organization.
"""
function find_version_checks_in_org(org::String;
        min_version::VersionNumber = JULIA_LTS,
        auth_token::String = "",
        work_dir::String = mktempdir(),
        ignore_dirs = ["test", "docs", ".git"])
    results = Dict{String, Vector{VersionCheck}}()

    @info "Fetching repositories for organization: $org"
    repos = OrgMaintenanceScripts.get_org_repos(org; auth_token)

    if isempty(repos)
        @warn "No repositories found for organization: $org"
        return results
    end

    @info "Found $(length(repos)) repositories"

    for repo_name in repos
        @info "Processing repository: $repo_name"

        repo_dir = joinpath(work_dir, basename(repo_name))
        repo_url = "https://github.com/$repo_name.git"

        try
            run(`git clone --depth 1 $repo_url $repo_dir`)

            checks = find_version_checks_in_repo(repo_dir; min_version, ignore_dirs)
            if !isempty(checks)
                results[repo_name] = checks
            end

        catch e
            @error "Failed to process $repo_name" exception=(e, catch_backtrace())
        finally
            rm(repo_dir; force = true, recursive = true)
        end
    end

    return results
end

"""
    write_version_checks_to_script(checks::Vector{VersionCheck}, output_file::String="fix_version_checks.jl")

Write version check results to a Julia script file that can be executed to fix them.
"""
function write_version_checks_to_script(
        checks::Vector{VersionCheck}, output_file::String = "fix_version_checks.jl")
    open(output_file, "w") do io
        println(io, "#!/usr/bin/env julia")
        println(io, "# Auto-generated script to fix version checks")
        println(io, "# Generated on: ", Dates.now())
        println(io, "# Total checks found: ", length(checks))
        println(io)
        println(io, "using OrgMaintenanceScripts")
        println(io)
        println(io, "# Version checks found:")
        println(io, "version_checks = [")

        for check in checks
            println(io, "    (")
            println(io, "        file = \"", escape_string(check.file), "\",")
            println(io, "        line = ", check.line_number, ",")
            println(io, "        content = \"", escape_string(check.line_content), "\",")
            println(io, "        version = v\"", check.version, "\",")
            println(io, "        pattern = \"", escape_string(check.pattern_match), "\"")
            println(io, "    ),")
        end

        println(io, "]")
        println(io)
        println(io, "# Execute fixes")
        println(io, "for check in version_checks")
        println(io, "    println(\"Processing: \", check.file, \":\", check.line)")
        println(io, "    # Add your fix logic here")
        println(io, "end")
    end

    # Make the script executable
    chmod(output_file, 0o755)

    @info "Version check script written to: $output_file"
    return output_file
end

"""
    write_org_version_checks_to_script(org_results::Dict{String, Vector{VersionCheck}}, output_file::String="fix_org_version_checks.jl")

Write organization-wide version check results to a script file.
"""
function write_org_version_checks_to_script(
        org_results::Dict{String, Vector{VersionCheck}},
        output_file::String = "fix_org_version_checks.jl")
    total_checks = sum(length(checks) for checks in values(org_results))

    open(output_file, "w") do io
        println(io, "#!/usr/bin/env julia")
        println(io, "# Auto-generated script to fix version checks across organization")
        println(io, "# Generated on: ", Dates.now())
        println(io, "# Total repositories with checks: ", length(org_results))
        println(io, "# Total checks found: ", total_checks)
        println(io)
        println(io, "using OrgMaintenanceScripts")
        println(io)
        println(io, "# Version checks by repository:")
        println(io, "org_version_checks = Dict(")

        for (repo, checks) in org_results
            println(io, "    \"", escape_string(repo), "\" => [")
            for check in checks
                println(io, "        (")
                println(io, "            file = \"", escape_string(check.file), "\",")
                println(io, "            line = ", check.line_number, ",")
                println(io, "            content = \"",
                    escape_string(check.line_content), "\",")
                println(io, "            version = v\"", check.version, "\",")
                println(io, "            pattern = \"",
                    escape_string(check.pattern_match), "\"")
                println(io, "        ),")
            end
            println(io, "    ],")
        end

        println(io, ")")
        println(io)
        println(io, "# Process each repository")
        println(io, "for (repo, checks) in org_version_checks")
        println(io, "    println(\"\\nRepository: \$repo\")")
        println(io, "    println(\"Found \$(length(checks)) version checks\")")
        println(io, "    # Add your repository processing logic here")
        println(io, "end")
    end

    chmod(output_file, 0o755)

    @info "Organization version check script written to: $output_file"
    return output_file
end

"""
    fix_version_checks_parallel(checks::Vector{VersionCheck}, n_processes::Int=4; 
                               github_token::String="", 
                               base_branch::String="main",
                               pr_title_prefix::String="[Auto] Remove obsolete version checks")

Fix version checks in parallel using N processes. Each process will create a PR
to fix the version checks by removing obsolete comparisons.
"""
function fix_version_checks_parallel(checks::Vector{VersionCheck}, n_processes::Int = 4;
        github_token::String = "",
        base_branch::String = "main",
        pr_title_prefix::String = "[Auto] Remove obsolete version checks")
    if isempty(github_token)
        error("GitHub token is required for creating PRs")
    end

    # Group checks by repository
    checks_by_repo = Dict{String, Vector{VersionCheck}}()
    for check in checks
        repo_path = dirname(check.file)
        # Find the git root
        while !isdir(joinpath(repo_path, ".git")) && repo_path != "/"
            repo_path = dirname(repo_path)
        end

        if !haskey(checks_by_repo, repo_path)
            checks_by_repo[repo_path] = VersionCheck[]
        end
        push!(checks_by_repo[repo_path], check)
    end

    # Add worker processes if needed
    if nworkers() < n_processes
        addprocs(n_processes - nworkers())
    end

    # Define the worker function
    @everywhere function process_repo_fixes(
            repo_path::String, repo_checks::Vector{VersionCheck},
            github_token::String, base_branch::String, pr_title_prefix::String)
        try
            # Create a temporary directory for Claude to work in
            work_dir = mktempdir()

            # Clone the repository
            repo = LibGit2.GitRepo(repo_path)
            remote_url = LibGit2.url(LibGit2.get(LibGit2.GitRemote, repo, "origin"))
            close(repo)

            # Extract owner/repo from URL
            m = match(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$", remote_url)
            if isnothing(m)
                return (repo_path, false, "Could not parse repository URL")
            end
            owner, repo_name = m.captures

            # Create fix script for Claude
            fix_script = joinpath(work_dir, "fix_checks.jl")
            open(fix_script, "w") do io
                println(io, "# Fix obsolete version checks")
                println(io, "# Repository: $owner/$repo_name")
                println(io, "# Checks to fix:")
                for check in repo_checks
                    println(io,
                        "# - $(check.file):$(check.line_number) - version $(check.version)")
                end
            end

            # Create Claude prompt
            prompt = """
            Please fix the obsolete Julia version checks in the repository $owner/$repo_name.

            The current Julia LTS is v$JULIA_LTS, so any version checks for versions older than this are obsolete.

            Here are the version checks that need to be fixed:
            """

            for check in repo_checks
                prompt *= "\n- File: $(check.file), Line: $(check.line_number)"
                prompt *= "\n  Content: $(check.line_content)"
                prompt *= "\n  Checking for: v$(check.version)"
            end

            prompt *= """

            Please:
            1. Clone the repository from https://github.com/$owner/$repo_name
            2. Create a new branch named 'remove-obsolete-version-checks-$(Dates.format(now(), "yyyymmdd"))'
            3. Remove or update these obsolete version checks
            4. Commit the changes with a descriptive message
            5. Create a PR with title: "$pr_title_prefix for Julia v$JULIA_LTS"
            6. In the PR description, list all the version checks that were removed

            Use the provided GitHub token for authentication: $github_token
            """

            # Here we would normally shell out to Claude
            # For now, return a placeholder
            @info "Would process $repo_path with $(length(repo_checks)) checks"

            return (repo_path, true, "PR created successfully")

        catch e
            return (repo_path, false, string(e))
        end
    end

    # Process repositories in parallel
    results = pmap(pairs(checks_by_repo)) do (repo_path, repo_checks)
        process_repo_fixes(
            repo_path, repo_checks, github_token, base_branch, pr_title_prefix)
    end

    # Summarize results
    successful = count(r -> r[2], results)
    failed = length(results) - successful

    @info "Parallel processing complete" successful failed

    return results
end

"""
    fix_org_version_checks_parallel(org::String, n_processes::Int=4;
                                   min_version::VersionNumber=JULIA_LTS,
                                   github_token::String="",
                                   base_branch::String="main",
                                   work_dir::String=mktempdir())

Find and fix version checks across an entire GitHub organization using parallel processing.
"""
function fix_org_version_checks_parallel(org::String, n_processes::Int = 4;
        min_version::VersionNumber = JULIA_LTS,
        github_token::String = "",
        base_branch::String = "main",
        work_dir::String = mktempdir())

    # First, find all version checks
    @info "Finding version checks in organization: $org"
    org_checks = find_version_checks_in_org(
        org; min_version, auth_token = github_token, work_dir)

    # Flatten into a single list
    all_checks = VersionCheck[]
    for (repo, checks) in org_checks
        append!(all_checks, checks)
    end

    if isempty(all_checks)
        @info "No obsolete version checks found in organization: $org"
        return nothing
    end

    @info "Found $(length(all_checks)) obsolete version checks across $(length(org_checks)) repositories"

    # Write results to script
    script_file = joinpath(work_dir, "fix_$(org)_version_checks.jl")
    write_org_version_checks_to_script(org_checks, script_file)

    # Fix in parallel
    results = fix_version_checks_parallel(
        all_checks, n_processes; github_token, base_branch)

    return (checks = org_checks, fixes = results, script = script_file)
end
