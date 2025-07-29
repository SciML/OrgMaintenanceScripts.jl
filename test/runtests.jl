using OrgMaintenanceScripts
using Test
using TOML

@testset "OrgMaintenanceScripts.jl" begin
    @testset "Version bumping" begin
        # Test bump_minor_version
        @test OrgMaintenanceScripts.bump_minor_version("1.2.3") == "1.3.0"
        @test OrgMaintenanceScripts.bump_minor_version("0.1.0") == "0.2.0"
        @test OrgMaintenanceScripts.bump_minor_version("2.10.5") == "2.11.0"

        # Test invalid version format
        @test_throws ErrorException OrgMaintenanceScripts.bump_minor_version("1.2")
        @test_throws ErrorException OrgMaintenanceScripts.bump_minor_version("1.2.3.4")
    end

    @testset "Project file handling" begin
        # Create a temporary test project
        mktempdir() do tmpdir
            project_path = joinpath(tmpdir, "Project.toml")

            # Test with valid Project.toml
            project_data = Dict(
                "name" => "TestPackage",
                "uuid" => "12345678-1234-1234-1234-123456789012",
                "version" => "0.1.0"
            )

            open(project_path, "w") do io
                TOML.print(io, project_data)
            end

            result = OrgMaintenanceScripts.update_project_version(project_path)
            @test !isnothing(result)
            @test result[1] == "0.1.0"
            @test result[2] == "0.2.0"

            # Verify file was updated
            updated_project = TOML.parsefile(project_path)
            @test updated_project["version"] == "0.2.0"

            # Test with missing version field
            delete!(updated_project, "version")
            open(project_path, "w") do io
                TOML.print(io, updated_project)
            end

            result = OrgMaintenanceScripts.update_project_version(project_path)
            @test isnothing(result)

            # Test with non-existent file
            result = OrgMaintenanceScripts.update_project_version(joinpath(
                tmpdir, "nonexistent.toml"))
            @test isnothing(result)
        end
    end

    @testset "Repository processing" begin
        # Create a mock repository structure
        mktempdir() do tmpdir
            # Main Project.toml
            main_project = Dict(
                "name" => "MainPackage",
                "uuid" => "12345678-1234-1234-1234-123456789012",
                "version" => "1.0.0"
            )
            open(joinpath(tmpdir, "Project.toml"), "w") do io
                TOML.print(io, main_project)
            end

            # Create lib directory with subpackages
            lib_dir = joinpath(tmpdir, "lib")
            mkpath(lib_dir)

            for (i, pkg) in enumerate(["SubPkgA", "SubPkgB"])
                pkg_dir = joinpath(lib_dir, pkg)
                mkpath(pkg_dir)

                sub_project = Dict(
                    "name" => pkg,
                    "uuid" => "12345678-1234-1234-1234-12345678901$i",
                    "version" => "0.$i.0"
                )
                open(joinpath(pkg_dir, "Project.toml"), "w") do io
                    TOML.print(io, sub_project)
                end
            end

            # Initialize git repo
            cd(tmpdir) do
                run(`git init`)
                run(`git config user.name "Test User"`)
                run(`git config user.email "test@example.com"`)
                run(`git add .`)
                run(`git commit -m "Initial commit"`)
            end

            # Test bump_and_register_repo
            result = bump_and_register_repo(tmpdir)

            @test !isnothing(result)
            @test basename(tmpdir) in result.registered
            @test "SubPkgA" in result.registered
            @test "SubPkgB" in result.registered
            @test isempty(result.failed)

            # Verify versions were bumped
            main_updated = TOML.parsefile(joinpath(tmpdir, "Project.toml"))
            @test main_updated["version"] == "1.1.0"

            subA_updated = TOML.parsefile(joinpath(lib_dir, "SubPkgA", "Project.toml"))
            @test subA_updated["version"] == "0.2.0"

            subB_updated = TOML.parsefile(joinpath(lib_dir, "SubPkgB", "Project.toml"))
            @test subB_updated["version"] == "0.3.0"
        end
    end

    @testset "Basic functionality (legacy)" begin
        # Test deprecated functions still exist but warn
        @test_logs (:warn,) OrgMaintenanceScripts.update_manifests()
        @test_logs (:warn,) OrgMaintenanceScripts.update_project_tomls()
    end

    include("formatting_tests.jl")
    include("min_version_fixer_tests.jl")
    include("version_check_finder_tests.jl")
    include("invalidation_analysis_tests.jl")
    include("import_timing_analysis_tests.jl")
    include("explicit_imports_fixer_tests.jl")
end
