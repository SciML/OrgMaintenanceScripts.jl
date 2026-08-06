using OrgMaintenanceScripts
using SciMLTesting
using Dates
using Test

# JSON3 1.x documents these entry points but does not declare them `public` on
# Julia 1.11. The owning package is outside SciML, so this exception is exact.
run_qa(
    OrgMaintenanceScripts;
    ei_kwargs = (;
        all_qualified_accesses_are_public = (; ignore = (:pretty, :read)),
    )
)

using JET

@testset "JET static analysis" begin
    @testset "Project utilities" begin
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_all_project_tomls(".")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.get_project_info("Project.toml")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.is_subpackage(".", ".")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.get_relative_project_path(".", ".")
    end

    @testset "Version check finder" begin
        mktempdir() do tmpdir
            test_file = joinpath(tmpdir, "test.jl")
            write(
                test_file, """
                    @static if VERSION >= v"1.6"
                    end
                    if VERSION < v"1.9"
                    end
                """
            )

            @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_version_checks_in_file(
                test_file
            )
        end

        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_version_checks_in_repo(".")
    end

    @testset "Version bumping functions" begin
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.bump_minor_version(
            "1.0.0"
        )
    end

    @testset "Struct constructors" begin
        @test_opt VersionCheck("test.jl", 1, "test line", v"1.0", "v\"1.0\"")
        @test_opt InvalidationEntry("method", "file.jl", 1, "pkg", "reason", 0, 0)
        @test_opt InvalidationReport(
            "repo", 0, InvalidationEntry[], String[], Dates.now(), "summary", String[]
        )
    end

    @testset "Report functions" begin
        checks = VersionCheck[]
        @test_opt target_modules = (OrgMaintenanceScripts,) print_version_check_summary(devnull, checks)

        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "output.jl")
            @test_opt target_modules = (OrgMaintenanceScripts,) write_version_checks_to_script(
                checks, output_file
            )
        end
    end
end
