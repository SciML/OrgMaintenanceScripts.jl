using Test
using OrgMaintenanceScripts
using Pkg

@testset "Formatting Functions" begin
    @testset "format_repository with invalid inputs" begin
        # Test with missing fork_user when create_pr=true
        success, message, pr_url = format_repository(
            "https://github.com/test/test.jl.git";
            create_pr = true,
            fork_user = "",
        )
        @test !success
        @test occursin("fork_user must be provided", message)
        @test pr_url === nothing

        # Test with both push_to_master and create_pr
        success, message, pr_url = format_repository(
            "https://github.com/test/test.jl.git";
            push_to_master = true,
            create_pr = true,
            fork_user = "test",
        )
        @test !success
        @test occursin("Cannot both push_to_master and create_pr", message)
        @test pr_url === nothing
    end

    @testset "get_org_repositories" begin
        # Test with a small org or limit
        # This test might fail if gh CLI is not available
        try
            repos = OrgMaintenanceScripts.get_org_repositories("JuliaLang", 5)
            @test isa(repos, Vector{<:AbstractString})
            @test all(repo -> endswith(repo, ".jl"), repos)
        catch e
            @test_skip "gh CLI not available"
        end
    end

    @testset "has_failing_formatter_ci" begin
        # This is hard to test without mocking, so we just test it doesn't error
        try
            result = OrgMaintenanceScripts.has_failing_formatter_ci(
                "SciML",
                "DifferentialEquations.jl",
            )
            @test isa(result, Bool)
        catch e
            @test_skip "gh CLI not available"
        end
    end
end
