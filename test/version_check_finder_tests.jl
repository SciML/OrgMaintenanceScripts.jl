using Test
using OrgMaintenanceScripts

@testset "Version Check Finder" begin
    @testset "parse_version_check" begin
        # Test various VERSION check patterns
        test_cases = [
            ("if VERSION >= v\"1.6\"", (v"1.6", ">=")),
            ("@static if VERSION > v\"1.10.0\"", (v"1.10.0", ">")),
            ("VERSION <= v\"1.8\"", (v"1.8", "<=")),
            ("if VERSION == v\"1.9\"", (v"1.9", "==")),
            ("VERSION >= v1.6", (v"1.6", ">=")),
            ("VERSION >= VersionNumber(\"1.7\")", (v"1.7", ">=")),
            ("# This is a comment about VERSION", nothing),
            ("version = \"1.0.0\"", nothing),
        ]
        
        for (line, expected) in test_cases
            result = OrgMaintenanceScripts.parse_version_check(line)
            @test result == expected
        end
    end
    
    @testset "find_version_checks_in_file" begin
        mktempdir() do tmpdir
            # Create a test Julia file with various version checks
            test_file = joinpath(tmpdir, "test.jl")
            
            content = """
            # Test file with version checks
            
            if VERSION >= v"1.6"
                # This is old and should be found
                println("Julia 1.6+")
            end
            
            @static if VERSION > v"1.8.0"
                # This is also old
                feature_18()
            end
            
            if VERSION >= v"1.10"
                # This is current LTS, should not be found by default
                modern_feature()
            end
            
            if VERSION >= v"1.11"
                # This is newer than LTS, should not be found
                new_feature()
            end
            
            # Not a version check
            version = "1.0.0"
            """
            
            open(test_file, "w") do io
                write(io, content)
            end
            
            # Test with default min_version (1.10)
            checks = find_version_checks_in_file(test_file)
            @test length(checks) == 2
            
            # Verify the checks found
            @test checks[1].line_number == 3
            @test checks[1].version == v"1.6"
            @test checks[1].operator == ">="
            @test contains(checks[1].line_content, "VERSION >= v\"1.6\"")
            
            @test checks[2].line_number == 8
            @test checks[2].version == v"1.8.0"
            @test checks[2].operator == ">"
            
            # Test with different min_version
            checks_17 = find_version_checks_in_file(test_file; min_version=v"1.7")
            @test length(checks_17) == 1  # Only 1.6 check should be found
            @test checks_17[1].version == v"1.6"
            
            # Test with very old min_version
            checks_old = find_version_checks_in_file(test_file; min_version=v"1.0")
            @test length(checks_old) == 0  # No checks should be found
        end
    end
    
    @testset "find_version_checks_in_repo" begin
        mktempdir() do tmpdir
            # Create a mock repository structure
            src_dir = joinpath(tmpdir, "src")
            test_dir = joinpath(tmpdir, "test")
            mkpath(src_dir)
            mkpath(test_dir)
            
            # Create main module file
            main_file = joinpath(src_dir, "MyPackage.jl")
            open(main_file, "w") do io
                write(io, """
                module MyPackage
                
                if VERSION >= v"1.5"
                    const OLD_FEATURE = true
                end
                
                if VERSION >= v"1.10"
                    const NEW_FEATURE = true
                end
                
                end # module
                """)
            end
            
            # Create test file
            test_file = joinpath(test_dir, "runtests.jl")
            open(test_file, "w") do io
                write(io, """
                using Test
                
                @static if VERSION >= v"1.6"
                    @testset "Old tests" begin
                        @test true
                    end
                end
                """)
            end
            
            # Create Project.toml
            project_file = joinpath(tmpdir, "Project.toml")
            open(project_file, "w") do io
                write(io, """
                name = "MyPackage"
                uuid = "12345678-1234-1234-1234-123456789012"
                version = "0.1.0"
                """)
            end
            
            # Find version checks
            checks = find_version_checks_in_repo(tmpdir)
            
            @test length(checks) == 2  # Two files with old version checks
            @test haskey(checks, "src/MyPackage.jl")
            @test haskey(checks, "test/runtests.jl")
            
            @test length(checks["src/MyPackage.jl"]) == 1
            @test checks["src/MyPackage.jl"][1].version == v"1.5"
            
            @test length(checks["test/runtests.jl"]) == 1
            @test checks["test/runtests.jl"][1].version == v"1.6"
        end
    end
    
    @testset "VersionCheck struct" begin
        # Test the VersionCheck struct
        check = VersionCheck(
            "src/file.jl",
            10,
            "if VERSION >= v\"1.6\"",
            v"1.6",
            ">="
        )
        
        @test check.file_path == "src/file.jl"
        @test check.line_number == 10
        @test check.line_content == "if VERSION >= v\"1.6\""
        @test check.version == v"1.6"
        @test check.operator == ">="
    end
    
    @testset "print_version_check_summary" begin
        # Test the summary printing function
        results = Dict{String,Any}(
            "Org/Repo1" => Dict{String,Vector{VersionCheck}}(
                "src/main.jl" => [
                    VersionCheck("src/main.jl", 5, "if VERSION >= v\"1.6\"", v"1.6", ">="),
                    VersionCheck("src/main.jl", 10, "if VERSION > v\"1.8\"", v"1.8", ">")
                ],
                "test/runtests.jl" => [
                    VersionCheck("test/runtests.jl", 3, "@static if VERSION >= v\"1.7\"", v"1.7", ">=")
                ]
            ),
            "Org/Repo2" => Dict{String,Vector{VersionCheck}}(
                "src/compat.jl" => [
                    VersionCheck("src/compat.jl", 1, "VERSION >= v\"1.5\" && true", v"1.5", ">=")
                ]
            )
        )
        
        # Capture output
        io = IOBuffer()
        print_version_check_summary(results; io=io)
        output = String(take!(io))
        
        # Check that summary contains expected information
        @test contains(output, "Old Version Checks Summary")
        @test contains(output, "Org/Repo1")
        @test contains(output, "Org/Repo2")
        @test contains(output, "src/main.jl")
        @test contains(output, "test/runtests.jl")
        @test contains(output, "src/compat.jl")
        @test contains(output, "Total repositories with old checks: 2")
        @test contains(output, "Total files with old checks: 3")
        @test contains(output, "Total old version checks: 4")
    end
end