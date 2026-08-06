using Dates
using OrgMaintenanceScripts
using Test

@testset "Public report values" begin
    check = VersionCheck("src/example.jl", 8, "VERSION < v\"1.10\"", v"1.10", "v\"1.10\"")
    @test check.file == "src/example.jl"
    @test check.version == v"1.10"

    invalidation = InvalidationEntry("f(::Int)", "src/f.jl", 12, "Demo", "method replaced", 2, 0)
    invalidation_report = InvalidationReport(
        "Demo.jl", 1, [invalidation], ["Demo"], DateTime(2026, 1, 1), "One invalidation", String[]
    )
    @test invalidation_report.major_invalidators == [invalidation]
    @test invalidation_report.total_invalidations == 1

    timing = ImportTiming("Demo", 0.25, 0.1, 0.15, ["Dates"], 1, true)
    timing_report = ImportTimingReport(
        "Demo.jl", "Demo", 0.25, [timing], ["Dates"], DateTime(2026, 1, 1),
        "Fast import", String[], ""
    )
    @test timing_report.major_contributors == [timing]
    @test timing_report.total_import_time == 0.25
end
