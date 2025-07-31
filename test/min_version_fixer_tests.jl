using Test
using OrgMaintenanceScripts
using TOML

@testset "Minimum Version Fixer Tests" begin
    # Test helper functions
    @testset "extract_min_version_from_compat" begin
        @test OrgMaintenanceScripts.extract_min_version_from_compat("1.2") == v"1.2.0"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("^1.2") == v"1.2.0"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("~1.2") == v"1.2.0"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("1.2.3") == v"1.2.3"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("1.2, 2") == v"1.2.0"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("1.2-1.5") == v"1.2.0"
        @test OrgMaintenanceScripts.extract_min_version_from_compat("") === nothing
    end

    @testset "is_outdated_compat" begin
        # Without being able to mock get_latest_version, we test the fallback behavior
        @test OrgMaintenanceScripts.is_outdated_compat("0.3", "UnknownPkg")
        @test OrgMaintenanceScripts.is_outdated_compat("0.4.2", "UnknownPkg")
        @test !OrgMaintenanceScripts.is_outdated_compat("0.5", "UnknownPkg")
        @test !OrgMaintenanceScripts.is_outdated_compat("1.0", "UnknownPkg")
        @test OrgMaintenanceScripts.is_outdated_compat("", "UnknownPkg")  # Empty compat is outdated
    end

    @testset "bump_compat_version" begin
        # Test the fallback behavior when get_latest_version returns nothing
        @test OrgMaintenanceScripts.bump_compat_version("0.3", "UnknownPkg") == "0.4"
        @test OrgMaintenanceScripts.bump_compat_version("0.5.2", "UnknownPkg") == "0.6"
        @test OrgMaintenanceScripts.bump_compat_version("1.2", "UnknownPkg") == "1.0"
        @test OrgMaintenanceScripts.bump_compat_version("2.5.3", "UnknownPkg") == "2.0"
    end

    @testset "update_compat!" begin
        # Test preserving upper bounds
        project = Dict("compat" => Dict{String, Any}(
            "PkgA" => "0.5, 1",
            "PkgB" => "0.3-0.5",
            "PkgC" => "^1.2",
            "PkgD" => "0.8"
        ))

        updates = Dict(
            "PkgA" => "0.7",
            "PkgB" => "0.4",
            "PkgC" => "1.5",
            "PkgD" => "1.0"
        )

        OrgMaintenanceScripts.update_compat!(project, updates)

        @test project["compat"]["PkgA"] == " 0.7, 1"  # Preserved upper bound
        @test project["compat"]["PkgB"] == "0.4-0.5"  # Preserved range
        @test project["compat"]["PkgC"] == "1.5"      # Simple replacement
        @test project["compat"]["PkgD"] == "1.0"      # Simple replacement
    end

    @testset "get_smart_min_version" begin
        # Test fallback behavior for packages
        @test OrgMaintenanceScripts.get_smart_min_version("UnknownPkg", "0.3") == "0.4"
        @test OrgMaintenanceScripts.get_smart_min_version("UnknownPkg", "1.2") == "1.0"

        # Note: We can't easily test registry lookups in unit tests without mocking
        # The function will try to get latest version from registry first,
        # then fall back to bump_compat_version
    end

    @testset "parse_resolution_errors" begin
        # Mock error output
        error_output = """
        ERROR: Unsatisfiable requirements detected for package RecursiveArrayTools [731186ca]:
         RecursiveArrayTools [731186ca] log:
         ├─possible versions are: 0.15.0-3.24.0 or uninstalled
         └─restricted to versions 2.0.0-2 by Project [deps], leaving only versions: 2.0.0-2.38.10
           └─Project [deps] depends on RecursiveArrayTools

        ERROR: Unsatisfiable requirements detected for package StaticArrays [90137ffa]:
         StaticArrays [90137ffa] log:
         ├─possible versions are: 0.0.1-1.9.2 or uninstalled
        """

        project_toml = Dict(
            "deps" => Dict(
            "RecursiveArrayTools" => "731186ca-5190-57fd-a4c3-8b3e5a648489",
            "StaticArrays" => "90137ffa-7385-5640-81b9-e52037218182",
            "SomeOtherPkg" => "12345678-1234-1234-1234-123456789012"
        )
        )

        problematic = OrgMaintenanceScripts.parse_resolution_errors(error_output, project_toml)

        @test "RecursiveArrayTools" in problematic
        @test "StaticArrays" in problematic
        @test !("SomeOtherPkg" in problematic)
    end
end
