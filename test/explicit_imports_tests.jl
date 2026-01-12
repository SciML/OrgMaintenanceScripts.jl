# Test that OrgMaintenanceScripts maintains explicit import hygiene

using ExplicitImports: check_no_implicit_imports, check_no_stale_explicit_imports

@testset "Explicit Imports Hygiene" begin
    @testset "No implicit imports" begin
        @test check_no_implicit_imports(OrgMaintenanceScripts) === nothing
    end

    @testset "No stale explicit imports" begin
        @test check_no_stale_explicit_imports(OrgMaintenanceScripts) === nothing
    end
end
