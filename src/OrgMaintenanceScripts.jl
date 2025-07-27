module OrgMaintenanceScripts

using Pkg
using TOML
using Dates

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

# Include explicit imports fixing functionality
include("explicit_imports_fixer.jl")

export bump_and_register_repo, bump_and_register_org
export format_repository, format_org_repositories
export update_manifests, update_project_tomls
export fix_package_min_versions, fix_repo_min_versions, fix_org_min_versions
export get_available_compat_updates, bump_compat_and_test, bump_compat_org_repositories
export find_version_checks_in_file, find_version_checks_in_repo, find_version_checks_in_org
export print_version_check_summary, VersionCheck
export fix_explicit_imports, fix_repo_explicit_imports, fix_org_explicit_imports

end # module OrgMaintenanceScripts