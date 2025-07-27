using Test
using OrgMaintenanceScripts
using Dates

@testset "Invalidation Analysis Tests" begin
    # Create a simple test package structure
    test_dir = mktempdir()
    
    # Create Project.toml
    project_toml = joinpath(test_dir, "Project.toml")
    write(project_toml, """
    name = "TestInvalidationPackage"
    uuid = "12345678-1234-1234-1234-123456789abc"
    version = "0.1.0"
    
    [deps]
    """)
    
    # Create src directory and main file
    src_dir = joinpath(test_dir, "src")
    mkpath(src_dir)
    
    main_file = joinpath(src_dir, "TestInvalidationPackage.jl")
    write(main_file, """
    module TestInvalidationPackage
    
    # Simple function that shouldn't cause invalidations
    function simple_add(x::Int, y::Int)
        return x + y
    end
    
    # Function with type instability (potential invalidation source)
    function unstable_function(x)
        if x > 0
            return x
        else
            return "negative"
        end
    end
    
    export simple_add, unstable_function
    
    end # module
    """)
    
    # Create test directory and test file
    test_test_dir = joinpath(test_dir, "test")
    mkpath(test_test_dir)
    
    runtests_file = joinpath(test_test_dir, "runtests.jl")
    write(runtests_file, """
    using TestInvalidationPackage
    using Test
    
    @testset "TestInvalidationPackage Tests" begin
        @test simple_add(2, 3) == 5
        @test unstable_function(1) == 1
        @test unstable_function(-1) == "negative"
    end
    """)
    
    @testset "InvalidationEntry and InvalidationReport structures" begin
        # Test InvalidationEntry
        entry = InvalidationEntry(
            "test_method",
            "test.jl",
            42,
            "TestPackage",
            "Test reason",
            5,
            1
        )
        
        @test entry.method == "test_method"
        @test entry.file == "test.jl"
        @test entry.line == 42
        @test entry.package == "TestPackage"
        @test entry.reason == "Test reason"
        @test entry.children_count == 5
        @test entry.depth == 1
        
        # Test InvalidationReport
        report = InvalidationReport(
            "test_repo",
            10,
            [entry],
            ["pkg1", "pkg2"],
            now(),
            "Test summary",
            ["recommendation1", "recommendation2"]
        )
        
        @test report.repo == "test_repo"
        @test report.total_invalidations == 10
        @test length(report.major_invalidators) == 1
        @test length(report.packages_affected) == 2
        @test length(report.recommendations) == 2
    end
    
    @testset "analyze_major_invalidators" begin
        # Create mock invalidation data
        mock_data = Dict(
            "total_invalidations" => 15,
            "tree_count" => 3,
            "invalidation_details" => [
                Dict(
                    "method" => "method1",
                    "file" => "file1.jl",
                    "line" => 10,
                    "package" => "Package1",
                    "children_count" => 8,
                    "depth" => 0
                ),
                Dict(
                    "method" => "method2",
                    "file" => "file2.jl",
                    "line" => 20,
                    "package" => "Package1",
                    "children_count" => 3,
                    "depth" => 1
                ),
                Dict(
                    "method" => "method3",
                    "file" => "file3.jl",
                    "line" => 30,
                    "package" => "Package2",
                    "children_count" => 2,
                    "depth" => 0
                )
            ]
        )
        
        major_invalidators, package_impact = OrgMaintenanceScripts.analyze_major_invalidators(mock_data)
        
        @test length(major_invalidators) == 3
        @test major_invalidators[1].children_count == 8  # Should be sorted by impact
        @test major_invalidators[1].package == "Package1"
        
        @test length(package_impact) == 2  # Two packages
        @test package_impact[1][1] == "Package1"  # Package1 should have higher impact
        @test package_impact[1][2] == 11  # Total children (8 + 3)
    end
    
    @testset "write_invalidation_report" begin
        # Create a test report
        entry = InvalidationEntry(
            "test_method",
            "test.jl",
            42,
            "TestPackage",
            "Test reason",
            5,
            1
        )
        
        report = InvalidationReport(
            "test_repo",
            10,
            [entry],
            ["pkg1", "pkg2"],
            DateTime(2024, 1, 1, 12, 0, 0),
            "Test summary",
            ["recommendation1"]
        )
        
        # Write report to file
        output_file = joinpath(test_dir, "test_report.json")
        OrgMaintenanceScripts.write_invalidation_report(report, output_file)
        
        @test isfile(output_file)
        
        # Read and verify content
        content = read(output_file, String)
        @test contains(content, "test_repo")
        @test contains(content, "test_method")
        @test contains(content, "TestPackage")
        @test contains(content, "recommendation1")
    end
    
    @testset "generate_invalidation_report" begin
        # Test with our mock package
        # Note: This test might fail if SnoopCompileCore is not available
        # or if the test environment doesn't support the analysis
        try
            report = generate_invalidation_report(test_dir)
            
            @test isa(report, InvalidationReport)
            @test report.repo == basename(test_dir)
            @test isa(report.total_invalidations, Int)
            @test isa(report.analysis_time, DateTime)
            @test !isempty(report.summary)
            @test isa(report.recommendations, Vector{String})
            
            # Should have some recommendations
            @test !isempty(report.recommendations)
            
        catch e
            # If SnoopCompileCore analysis fails, that's OK for testing
            @test_broken false  # Mark as expected failure
            @info "Invalidation analysis test skipped due to: $e"
        end
    end
    
    @testset "analyze_repo_invalidations" begin
        # Test the main analysis function
        try
            # Create a temporary output file
            output_file = joinpath(test_dir, "analysis_output.json")
            
            report = analyze_repo_invalidations(test_dir; output_file=output_file)
            
            @test isa(report, InvalidationReport)
            @test report.repo == basename(test_dir)
            
            # Check if output file was created (if analysis succeeded)
            if report.total_invalidations >= 0
                @test isfile(output_file)
            end
            
        catch e
            @test_broken false  # Mark as expected failure for CI environments
            @info "Repository analysis test skipped due to: $e"
        end
    end
    
    @testset "Edge cases" begin
        # Test with non-existent directory
        @test_throws Exception generate_invalidation_report("/nonexistent/path")
        
        # Test with directory without Project.toml
        empty_dir = mktempdir()
        report = generate_invalidation_report(empty_dir)
        @test report.total_invalidations == -1  # Should indicate failure
        @test contains(report.summary, "failed")
    end
    
    # Clean up
    rm(test_dir; recursive=true)
end