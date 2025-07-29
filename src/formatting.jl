# Formatting maintenance functions for SciML repositories

using Pkg
using Dates
using JuliaFormatter

"""
    format_repository(repo_url::String; 
                     test::Bool = true,
                     push_to_master::Bool = false,
                     create_pr::Bool = true,
                     fork_user::String = "",
                     working_dir::String = mktempdir())

Format a single repository with JuliaFormatter.

# Arguments

  - `repo_url`: URL of the repository to format (e.g., "https://github.com/SciML/Example.jl.git")
  - `test`: Whether to run tests after formatting (default: true)
  - `push_to_master`: Whether to push directly to master/main if tests pass (default: false)
  - `create_pr`: Whether to create a PR instead of pushing to master (default: true)
  - `fork_user`: GitHub username for creating PRs (required if create_pr=true)
  - `working_dir`: Directory to clone the repository into (default: temporary directory)

# Returns

  - `(success::Bool, message::String, pr_url::Union{String,Nothing})`
"""
function format_repository(
        repo_url::String;
        test::Bool = true,
        push_to_master::Bool = false,
        create_pr::Bool = true,
        fork_user::String = "",
        working_dir::String = mktempdir()
)

    # Validate inputs
    if create_pr && isempty(fork_user)
        # Try to get current gh user
        try
            fork_user = strip(read(`gh api user --jq .login`, String))
            @info "Using GitHub username from gh CLI: $fork_user"
        catch
            error_msg = "fork_user must be provided when create_pr=true (or configure gh CLI)"
            @error error_msg repo=repo_url
            return (false, error_msg, nothing)
        end
    end

    if push_to_master && create_pr
        error_msg = "Cannot both push_to_master and create_pr"
        @error error_msg repo=repo_url
        return (false, error_msg, nothing)
    end

    # Extract repo name from URL
    repo_name = basename(repo_url)
    if endswith(repo_name, ".git")
        repo_name = repo_name[1:(end - 4)]
    end

    repo_path = joinpath(working_dir, repo_name)

    try
        # Clone repository
        @info "Cloning $repo_name..."
        run(`git clone $repo_url $repo_path`)

        cd(repo_path) do
            # Get default branch
            default_branch = strip(read(
                `git symbolic-ref refs/remotes/origin/HEAD`, String))
            default_branch = split(default_branch, "/")[end]

            # Create branch if not pushing to master
            if !push_to_master
                @info "Creating formatting branch..."
                run(`git checkout -b fix-formatting`)
            end

            # Check for formatter config
            formatter_config_created = false
            if !isfile(".JuliaFormatter.toml")
                @info "Creating .JuliaFormatter.toml with SciML style..."
                open(".JuliaFormatter.toml", "w") do f
                    println(f, "style = \"sciml\"")
                    println(f, "format_markdown = true")
                    println(f, "format_docstrings = true")
                end
                formatter_config_created = true
            end

            # Run formatter
            @info "Running JuliaFormatter..."
            format_result = try
                JuliaFormatter.format(".")
                true
            catch e
                @warn "Formatter encountered errors" exception=e
                false
            end

            # Check for changes (excluding just the formatter config)
            changes = read(`git status --porcelain`, String)
            changed_files = filter(!isempty, split(changes, '\n'))

            # If only change is the formatter config, no formatting was needed
            if isempty(changed_files) ||
               (length(changed_files) == 1 && formatter_config_created &&
                occursin(".JuliaFormatter.toml", changed_files[1]))
                @info "No formatting changes needed"
                return (true, "No formatting changes needed", nothing)
            end

            # Add formatter config if it was created
            if formatter_config_created
                run(`git add .JuliaFormatter.toml`)
            end

            # Stage changes
            run(`git add -A`)

            # Get statistics
            stats = read(`git diff --cached --stat`, String)
            num_files_changed = count(c -> c == '\n', stats) - 1

            @info "Formatting complete" files_changed=num_files_changed

            # Run tests if requested
            test_passed = true
            if test
                @info "Running tests..."
                test_passed = run_tests(repo_path)
            end

            if !test_passed && push_to_master
                return (false, "Tests failed, not pushing to master", nothing)
            end

            # Commit changes
            @info "Committing changes..."
            commit_message = """
            Apply JuliaFormatter to fix code formatting

            - Applied JuliaFormatter with SciML style guide
            - Formatted $num_files_changed files
            $(test ? "- Tests: $(test_passed ? "✓ Passed" : "✗ Failed")" : "")

            🤖 Generated by OrgMaintenanceScripts.jl
            """

            run(`git config user.email "sciml-bot@julialang.org"`)
            run(`git config user.name "SciML Bot"`)

            open("commit_msg.txt", "w") do f
                print(f, commit_message)
            end
            run(`git commit -F commit_msg.txt`)
            rm("commit_msg.txt")

            # Push or create PR
            if push_to_master
                @info "Pushing to $default_branch..."
                run(`git push origin $default_branch`)
                return (
                    true,
                    "Successfully pushed formatting changes to $default_branch",
                    nothing
                )
            elseif create_pr
                @info "Creating pull request..."

                # Extract org and repo from URL first (needed for gh commands)
                m = match(r"github\.com/([^/]+)/([^/]+?)(?:\.git)?$", repo_url)
                if m === nothing
                    return (false, "Could not parse repository URL", nothing)
                end
                org, repo = m.captures

                # Create or verify fork using gh
                @info "Ensuring fork exists..."
                fork_exists = try
                    # Check if fork already exists
                    run(`gh repo view $fork_user/$repo --json name`)
                    true
                catch
                    false
                end

                if !fork_exists
                    @info "Creating fork..."
                    try
                        run(`gh repo fork $org/$repo --clone=false`)
                    catch e
                        error_msg = "Failed to create fork: $(sprint(showerror, e))"
                        @error error_msg
                        return (false, error_msg, nothing)
                    end
                    # Wait a moment for fork to be created
                    sleep(2)
                end

                # Add fork remote
                fork_url = "https://github.com/$fork_user/$repo.git"
                run(`git remote add fork $fork_url`)

                # Push to fork
                try
                    run(`git push fork fix-formatting --force`)
                catch e
                    error_msg = "Failed to push to fork: $(sprint(showerror, e))"
                    @error error_msg
                    return (false, error_msg, nothing)
                end

                # Wait for push to be processed
                sleep(1)

                # Create PR using gh CLI
                pr_body = """
                ## Summary
                - Applied JuliaFormatter to ensure consistent code formatting
                - Formatted $num_files_changed files to comply with SciML style guide
                $(test ? "- Test status: $(test_passed ? "✅ All tests passed" : "⚠️ Some tests failed")" : "")

                ## Changes
                ```
                $stats
                ```

                This PR was automatically generated by OrgMaintenanceScripts.jl
                """

                open("pr_body.txt", "w") do f
                    print(f, pr_body)
                end

                # Check if PR already exists
                existing_pr = try
                    pr_list = read(
                        `gh pr list --repo $org/$repo --head $fork_user:fix-formatting --json url --jq '.[0].url'`,
                        String)
                    strip(pr_list)
                catch
                    ""
                end

                if !isempty(existing_pr)
                    @info "Pull request already exists, will update it" pr=existing_pr
                    rm("pr_body.txt"; force = true)
                    return (true, "Updated existing pull request", existing_pr)
                end

                # Create new PR
                try
                    pr_output = read(
                        `gh pr create --repo $org/$repo --head $fork_user:fix-formatting --base $default_branch --title "Apply JuliaFormatter to fix code formatting" --body-file pr_body.txt`,
                        String
                    )
                    rm("pr_body.txt")
                    pr_url = strip(pr_output)
                    return (true, "Successfully created pull request", pr_url)
                catch e
                    rm("pr_body.txt"; force = true)
                    error_output = sprint(showerror, e)

                    # Check if error is because PR already exists (shouldn't happen but handle it)
                    if occursin("already exists", error_output)
                        # Try to get the existing PR URL
                        existing_pr = try
                            pr_list = read(
                                `gh pr list --repo $org/$repo --head $fork_user:fix-formatting --json url --jq '.[0].url'`,
                                String)
                            strip(pr_list)
                        catch
                            ""
                        end

                        if !isempty(existing_pr)
                            @info "Pull request already exists (from error), updated it" pr=existing_pr
                            return (true, "Updated existing pull request", existing_pr)
                        end
                    end

                    error_msg = "Failed to create PR: $error_output"
                    @error error_msg
                    return (false, error_msg, nothing)
                end
            end
        end
    catch e
        return (false, "Error: $(sprint(showerror, e))", nothing)
    finally
        # Cleanup if using temp directory
        if startswith(working_dir, tempdir())
            rm(repo_path; force = true, recursive = true)
        end
    end
end

"""
    run_tests(repo_path::String; timeout_minutes::Int = 10)

Run tests for a Julia package.

# Returns

  - `true` if tests pass, `false` otherwise
"""
function run_tests(repo_path::String; timeout_minutes::Int = 10)
    try
        # First instantiate the project
        run(`julia --project=. -e "using Pkg; Pkg.instantiate()"`)

        # Run tests with timeout
        test_cmd = `julia --project=. -e "using Pkg; Pkg.test()"`
        test_process = run(
            pipeline(test_cmd; stdout = stdout, stderr = stderr); wait = false)

        # Wait for tests with timeout
        test_start = time()
        timeout_seconds = timeout_minutes * 60

        while !process_exited(test_process) && (time() - test_start) < timeout_seconds
            sleep(1)
        end

        if process_exited(test_process) && success(test_process)
            @info "Tests passed!"
            return true
        else
            if !process_exited(test_process)
                kill(test_process)
                @warn "Tests timed out after $timeout_minutes minutes"
            else
                @warn "Tests failed"
            end
            return false
        end
    catch e
        @error "Error running tests" exception=e
        return false
    end
end

"""
    format_org_repositories(org::String = "SciML";
                           test::Bool = true,
                           push_to_master::Bool = false,
                           create_pr::Bool = true,
                           fork_user::String = "",
                           limit::Int = 100,
                           only_failing_ci::Bool = true,
                           log_file::String = "")

Format all repositories in a GitHub organization.

# Arguments

  - `org`: GitHub organization name (default: "SciML")
  - `test`: Whether to run tests after formatting (default: true)
  - `push_to_master`: Whether to push directly to master/main if tests pass (default: false)
  - `create_pr`: Whether to create PRs instead of pushing to master (default: true)
  - `fork_user`: GitHub username for creating PRs (required if create_pr=true)
  - `limit`: Maximum number of repositories to process (default: 100)
  - `only_failing_ci`: Only process repos with failing formatter CI (default: true)
  - `log_file`: Path to save results log (default: auto-generated)

# Returns

  - `(successes::Vector{String}, failures::Vector{String}, pr_urls::Vector{String})`
"""
function format_org_repositories(
        org::String = "SciML";
        test::Bool = true,
        push_to_master::Bool = false,
        create_pr::Bool = true,
        fork_user::String = "",
        limit::Int = 100,
        only_failing_ci::Bool = true,
        log_file::String = ""
)

    # Validate inputs early
    if create_pr && isempty(fork_user)
        # Try to get current gh user
        try
            fork_user = strip(read(`gh api user --jq .login`, String))
            @info "Using GitHub username from gh CLI: $fork_user"
        catch
            error_msg = "fork_user must be provided when create_pr=true (or configure gh CLI)"
            @error error_msg
            return (String[], String[], String[])
        end
    end

    if push_to_master && create_pr
        error_msg = "Cannot both push_to_master and create_pr"
        @error error_msg
        return (String[], String[], String[])
    end

    # Set up logging
    if isempty(log_file)
        log_dir = joinpath(pwd(), "formatting_logs")
        mkpath(log_dir)
        log_file = joinpath(
            log_dir,
            "formatting_$(org)_$(Dates.format(now(), "yyyy-mm-dd_HHMMSS")).log"
        )
    end

    @info "Starting organization-wide formatting" org=org log_file=log_file

    # Get repositories
    @info "Fetching repositories from $org..."
    repos = get_org_repositories(org, limit)

    if only_failing_ci
        @info "Filtering repositories with failing formatter CI..."
        repos = filter(repo -> has_failing_formatter_ci(org, repo), repos)
    end

    @info "Found $(length(repos)) repositories to process"

    # Process repositories
    successes = String[]
    failures = String[]
    pr_urls = String[]

    working_dir = mktempdir()

    open(log_file, "w") do log_io
        println(log_io, "# SciML Organization Formatting Log")
        println(log_io, "# Generated: $(Dates.now())")
        println(log_io, "# Organization: $org")
        println(log_io, "# Total repositories: $(length(repos))")
        println(log_io, "#" * "="^60)
        println(log_io)

        for (i, repo) in enumerate(repos)
            @info "Processing repository" repo=repo progress="$i/$(length(repos))"
            println(log_io, "\n[$i/$(length(repos))] Processing $repo...")

            repo_url = "https://github.com/$org/$repo.git"

            success, message, pr_url = format_repository(
                repo_url;
                test = test,
                push_to_master = push_to_master,
                create_pr = create_pr,
                fork_user = fork_user,
                working_dir = working_dir
            )

            if success
                push!(successes, repo)
                if pr_url !== nothing
                    push!(pr_urls, pr_url)
                    @info "✓ SUCCESS: $repo - $message" pr=pr_url
                    println(log_io, "✓ SUCCESS: $message")
                    println(log_io, "  PR: $pr_url")
                else
                    @info "✓ SUCCESS: $repo - $message"
                    println(log_io, "✓ SUCCESS: $message")
                end
            else
                push!(failures, repo)
                @error "✗ FAILED: $repo - $message"
                println(log_io, "✗ FAILED: $message")
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

    rm(working_dir; force = true, recursive = true)

    @info "Organization formatting complete" successes=length(successes) failures=length(
        failures,
    ) prs=length(pr_urls)

    return (successes, failures, pr_urls)
end

"""
    get_org_repositories(org::String, limit::Int = 100)

Get all Julia repositories from a GitHub organization.
"""
function get_org_repositories(org::String, limit::Int = 100)
    try
        cmd = `gh repo list $org --limit $limit --json name,isArchived --jq '.[] | select(.isArchived == false and (.name | endswith(".jl"))) | .name'`
        output = read(cmd, String)
        repos = filter(!isempty, split(strip(output), '\n'))
        return String.(repos)  # Convert to Vector{String}
    catch e
        @error "Failed to fetch repositories" exception=e
        return String[]
    end
end

"""
    has_failing_formatter_ci(org::String, repo::String)

Check if a repository has failing formatter CI.
"""
function has_failing_formatter_ci(org::String, repo::String)
    workflows = ["Format Check", "FormatCheck", "format-check"]
    branches = ["master", "main"]

    for workflow in workflows
        for branch in branches
            try
                # First get all runs for the workflow
                cmd = `gh run list --repo $org/$repo --workflow $workflow --limit 10 --json status,conclusion,headBranch`
                output = read(cmd, String)

                if !isempty(output)
                    # Check if any run on the target branch has failed
                    if occursin("\"headBranch\":\"$branch\"", output) && (
                        occursin("\"conclusion\":\"failure\"", output) ||
                        occursin("\"status\":\"failure\"", output)
                    )
                        return true
                    end
                end
            catch
                # Workflow might not exist
                continue
            end
        end
    end

    return false
end
