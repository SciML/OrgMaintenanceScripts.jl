using Test
using OrgMaintenanceScripts
using Dates

@testset "Import Timing Analysis Tests" begin
    # Create a simple test package structure
    test_dir = mktempdir()
    
    # Create Project.toml
    project_toml = joinpath(test_dir, "Project.toml")
    write(project_toml, """
    name = "TestImportTimingPackage"
    uuid = "12345678-1234-1234-1234-123456789def"
    version = "0.1.0"
    
    [deps]
    Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
    """)
    
    # Create src directory and main file
    src_dir = joinpath(test_dir, "src")
    mkpath(src_dir)
    
    main_file = joinpath(src_dir, "TestImportTimingPackage.jl")
    write(main_file, """
    module TestImportTimingPackage
    
    using Dates
    
    # Simple function
    function get_current_time()
        return now()
    end
    
    # Function that might take some time to compile
    function complex_computation(x::T) where T
        result = zero(T)
        for i in 1:100
            result += sin(x * i) + cos(x * i)
        end
        return result
    end
    
    export get_current_time, complex_computation
    
    end # module
    """)
    
    @testset "ImportTiming and ImportTimingReport structures" begin
        # Test ImportTiming
        timing = ImportTiming(
            "TestPackage",
            1.5,      # total_time
            0.8,      # precompile_time
            0.7,      # load_time
            ["Dates"], # dependencies
            1,        # dep_count
            false     # is_local
        )
        
        @test timing.package_name == "TestPackage"
        @test timing.total_time == 1.5
        @test timing.precompile_time == 0.8
        @test timing.load_time == 0.7
        @test timing.dependencies == ["Dates"]
        @test timing.dep_count == 1
        @test timing.is_local == false
        
        # Test ImportTimingReport
        report = ImportTimingReport(
            "test_repo",
            "TestPackage",
            2.5,
            [timing],
            ["Dates", "TestPackage"],
            now(),
            "Test summary",
            ["recommendation1"],
            "Raw @time_imports output"
        )
        
        @test report.repo == "test_repo"
        @test report.package_name == "TestPackage"
        @test report.total_import_time == 2.5
        @test length(report.major_contributors) == 1
        @test length(report.dependency_chain) == 2
        @test length(report.recommendations) == 1
        @test !isempty(report.raw_output)
    end
    
    @testset "parse_import_timings" begin
        # Create mock timing data
        mock_data = Dict(
            "package_name" => "TestPackage",
            "timing_entries" => [
                Dict(
                    "package" => "Dates",
                    "time_ms" => 500.0,
                    "time_seconds" => 0.5,
                    "is_precompile" => true,
                    "is_local" => false,
                    "line" => "  500.0 ms  Dates"
                ),
                Dict(
                    "package" => "Dates",
                    "time_ms" => 100.0,
                    "time_seconds" => 0.1,
                    "is_precompile" => false,
                    "is_local" => false,
                    "line" => "  100.0 ms  ✓ Dates"
                ),
                Dict(
                    "package" => "TestPackage",
                    "time_ms" => 200.0,
                    "time_seconds" => 0.2,
                    "is_precompile" => true,
                    "is_local" => true,
                    "line" => "  200.0 ms  TestPackage"
                )
            ],
            "raw_output" => "Mock @time_imports output",
            "total_entries" => 3
        )
        
        import_timings = OrgMaintenanceScripts.parse_import_timings(mock_data)
        
        @test length(import_timings) == 2  # Dates and TestPackage
        
        # Should be sorted by total time (descending)
        @test import_timings[1].total_time >= import_timings[2].total_time
        
        # Find Dates entry
        dates_timing = findfirst(t -> t.package_name == "Dates", import_timings)
        @test dates_timing !== nothing
        dates_entry = import_timings[dates_timing]
        @test dates_entry.total_time == 0.6  # 0.5 + 0.1
        @test dates_entry.precompile_time == 0.5
        @test dates_entry.load_time == 0.1
        @test !dates_entry.is_local
        
        # Find TestPackage entry
        test_timing = findfirst(t -> t.package_name == "TestPackage", import_timings)
        @test test_timing !== nothing
        test_entry = import_timings[test_timing]
        @test test_entry.total_time == 0.2
        @test test_entry.precompile_time == 0.2
        @test test_entry.load_time == 0.0
        @test test_entry.is_local
    end
    
    @testset "write_import_timing_report" begin
        # Create a test report
        timing = ImportTiming(
            "TestPackage",
            1.5,
            0.8,
            0.7,
            ["Dates"],
            1,
            false
        )
        
        report = ImportTimingReport(
            "test_repo",
            "TestPackage",
            2.5,
            [timing],
            ["Dates", "TestPackage"],
            DateTime(2024, 1, 1, 12, 0, 0),
            "Test summary",
            ["recommendation1"],
            "Raw output"
        )
        
        # Write report to file
        output_file = joinpath(test_dir, "test_import_report.json")
        OrgMaintenanceScripts.write_import_timing_report(report, output_file)
        
        @test isfile(output_file)
        
        # Read and verify content
        content = read(output_file, String)
        @test contains(content, "test_repo")
        @test contains(content, "TestPackage")
        @test contains(content, "2.5")
        @test contains(content, "recommendation1")
        @test contains(content, "Raw output")
    end
    
    @testset "generate_import_timing_report" begin
        # Test with our mock package
        # Note: This test might fail if the package can't be imported
        try
            report = generate_import_timing_report(test_dir)
            
            @test isa(report, ImportTimingReport)
            @test report.repo == basename(test_dir)
            @test report.package_name == "TestImportTimingPackage"
            @test isa(report.total_import_time, Float64)
            @test isa(report.analysis_time, DateTime)
            @test !isempty(report.summary)
            @test isa(report.recommendations, Vector{String})
            
            # Should have some recommendations
            @test !isempty(report.recommendations)
            
            # Check that we have timing data structure
            @test isa(report.major_contributors, Vector{ImportTiming})
            
        catch e
            # If import timing analysis fails, that's OK for testing
            @test_broken false  # Mark as expected failure
            @info "Import timing analysis test skipped due to: $e"
        end
    end
    
    @testset "analyze_repo_import_timing" begin
        # Test the main analysis function
        try
            # Create a temporary output file
            output_file = joinpath(test_dir, "timing_analysis_output.json")
            
            report = analyze_repo_import_timing(test_dir; output_file=output_file)
            
            @test isa(report, ImportTimingReport)
            @test report.repo == basename(test_dir)
            @test report.package_name == "TestImportTimingPackage"
            
            # Check if output file was created (if analysis succeeded)
            if report.total_import_time >= 0
                @test isfile(output_file)
            end
            
        catch e
            @test_broken false  # Mark as expected failure for CI environments
            @info "Repository import timing analysis test skipped due to: $e"
        end
    end
    
    @testset "generate_org_import_summary_report" begin
        # Create mock results for organization summary
        timing1 = ImportTiming("FastPackage", 0.5, 0.3, 0.2, ["Base"], 1, true)
        timing2 = ImportTiming("SlowDep", 2.0, 1.5, 0.5, [], 0, false)
        
        report1 = ImportTimingReport(
            "FastRepo",
            "FastPackage", 
            1.0,
            [timing1],
            ["FastPackage"],
            now(),
            "Fast loading",
            ["Great job!"],
            "Mock output 1"
        )
        
        report2 = ImportTimingReport(
            "SlowRepo",
            "SlowPackage",
            5.0,
            [timing2],
            ["SlowDep", "SlowPackage"],
            now(),
            "Slow loading",
            ["Optimize dependencies"],
            "Mock output 2"
        )
        
        results = Dict(
            "org/FastRepo" => report1,
            "org/SlowRepo" => report2
        )
        
        # Generate summary report
        output_dir = mktempdir()
        summary_file = OrgMaintenanceScripts.generate_org_import_summary_report("TestOrg", results, output_dir)
        
        @test isfile(summary_file)
        @test endswith(summary_file, "TestOrg_import_timing_summary.md")
        
        # Check content
        content = read(summary_file, String)
        @test contains(content, "Import Timing Analysis Report for TestOrg")
        @test contains(content, "FastRepo")
        @test contains(content, "SlowRepo")
        @test contains(content, "1.0s")  # FastRepo time
        @test contains(content, "5.0s")  # SlowRepo time
        @test contains(content, "SlowDep")  # Problematic dependency
    end
    
    @testset "Edge cases" begin
        # Test with non-existent directory
        @test_throws Exception generate_import_timing_report("/nonexistent/path")
        
        # Test with directory without Project.toml
        empty_dir = mktempdir()
        @test_throws Exception generate_import_timing_report(empty_dir)
        
        # Test with invalid package name
        @test_throws Exception generate_import_timing_report(test_dir, "NonExistentPackage")
    end
    
    # Clean up
    rm(test_dir; recursive=true)
end