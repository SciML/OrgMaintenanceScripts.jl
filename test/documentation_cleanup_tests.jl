using Test
using OrgMaintenanceScripts

@testset "Documentation Cleanup Tests" begin
    
    @testset "Input Validation" begin
        # Test invalid repository path
        @test_throws ArgumentError cleanup_gh_pages_docs("/nonexistent/path")
        
        # Test non-git directory
        mktempdir() do tmpdir
            @test_throws ArgumentError cleanup_gh_pages_docs(tmpdir)
        end
    end
    
    @testset "Mock Repository Tests" begin
        # Create a mock git repository for testing
        mktempdir() do tmpdir
            cd(tmpdir) do
                # Initialize git repo
                run(`git init`)
                run(`git config user.email "test@example.com"`)
                run(`git config user.name "Test User"`)
                
                # Create main branch with initial commit
                write("README.md", "# Test Repository")
                run(`git add README.md`)
                run(`git commit -m "Initial commit"`)
                
                @testset "No gh-pages Branch" begin
                    # Test with repository that has no gh-pages branch
                    result = cleanup_gh_pages_docs(tmpdir, dry_run=true)
                    @test result.success == true
                    @test result.files_removed == 0
                end
                
                @testset "With gh-pages Branch" begin
                    # Create gh-pages branch with mock documentation
                    run(`git checkout --orphan gh-pages`)
                    
                    # Create mock version directories
                    mkdir("v1.0.0")
                    mkdir("v1.1.0") 
                    mkdir("v2.0.0")
                    mkdir("dev")
                    mkdir("previews")
                    
                    # Create mock files in version directories
                    write("v1.0.0/index.html", "Old version 1.0.0 docs")
                    write("v1.1.0/index.html", "Old version 1.1.0 docs")  
                    write("v2.0.0/index.html", "Latest version 2.0.0 docs")
                    write("dev/index.html", "Development docs")
                    write("previews/index.html", "Preview docs")
                    
                    # Create a large mock file
                    large_content = repeat("X", 6 * 1024 * 1024)  # 6MB file
                    write("v1.0.0/large_plot.svg", large_content)
                    
                    run(`git add .`)
                    run(`git commit -m "Add mock documentation"`)
                    
                    @testset "Dry Run Mode" begin
                        result = cleanup_gh_pages_docs(tmpdir, dry_run=true)
                        
                        @test result.success == true  
                        @test result.dirs_removed >= 2  # Should identify dev, previews, old versions
                        
                        # Files should still exist after dry run
                        @test isdir("v1.0.0")
                        @test isdir("dev")
                        @test isfile("v1.0.0/large_plot.svg")
                    end
                    
                    @testset "Preserve Latest Version" begin
                        result = cleanup_gh_pages_docs(tmpdir, preserve_latest=true)
                        
                        @test result.success == true
                        @test result.preserved_version == "v2.0.0"
                        @test "v1.0.0" in result.versions_cleaned
                        @test "v1.1.0" in result.versions_cleaned
                        @test !("v2.0.0" in result.versions_cleaned)
                        
                        # Latest version should still exist
                        @test isdir("v2.0.0")
                        @test isfile("v2.0.0/index.html")
                        
                        # Old versions should be removed
                        @test !isdir("v1.0.0")
                        @test !isdir("v1.1.0")
                        @test !isdir("dev")
                        @test !isdir("previews")
                    end
                end
            end
        end
    end
    
    @testset "Analysis Function" begin
        mktempdir() do tmpdir
            cd(tmpdir) do
                # Initialize git repo
                run(`git init`)
                run(`git config user.email "test@example.com"`)
                run(`git config user.name "Test User"`)
                
                write("README.md", "# Test")
                run(`git add README.md`)
                run(`git commit -m "Initial commit"`)
                
                # Test analysis with no gh-pages
                analysis = analyze_gh_pages_bloat(tmpdir)
                @test analysis.total_size_mb == 0.0
                @test isempty(analysis.large_files)
                @test analysis.analysis == "No gh-pages branch"
                
                # Create gh-pages with content
                run(`git checkout --orphan gh-pages`)
                mkdir("v1.0.0")
                write("v1.0.0/small.html", "small file")
                write("v1.0.0/large.html", repeat("X", 2 * 1024 * 1024))  # 2MB
                
                run(`git add .`)
                run(`git commit -m "Add docs"`)
                
                analysis = analyze_gh_pages_bloat(tmpdir)
                @test analysis.total_size_mb > 0
                @test !isempty(analysis.versions)
                @test analysis.latest_version == "v1.0.0"
                @test contains(analysis.analysis, "Documentation Bloat Analysis")
            end
        end
    end
    
    @testset "Organization Cleanup" begin
        # Test with empty repository list
        results = cleanup_org_gh_pages_docs(String[], dry_run=true)
        @test isempty(results)
        
        # Test with invalid repository URLs would require actual network access
        # So we'll skip this for unit tests
    end
    
    @testset "Integration Test - Full Workflow" begin
        mktempdir() do tmpdir
            cd(tmpdir) do
                # Setup complete mock repository
                run(`git init`)
                run(`git config user.email "test@example.com"`)
                run(`git config user.name "Test User"`)
                
                # Main branch
                write("README.md", "# Test Package")
                mkdir("src")
                write("src/Package.jl", "module Package end")
                run(`git add .`)
                run(`git commit -m "Initial package"`)
                
                # Create tags (simulating releases)
                run(`git tag v1.0.0`)
                run(`git tag v2.0.0`)
                
                # Create gh-pages with documentation
                run(`git checkout --orphan gh-pages`)
                
                # Create realistic documentation structure
                for version in ["v1.0.0", "v1.5.0", "v2.0.0"]
                    mkdir(version)
                    mkdir("$version/tutorials")
                    
                    # Create realistic documentation files
                    write("$version/index.html", """
                    <!DOCTYPE html>
                    <html><head><title>Docs $version</title></head>
                    <body><h1>Documentation $version</h1></body></html>
                    """)
                    
                    # Simulate large tutorial with embedded plots
                    large_tutorial = """
                    <!DOCTYPE html><html><head><title>Tutorial</title></head><body>
                    <h1>Tutorial</h1>
                    <div>$(repeat("Large embedded SVG plot data ", 50000))</div>
                    </body></html>
                    """
                    write("$version/tutorials/example.html", large_tutorial)
                end
                
                # Add development and preview docs
                mkdir("dev")
                write("dev/index.html", "Development documentation")
                
                mkdir("previews")
                mkdir("previews/PR123") 
                write("previews/PR123/index.html", "PR preview docs")
                
                run(`git add .`)
                run(`git commit -m "Add comprehensive documentation"`)
                
                # Test analysis first
                analysis = analyze_gh_pages_bloat(tmpdir)
                @test analysis.total_size_mb > 1.0  # Should have large files
                @test length(analysis.versions) == 3
                @test analysis.latest_version == "v2.0.0"
                
                # Test cleanup preserving latest
                result = cleanup_gh_pages_docs(tmpdir, preserve_latest=true)
                
                @test result.success == true
                @test result.preserved_version == "v2.0.0"
                @test result.files_removed > 0
                @test "v1.0.0" in result.versions_cleaned
                @test "dev" in result.versions_cleaned
                
                # Verify final state
                @test isdir("v2.0.0")  # Latest preserved
                @test !isdir("v1.0.0")  # Old version removed
                @test !isdir("dev")     # Dev docs removed
                @test !isdir("previews") # Preview docs removed
                
                # Verify git history was updated
                last_commit = readchomp(`git log -1 --format=%s`)
                @test contains(last_commit, "Clean up old documentation")
            end
        end
    end
end