# Multiprocess Testing

The multiprocess testing functionality allows you to run tests in parallel similar to GitHub Actions CI workflows, but locally. This is particularly useful for large Julia packages with multiple test groups that can benefit from parallel execution.

## Overview

This module provides the ability to:

- Parse GitHub Actions CI workflow files to extract test groups
- Run multiple test groups in parallel using Julia's `Distributed` module
- Generate comprehensive logs for each test group
- Provide detailed summaries of test results
- Handle continue-on-error scenarios like GitHub Actions

## Key Functions

### `parse_ci_workflow(workflow_file::String)`

Parses a GitHub Actions CI workflow YAML file to extract test groups.

```julia
test_groups = parse_ci_workflow(".github/workflows/CI.yml")
```

**Arguments:**
- `workflow_file::String`: Path to the CI workflow YAML file

**Returns:**
- `Vector{TestGroup}`: List of test groups found in the workflow

### `run_multiprocess_tests(workflow_file::String, project_path::String; log_dir::String="test_logs", max_workers::Int=4)`

Runs tests in parallel based on a CI workflow file.

```julia
summary = run_multiprocess_tests(".github/workflows/CI.yml", ".", log_dir="my_logs")
print_test_summary(summary)
```

**Arguments:**
- `workflow_file::String`: Path to the CI workflow YAML file
- `project_path::String`: Path to the project directory
- `log_dir::String`: Directory to write log files (default: "test_logs")
- `max_workers::Int`: Maximum number of worker processes (default: 4)

**Returns:**
- `TestSummary`: Summary of all test results

### `run_tests_from_repo(repo_url::String; kwargs...)`

Clones a repository and runs its tests using the CI workflow configuration.

```julia
summary = run_tests_from_repo("https://github.com/SciML/OrdinaryDiffEq.jl")
print_test_summary(summary)
```

**Arguments:**
- `repo_url::String`: GitHub repository URL
- `branch::String`: Git branch to checkout (default: "master")
- `workflow_path::String`: Path to CI workflow file (default: ".github/workflows/CI.yml")
- `log_dir::String`: Directory for log files (default: "test_logs")

**Returns:**
- `TestSummary`: Summary of test results

### `print_test_summary(summary::TestSummary)`

Prints a concise test summary to the console.

```julia
print_test_summary(summary)
```

### `generate_test_summary_report(summary::TestSummary, output_file::Union{String, Nothing}=nothing)`

Generates a comprehensive test summary report.

```julia
report = generate_test_summary_report(summary, "test_report.txt")
println(report)
```

## Data Structures

### `TestGroup`

Represents a single test group with its configuration.

**Fields:**
- `name::String`: Name of the test group (e.g., "InterfaceI")
- `env_vars::Dict{String, String}`: Environment variables to set during testing
- `continue_on_error::Bool`: Whether to continue if this group fails

### `TestResult` 

Represents the result of running a test group.

**Fields:**
- `group::TestGroup`: The test group that was run
- `success::Bool`: Whether the test group passed
- `duration::Float64`: Duration in seconds
- `log_file::String`: Path to the log file
- `error_message::Union{String, Nothing}`: Error message if failed
- `start_time::DateTime`: When the test started
- `end_time::DateTime`: When the test ended

### `TestSummary`

Summary of all test results.

**Fields:**
- `total_groups::Int`: Total number of test groups
- `passed_groups::Int`: Number of groups that passed
- `failed_groups::Int`: Number of groups that failed
- `total_duration::Float64`: Total duration in seconds
- `results::Vector{TestResult}`: Individual test results
- `start_time::DateTime`: Overall start time
- `end_time::DateTime`: Overall end time

## Usage Examples

### Basic Usage

```julia
using OrgMaintenanceScripts

# Run tests for a local package
summary = run_multiprocess_tests(".github/workflows/CI.yml", ".", log_dir="test_logs")
print_test_summary(summary)

# Generate detailed report
generate_test_summary_report(summary, "detailed_report.txt")
```

### Testing a Remote Repository

```julia
# Clone and test OrdinaryDiffEq.jl
summary = run_tests_from_repo("https://github.com/SciML/OrdinaryDiffEq.jl")
print_test_summary(summary)

# Check which groups failed
failed_groups = [r.group.name for r in summary.results if !r.success]
if !isempty(failed_groups)
    println("Failed groups: ", join(failed_groups, ", "))
end
```

### Parsing Test Groups

```julia
# Just parse the workflow to see what groups exist
test_groups = parse_ci_workflow(".github/workflows/CI.yml")
for group in test_groups
    println("Group: $(group.name)")
    println("  Environment: $(group.env_vars)")
    println("  Continue on error: $(group.continue_on_error)")
end
```

### Custom Configuration

```julia
# Run with custom settings
summary = run_multiprocess_tests(
    ".github/workflows/CI.yml",
    ".",
    log_dir="custom_logs",
    max_workers=8  # Use more workers for faster execution
)
```

## Example Output

```
============================================================
TEST SUMMARY
============================================================
Total: 37 | Passed: 35 | Failed: 2 | Success: 94.6%
Duration: 1847.32 seconds

Failed Groups:
  • Downstream (test_logs/Downstream.log)
  • ModelingToolkit (test_logs/ModelingToolkit.log)
============================================================
```

## CI Workflow Compatibility

The parser supports standard GitHub Actions CI workflow files with the following structure:

```yaml
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    continue-on-error: ${{ matrix.group == 'Downstream' }}
    strategy:
      fail-fast: false
      matrix:
        group:
          - InterfaceI
          - InterfaceII
          - OrdinaryDiffEqCore
          - Downstream
        version:
          - '1'
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
      - uses: julia-actions/julia-runtest@v1
        env:
          GROUP: ${{ matrix.group }}
```

Key features supported:
- Automatic extraction of test group names from the `matrix.group` section
- Recognition of `continue-on-error` expressions to identify groups that should not fail the overall test suite
- Setting of the `GROUP` environment variable for each test group

## Performance Considerations

- **Parallel Execution**: Tests run in parallel using `pmap()`, significantly reducing total execution time
- **Worker Management**: The system automatically adds worker processes as needed, up to the specified maximum
- **Memory Usage**: Each test group runs in its own process, preventing memory leaks from affecting other tests
- **Log Isolation**: Individual log files prevent output mixing between parallel test groups

## Troubleshooting

### Common Issues

1. **Missing CI Workflow File**: Ensure the workflow file exists at the specified path
2. **YAML Parsing Errors**: Verify the workflow file has valid YAML syntax
3. **Environment Setup**: Make sure the project has a valid `Project.toml` file
4. **Worker Process Limits**: Adjust `max_workers` based on available system resources

### Log Files

Each test group generates its own log file in the specified log directory:
- `test_logs/GroupName.log` - Contains all output from that specific test group
- Logs include timestamps, environment variables, and full test output
- Failed tests include error messages and stack traces

### Environment Variables

The system temporarily sets environment variables for each test group:
- `GROUP=<group_name>` - The primary variable used by most Julia test suites
- Additional variables can be configured in the `TestGroup` structure
- Variables are cleaned up after each test group completes

This functionality is particularly useful for large SciML packages like OrdinaryDiffEq.jl that have dozens of test groups and can benefit significantly from parallel execution.