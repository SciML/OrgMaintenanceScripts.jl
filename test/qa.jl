# QA group: Aqua.jl project-quality checks and JET.jl static analysis.
# Runs in the isolated test/qa environment (see test/qa/Project.toml), gated on
# GROUP == "QA" in runtests.jl.

using SafeTestsets

@safetestset "Aqua quality assurance" begin
    include("qa_aqua.jl")
end

@safetestset "JET static analysis" begin
    include("qa_jet.jl")
end
