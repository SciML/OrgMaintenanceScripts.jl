# JET.jl static analysis tests
# These tests verify type stability and catch potential runtime errors

using JET

@testset "JET static analysis" begin
    @testset "Project utilities" begin
        # Test type stability of project utility functions
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_all_project_tomls(".")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.get_project_info("Project.toml")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.is_subpackage(".", ".")
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.get_relative_project_path(".", ".")
    end

    @testset "Version check finder" begin
        # Create a temporary test file
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

            # Test that find_version_checks_in_file is type stable
            @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_version_checks_in_file(
                test_file
            )
        end

        # Test find_version_checks_in_repo with the current directory
        # Note: This may have some issues from dependencies, so we use target_modules
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.find_version_checks_in_repo(".")
    end

    @testset "Version bumping functions" begin
        # Test bump_minor_version type stability
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.bump_minor_version(
            "1.0.0")
    end

    @testset "Struct constructors" begin
        # Test that struct constructors are type stable
        @test_opt OrgMaintenanceScripts.VersionCheck("test.jl", 1, "test line", v"1.0", "v\"1.0\"")
        @test_opt OrgMaintenanceScripts.InvalidationEntry("method", "file.jl", 1, "pkg", "reason", 0, 0)
        @test_opt OrgMaintenanceScripts.InvalidationReport(
            "repo", 0, OrgMaintenanceScripts.InvalidationEntry[], String[], Dates.now(), "summary", String[]
        )
    end

    @testset "Report functions" begin
        # Test VersionCheck related functions
        checks = OrgMaintenanceScripts.VersionCheck[]
        # Test the IO method directly for type stability
        @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.print_version_check_summary(
            devnull, checks)

        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "output.jl")
            @test_opt target_modules = (OrgMaintenanceScripts,) OrgMaintenanceScripts.write_version_checks_to_script(
                checks, output_file
            )
        end
    end
end
