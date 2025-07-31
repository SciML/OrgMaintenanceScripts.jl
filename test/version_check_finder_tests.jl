using Test
using OrgMaintenanceScripts
using Dates

@testset "Version Check Finder Tests" begin
    # Create temporary test files
    test_dir = mktempdir()

    # Test file with various version checks
    test_file1 = joinpath(test_dir, "test1.jl")
    write(test_file1, """
    # Some Julia code with version checks

    if VERSION >= v"1.6"
        println("This is old")
    end

    @static if VERSION > v"1.8.0"
        use_new_feature()
    end

    if VERSION >= v"1.10"
        # This should not be detected as obsolete
        current_lts_feature()
    end

    VERSION <= v"1.9" && old_workaround()

    if VERSION == v"1.7"
        specific_version_hack()
    end

    if VERSION >= VersionNumber("1.5")
        ancient_code()
    end
    """)

    # Test file without version checks
    test_file2 = joinpath(test_dir, "test2.jl")
    write(test_file2, """
    # Clean code without version checks
    function foo()
        return 42
    end
    """)

    @testset "find_version_checks_in_file" begin
        # Test finding checks in file with version checks
        checks = find_version_checks_in_file(test_file1)
        @test length(checks) == 5  # Should find 5 obsolete version checks

        # Verify the detected versions
        versions = [check.version for check in checks]
        @test v"1.6" in versions
        @test v"1.8.0" in versions
        @test v"1.9" in versions
        @test v"1.7" in versions
        @test v"1.5" in versions

        # Test that v"1.10" is not detected (it's the current LTS)
        @test !(v"1.10" in versions)

        # Test file without version checks
        checks2 = find_version_checks_in_file(test_file2)
        @test isempty(checks2)

        # Test non-existent file
        checks3 = find_version_checks_in_file("nonexistent.jl")
        @test isempty(checks3)
    end

    @testset "find_version_checks_in_repo" begin
        # Create a mock repository structure
        src_dir = joinpath(test_dir, "src")
        mkdir(src_dir)

        # Add test file to src
        cp(test_file1, joinpath(src_dir, "module.jl"))

        # Test finding checks in repo
        checks = find_version_checks_in_repo(test_dir)
        @test length(checks) == 10  # Should find 5 checks in each of two files (test1.jl and src/module.jl)

        # Test with custom ignore dirs
        test_subdir = joinpath(test_dir, "test")
        mkdir(test_subdir)
        cp(test_file1, joinpath(test_subdir, "test_checks.jl"))

        # Should not find checks in test directory
        checks_ignored = find_version_checks_in_repo(test_dir; ignore_dirs = ["test"])
        @test length(checks_ignored) == 10  # Only from test1.jl and src/module.jl
    end

    @testset "write_version_checks_to_script" begin
        # Create some test checks
        test_checks = [
            OrgMaintenanceScripts.VersionCheck(
                "test.jl",
                10,
                "if VERSION >= v\"1.6\"",
                v"1.6",
                "VERSION >= v\"1.6\""
            ),
            OrgMaintenanceScripts.VersionCheck(
                "test2.jl",
                20,
                "@static if VERSION > v\"1.8.0\"",
                v"1.8.0",
                "VERSION > v\"1.8.0\""
            )
        ]

        # Write to script
        script_file = joinpath(test_dir, "fix_script.jl")
        write_version_checks_to_script(test_checks, script_file)

        # Verify script was created
        @test isfile(script_file)

        # Check script is executable
        @test (filemode(script_file) & 0o111) != 0

        # Verify content
        content = read(script_file, String)
        @test contains(content, "#!/usr/bin/env julia")
        @test contains(content, "Total checks found: 2")
        @test contains(content, "test.jl")
        @test contains(content, "test2.jl")
    end

    @testset "write_org_version_checks_to_script" begin
        # Create test data for organization
        org_results = Dict(
            "org/repo1" => [
                OrgMaintenanceScripts.VersionCheck(
                "src/main.jl",
                15,
                "VERSION >= v\"1.7\"",
                v"1.7",
                "VERSION >= v\"1.7\""
            )
            ],
            "org/repo2" => [
                OrgMaintenanceScripts.VersionCheck(
                    "lib/util.jl",
                    25,
                    "VERSION < v\"1.9\"",
                    v"1.9",
                    "VERSION < v\"1.9\""
                ),
                OrgMaintenanceScripts.VersionCheck(
                    "src/compat.jl",
                    30,
                    "VERSION == v\"1.8\"",
                    v"1.8",
                    "VERSION == v\"1.8\""
                )
            ]
        )

        # Write to script
        org_script = joinpath(test_dir, "fix_org_script.jl")
        write_org_version_checks_to_script(org_results, org_script)

        # Verify script
        @test isfile(org_script)
        @test (filemode(org_script) & 0o111) != 0

        content = read(org_script, String)
        @test contains(content, "Total repositories with checks: 2")
        @test contains(content, "Total checks found: 3")
        @test contains(content, "org/repo1")
        @test contains(content, "org/repo2")
    end

    # Clean up
    rm(test_dir; recursive = true)
end
