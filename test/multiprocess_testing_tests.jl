using Test
using OrgMaintenanceScripts
using Dates
using YAML
using Pkg
using Distributed

@testset "Multiprocess Testing" begin

    @testset "TestGroup Construction" begin
        # Test basic construction
        group = TestGroup("TestGroup1")
        @test group.name == "TestGroup1"
        @test group.env_vars == Dict{String, String}()
        @test group.continue_on_error == false
        
        # Test with custom environment variables
        env_vars = Dict("GROUP" => "TestGroup1", "JULIA_NUM_THREADS" => "2")
        group = TestGroup("TestGroup1", env_vars=env_vars)
        @test group.env_vars == env_vars
        
        # Test continue on error
        group = TestGroup("TestGroup1", continue_on_error=true)
        @test group.continue_on_error == true
    end

    @testset "parse_ci_workflow" begin
        # Create a temporary CI workflow file for testing
        test_workflow = tempname() * ".yml"
        workflow_content = """
        name: CI
        on:
          push:
            branches: [master]
        jobs:
          test:
            runs-on: ubuntu-latest
            continue-on-error: \${{ matrix.group == 'Downstream' }}
            strategy:
              fail-fast: false
              matrix:
                group:
                  - InterfaceI
                  - InterfaceII
                  - Downstream
                  - OrdinaryDiffEqCore
                version:
                  - '1'
            steps:
              - uses: actions/checkout@v4
              - uses: julia-actions/setup-julia@v2
              - uses: julia-actions/julia-runtest@v1
                env:
                  GROUP: \${{ matrix.group }}
        """
        
        open(test_workflow, "w") do f
            write(f, workflow_content)
        end
        
        try
            groups = parse_ci_workflow(test_workflow)
            @test length(groups) == 4
            
            group_names = [g.name for g in groups]
            @test "InterfaceI" in group_names
            @test "InterfaceII" in group_names
            @test "Downstream" in group_names
            @test "OrdinaryDiffEqCore" in group_names
            
            # Check environment variables
            for group in groups
                @test haskey(group.env_vars, "GROUP")
                @test group.env_vars["GROUP"] == group.name
            end
            
            # Check continue-on-error logic
            downstream_group = first(g for g in groups if g.name == "Downstream")
            @test downstream_group.continue_on_error == true
            
            interface_group = first(g for g in groups if g.name == "InterfaceI")
            @test interface_group.continue_on_error == false
            
        finally
            rm(test_workflow)
        end
        
        # Test with non-existent file
        @test_throws ErrorException parse_ci_workflow("nonexistent.yml")
    end

    @testset "setup_test_environment" begin
        # Test with current directory (should work)
        current_dir = pwd()
        @test_nowarn setup_test_environment(current_dir)
        
        # Test with non-existent directory
        @test_throws ErrorException setup_test_environment("/nonexistent/path")
    end

    @testset "TestResult and TestSummary structures" begin
        # Create test data
        group = TestGroup("TestGroup1", env_vars=Dict("GROUP" => "TestGroup1"))
        start_time = now()
        end_time = start_time + Millisecond(5000)
        
        result = TestResult(
            group,
            true,  # success
            5.0,   # duration
            "test.log",
            nothing,  # no error
            start_time,
            end_time
        )
        
        @test result.group.name == "TestGroup1"
        @test result.success == true
        @test result.duration == 5.0
        @test result.log_file == "test.log"
        @test result.error_message === nothing
        
        # Test TestSummary
        results = [result]
        summary = TestSummary(1, 1, 0, 5.0, results, start_time, end_time)
        
        @test summary.total_groups == 1
        @test summary.passed_groups == 1
        @test summary.failed_groups == 0
        @test summary.total_duration == 5.0
        @test length(summary.results) == 1
    end

    @testset "generate_test_summary_report" begin
        # Create mock test results
        group1 = TestGroup("PassingGroup")
        group2 = TestGroup("FailingGroup")
        
        start_time = now()
        end_time = start_time + Millisecond(10000)
        
        result1 = TestResult(group1, true, 5.0, "passing.log", nothing, start_time, start_time + Millisecond(5000))
        result2 = TestResult(group2, false, 3.0, "failing.log", "Test failed", start_time + Millisecond(5000), end_time)
        
        summary = TestSummary(2, 1, 1, 8.0, [result1, result2], start_time, end_time)
        
        # Test report generation without file output
        report = generate_test_summary_report(summary)
        @test occursin("MULTIPROCESS TEST SUMMARY REPORT", report)
        @test occursin("Total Groups: 2", report)
        @test occursin("Passed: 1", report)
        @test occursin("Failed: 1", report)
        @test occursin("PassingGroup", report)
        @test occursin("FailingGroup", report)
        @test occursin("FAILED GROUPS SUMMARY", report)
        
        # Test report generation with file output
        temp_file = tempname() * ".txt"
        try
            report_from_file = generate_test_summary_report(summary, temp_file)
            @test isfile(temp_file)
            @test report == report_from_file
            
            file_content = read(temp_file, String)
            @test file_content == report
        finally
            isfile(temp_file) && rm(temp_file)
        end
    end

    @testset "print_test_summary" begin
        # Create mock summary
        group = TestGroup("TestGroup")
        result = TestResult(group, true, 5.0, "test.log", nothing, now(), now())
        summary = TestSummary(1, 1, 0, 5.0, [result], now(), now())
        
        # Capture output
        io = IOBuffer()
        redirect_stdout(io) do
            print_test_summary(summary)
        end
        output = String(take!(io))
        
        @test occursin("TEST SUMMARY", output)
        @test occursin("Total: 1", output)
        @test occursin("Passed: 1", output)
        @test occursin("Failed: 0", output)
        @test occursin("Success: 100.0%", output)
    end

    @testset "Integration with mock tests" begin
        # Create a temporary test project structure
        temp_dir = mktempdir()
        project_dir = joinpath(temp_dir, "TestPackage")
        mkdir(project_dir)
        
        # Create Project.toml
        project_toml = joinpath(project_dir, "Project.toml")
        open(project_toml, "w") do f
            write(f, """
            name = "TestPackage"
            uuid = "12345678-1234-1234-1234-123456789abc"
            version = "0.1.0"
            
            [deps]
            Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
            """)
        end
        
        # Create test directory and file
        test_dir = joinpath(project_dir, "test")
        mkdir(test_dir)
        
        test_file = joinpath(test_dir, "runtests.jl")
        open(test_file, "w") do f
            write(f, """
            using Test
            
            # Simple test that depends on GROUP environment variable
            group = get(ENV, "GROUP", "default")
            
            @testset "Test Group: \$group" begin
                if group == "FailingGroup"
                    @test false  # This will fail
                else
                    @test true   # This will pass
                end
            end
            """)
        end
        
        # Create a simple CI workflow
        github_dir = joinpath(project_dir, ".github", "workflows")
        mkpath(github_dir)
        
        ci_file = joinpath(github_dir, "CI.yml")
        open(ci_file, "w") do f
            write(f, """
            name: CI
            jobs:
              test:
                strategy:
                  matrix:
                    group:
                      - PassingGroup
                      - FailingGroup
            """)
        end
        
        try
            # Test parsing the workflow
            groups = parse_ci_workflow(ci_file)
            @test length(groups) == 2
            @test any(g -> g.name == "PassingGroup", groups)
            @test any(g -> g.name == "FailingGroup", groups)
            
            # Test setup_test_environment
            original_dir = pwd()
            try
                @test_nowarn setup_test_environment(project_dir)
                @test pwd() == project_dir
            finally
                cd(original_dir)
            end
            
        finally
            rm(temp_dir, recursive=true)
        end
    end

    @testset "Error handling" begin
        # Test parse_ci_workflow with malformed YAML
        bad_yaml = tempname() * ".yml"
        open(bad_yaml, "w") do f
            write(f, "invalid: yaml: content: [unclosed")
        end
        
        try
            @test_throws Exception parse_ci_workflow(bad_yaml)
        finally
            rm(bad_yaml)
        end
        
        # Test setup_test_environment with invalid path
        @test_throws ErrorException setup_test_environment("/completely/invalid/path")
    end

    @testset "TestGroup environment variable handling" begin
        group = TestGroup("TestEnv", env_vars=Dict("TEST_VAR" => "test_value"))
        
        # Simulate setting and cleaning environment variables
        original_env = copy(ENV)
        
        try
            # Set environment variables
            for (key, value) in group.env_vars
                ENV[key] = value
            end
            
            @test ENV["TEST_VAR"] == "test_value"
            
            # Clean up environment variables (simulate what run_single_test_group does)
            for key in keys(group.env_vars)
                delete!(ENV, key)
            end
            
            @test !haskey(ENV, "TEST_VAR")
            
        finally
            # Restore original environment
            empty!(ENV)
            merge!(ENV, original_env)
        end
    end

    @testset "Workflow parsing edge cases" begin
        # Test workflow with no groups
        empty_workflow = tempname() * ".yml"
        open(empty_workflow, "w") do f
            write(f, """
            name: CI
            jobs:
              test:
                runs-on: ubuntu-latest
            """)
        end
        
        try
            groups = parse_ci_workflow(empty_workflow)
            @test length(groups) == 0
        finally
            rm(empty_workflow)
        end
        
        # Test workflow with empty groups
        minimal_workflow = tempname() * ".yml"
        open(minimal_workflow, "w") do f
            write(f, """
            name: CI
            jobs:
              test:
                strategy:
                  matrix:
                    group: []
            """)
        end
        
        try
            groups = parse_ci_workflow(minimal_workflow)
            @test length(groups) == 0
        finally
            rm(minimal_workflow)
        end
    end

end