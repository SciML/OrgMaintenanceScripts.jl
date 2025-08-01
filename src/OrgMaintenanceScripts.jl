module OrgMaintenanceScripts

using Pkg
using TOML
using Dates

# Include project utilities for handling multiple Project.toml files
include("project_utils.jl")

# Include formatting functionality
include("formatting.jl")

# Include minimum version fixing functionality
include("min_version_fixer.jl")

# Include version bumping functionality
include("version_bumping.jl")

# Include compat bumping functionality
include("compat_bumper.jl")

# Include version check finding functionality
include("version_check_finder.jl")

# Include invalidation analysis functionality
include("invalidation_analysis.jl")

# Include import timing analysis functionality
include("import_timing_analysis.jl")

# Include explicit imports fixing functionality
include("explicit_imports_fixer.jl")

# Include multiprocess testing functionality
include("multiprocess_testing.jl")

export bump_and_register_repo, bump_and_register_org
export format_repository, format_org_repositories
export update_manifests, update_project_tomls, update_project_versions_all
export fix_package_min_versions, fix_repo_min_versions, fix_org_min_versions
export fix_package_min_versions_all
export get_available_compat_updates, bump_compat_and_test, bump_compat_org_repositories
export get_available_compat_updates_all, bump_compat_and_test_all
export find_version_checks_in_file, find_version_checks_in_repo, find_version_checks_in_org
export write_version_checks_to_script, write_org_version_checks_to_script
export fix_version_checks_parallel, fix_org_version_checks_parallel
export VersionCheck
export analyze_repo_invalidations, analyze_org_invalidations
export generate_invalidation_report, InvalidationReport, InvalidationEntry
export analyze_repo_import_timing, analyze_org_import_timing
export generate_import_timing_report, ImportTimingReport, ImportTiming
export print_version_check_summary
export fix_explicit_imports, fix_repo_explicit_imports, fix_org_explicit_imports
export run_explicit_imports_check_all
export find_all_project_tomls, get_project_info, is_subpackage, get_relative_project_path
export TestGroup, TestResult, TestSummary
export parse_ci_workflow, setup_test_environment, run_single_test_group
export run_multiprocess_tests, generate_test_summary_report, print_test_summary
export run_tests_from_repo

end # module OrgMaintenanceScripts
