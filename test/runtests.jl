using OrgMaintenanceScripts
using Test

@testset "OrgMaintenanceScripts.jl" begin
    @testset "Basic functionality" begin
        @test_nowarn update_manifests()
        @test_nowarn update_project_tomls()
    end
end