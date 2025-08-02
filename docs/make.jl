using OrgMaintenanceScripts
using Documenter

DocMeta.setdocmeta!(
    OrgMaintenanceScripts,
    :DocTestSetup,
    :(using OrgMaintenanceScripts);
    recursive = true
)

makedocs(;
    modules = [OrgMaintenanceScripts],
    authors = "SciML Contributors",
    repo = "https://github.com/SciML/OrgMaintenanceScripts.jl/blob/{commit}{path}#{line}",
    sitename = "OrgMaintenanceScripts.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://docs.sciml.ai/OrgMaintenanceScripts/stable/",
        edit_link = "main",
        assets = ["assets/favicon.ico"]
    ),
    pages = ["Home" => "index.md",
        "Formatting Maintenance" => "formatting.md",
        "Version Bumping" => "version_bumping.md",
        "Compat Bumping" => "compat_bumping.md",
        "Minimum Version Fixing" => "min_version_fixing.md",
        "Version Check Finder" => "version_check_finder.md",
        "Invalidation Analysis" => "invalidation_analysis.md",
        "Import Timing Analysis" => "import_timing_analysis.md",
        "Explicit Imports Fixing" => "explicit_imports_fixing.md",
        "Documentation Cleanup" => "documentation_cleanup.md",
        "Multiprocess Testing" => "multiprocess_testing.md"]
)

deploydocs(; repo = "github.com/SciML/OrgMaintenanceScripts.jl", devbranch = "main")
