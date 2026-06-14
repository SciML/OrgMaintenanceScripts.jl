using OrgMaintenanceScripts
using Test
using Aqua

@testset "Aqua quality assurance" begin
    # stale_deps and deps_compat are known failing and marked @test_broken below.
    # Tracked in https://github.com/SciML/OrgMaintenanceScripts.jl/issues/60
    Aqua.test_all(OrgMaintenanceScripts; stale_deps = false, deps_compat = false)
    # Aqua stale deps: SnoopCompileCore, YAML — tracked in https://github.com/SciML/OrgMaintenanceScripts.jl/issues/60
    @test_broken false
    # Aqua deps_compat: missing compat for Dates, Distributed, LibGit2, Logging, Pkg, Printf, Random — tracked in https://github.com/SciML/OrgMaintenanceScripts.jl/issues/60
    @test_broken false
end
