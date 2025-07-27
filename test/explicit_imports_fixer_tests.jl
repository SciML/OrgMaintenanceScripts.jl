using OrgMaintenanceScripts
using Test
using TOML

@testset "Explicit Imports Fixer" begin
    @testset "parse_explicit_imports_output" begin
        # Test parsing missing imports
        output = """
        === CHECKING MISSING EXPLICIT IMPORTS ===
        Base.println is not explicitly imported
        Test.@test is not explicitly imported
        """
        
        issues = OrgMaintenanceScripts.parse_explicit_imports_output(output)
        @test length(issues) == 2
        @test issues[1].type == :missing_import
        @test issues[1].module_name == "Base"
        @test issues[1].symbol == "println"
        
        # Test parsing unused imports
        output = """
        === CHECKING UNNECESSARY EXPLICIT IMPORTS ===
        unused_function is explicitly imported but not used
        another_unused is explicitly imported but not used
        """
        
        issues = OrgMaintenanceScripts.parse_explicit_imports_output(output)
        @test length(issues) == 2
        @test issues[1].type == :unused_import
        @test issues[1].symbol == "unused_function"
    end
    
    @testset "fix_missing_import" begin
        mktempdir() do tmpdir
            # Create a test file
            test_file = joinpath(tmpdir, "test.jl")
            write(test_file, """
            module TestModule
            
            function test_func()
                println("Hello")
            end
            
            end
            """)
            
            # Fix missing import
            success = OrgMaintenanceScripts.fix_missing_import(test_file, "Base", "println")
            @test success
            
            # Check the file was modified correctly
            content = read(test_file, String)
            @test occursin("using Base: println", content)
        end
    end
    
    @testset "fix_unused_import" begin
        mktempdir() do tmpdir
            # Create a test file with unused imports
            test_file = joinpath(tmpdir, "test.jl")
            write(test_file, """
            module TestModule
            
            using Base: println, push!, pop!
            using Test: @test
            
            function test_func()
                println("Hello")
                # push! and pop! are not used
            end
            
            end
            """)
            
            # Remove unused import
            success = OrgMaintenanceScripts.fix_unused_import(test_file, "push!")
            @test success
            
            # Check the file was modified correctly
            content = read(test_file, String)
            @test occursin("using Base: println, pop!", content) || occursin("using Base: pop!, println", content)
            @test !occursin("push!", content)
        end
    end
    
    @testset "Integration test with mock package" begin
        mktempdir() do tmpdir
            # Create a mock package
            pkg_dir = joinpath(tmpdir, "MockPackage")
            mkpath(joinpath(pkg_dir, "src"))
            
            # Create Project.toml
            project_toml = Dict(
                "name" => "MockPackage",
                "uuid" => "12345678-1234-1234-1234-123456789012",
                "version" => "0.1.0"
            )
            open(joinpath(pkg_dir, "Project.toml"), "w") do io
                TOML.print(io, project_toml)
            end
            
            # Create source file with import issues
            write(joinpath(pkg_dir, "src", "MockPackage.jl"), """
            module MockPackage
            
            using Base: push!  # This might be unused
            
            export greet
            
            function greet(name)
                println("Hello, \$name!")  # println not explicitly imported
                return nothing
            end
            
            end
            """)
            
            # Note: We can't fully test the fix_explicit_imports function here
            # because it requires ExplicitImports.jl to be installed and working
            # This would be tested in integration tests
            
            # Test that helper functions work with the mock package
            @test isdir(pkg_dir)
            @test isfile(joinpath(pkg_dir, "Project.toml"))
            @test isfile(joinpath(pkg_dir, "src", "MockPackage.jl"))
        end
    end
end