# Formatting Maintenance

The OrgMaintenanceScripts package provides automated formatting functionality to maintain consistent code style across SciML repositories using JuliaFormatter.

## Functions

### `format_repository`

Format a single repository with JuliaFormatter.

```julia
format_repository(repo_url::String;
    test::Bool = true,
    push_to_master::Bool = false,
    create_pr::Bool = true,
    fork_user::String = "",
    working_dir::String = mktempdir())
```

#### Arguments

  - `repo_url`: URL of the repository to format (e.g., "https://github.com/SciML/Example.jl.git")
  - `test`: Whether to run tests after formatting (default: true)
  - `push_to_master`: Whether to push directly to master/main if tests pass (default: false)
  - `create_pr`: Whether to create a PR instead of pushing to master (default: true)
  - `fork_user`: GitHub username for creating PRs (required if create_pr=true)
  - `working_dir`: Directory to clone the repository into (default: temporary directory)

#### Returns

  - `(success::Bool, message::String, pr_url::Union{String,Nothing})`

#### Example

```julia
# Format a repository and create a PR
success, message, pr_url = format_repository(
    "https://github.com/SciML/Example.jl.git";
    test = true,
    create_pr = true,
    fork_user = "myusername"
)

if success
    println("PR created: $pr_url")
else
    println("Failed: $message")
end
```

### `format_org_repositories`

Format all repositories in a GitHub organization.

```julia
format_org_repositories(org::String = "SciML";
    test::Bool = true,
    push_to_master::Bool = false,
    create_pr::Bool = true,
    fork_user::String = "",
    limit::Int = 100,
    only_failing_ci::Bool = true,
    log_file::String = "")
```

#### Arguments

  - `org`: GitHub organization name (default: "SciML")
  - `test`: Whether to run tests after formatting (default: true)
  - `push_to_master`: Whether to push directly to master/main if tests pass (default: false)
  - `create_pr`: Whether to create PRs instead of pushing to master (default: true)
  - `fork_user`: GitHub username for creating PRs (required if create_pr=true)
  - `limit`: Maximum number of repositories to process (default: 100)
  - `only_failing_ci`: Only process repos with failing formatter CI (default: true)
  - `log_file`: Path to save results log (default: auto-generated)

#### Returns

  - `(successes::Vector{String}, failures::Vector{String}, pr_urls::Vector{String})`

#### Example

```julia
# Format all SciML repos with failing formatter CI
successes, failures, pr_urls = format_org_repositories(
    "SciML";
    test = false,  # Skip tests for speed
    create_pr = true,
    fork_user = "myusername",
    only_failing_ci = true
)

println("Successfully formatted: $(length(successes)) repositories")
println("Failed: $(length(failures)) repositories")
println("Created $(length(pr_urls)) pull requests")
```

## Usage Scenarios

### 1. Regular Maintenance (Recommended)

Create PRs for repositories with failing formatter CI:

```julia
using OrgMaintenanceScripts

# Format repos with failing CI and create PRs
successes, failures, pr_urls = format_org_repositories(
    "SciML";
    fork_user = "sciml-bot",
    only_failing_ci = true,
    test = false  # Tests will run in CI
)
```

### 2. Direct Push to Master (Use with Caution)

For trusted automation that pushes directly to master after tests pass:

```julia
# Only push if tests pass
successes, failures, _ = format_org_repositories(
    "SciML";
    push_to_master = true,
    test = true,  # Must pass tests
    create_pr = false
)
```

### 3. Single Repository

Format a specific repository:

```julia
success, message, pr_url = format_repository(
    "https://github.com/SciML/DifferentialEquations.jl.git";
    fork_user = "myusername"
)
```

## Prerequisites

 1. **GitHub CLI**: The `gh` command-line tool must be installed and authenticated
 2. **Git**: Git must be configured with appropriate credentials
 3. **Julia**: Julia 1.6 or higher
 4. **Fork Access**: If creating PRs, you need fork access to the repositories

## Notes

  - The formatter uses the SciML style guide by default
  - If a repository doesn't have a `.JuliaFormatter.toml` file, one will be created
  - Tests are run with a 10-minute timeout by default
  - Rate limiting delays are included to avoid GitHub API limits
  - All operations are logged for audit purposes
