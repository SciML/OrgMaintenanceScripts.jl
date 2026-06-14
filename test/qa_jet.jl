using OrgMaintenanceScripts
using Test
using JET
using Dates

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
                    # Test file with version checks
                    @static if VERSION >= v"1.6"
                        # Some code for Julia 1.6+
                    end
                    if VERSION < v"1.9"
                        # Some code for older Julia
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
        @test_opt OrgMaintenanceScripts.VersionCheck("test.jl", 1, "test line", v"1.0", "v\"1.0\"")
        @test_opt OrgMaintenanceScripts.InvalidationEntry("method", "file.jl", 1, "pkg", "reason", 0, 0)
        @test_opt OrgMaintenanceScripts.InvalidationReport(
            "repo", 0, OrgMaintenanceScripts.InvalidationEntry[], String[], Dates.now(), "summary", String[]
        )
    end

    @testset "Report functions" begin
        checks = OrgMaintenanceScripts.VersionCheck[]
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.print_version_check_summary(
            devnull, checks
        )

        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "output.jl")
            @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.write_version_checks_to_script(
                checks, output_file
            )
        end
    end
end
