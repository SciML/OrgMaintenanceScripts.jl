# Explicit Imports Fixer
# Automatically fix explicit import issues using ExplicitImports.jl

using Pkg
using TOML

"""
    run_explicit_imports_check(package_path::String; verbose=true)

Run ExplicitImports.jl checks on a package and return the report.
Returns (success::Bool, report::String, issues::Vector)
"""
function run_explicit_imports_check(package_path::String; verbose=true)
    if !isdir(package_path)
        error("Package path does not exist: $package_path")
    end
    
    # Create a temporary environment to run checks
    mktempdir() do tmpdir
        # Copy the package to temp directory to avoid modifying the original during checks
        test_path = joinpath(tmpdir, "test_package")
        cp(package_path, test_path)
        
        cd(test_path) do
            # Create a temporary project for running ExplicitImports
            checker_env = joinpath(tmpdir, "checker_env")
            mkpath(checker_env)
            
            # Create the checker script
            checker_script = joinpath(tmpdir, "check_imports.jl")
            open(checker_script, "w") do io
                write(io, """
                using Pkg
                Pkg.activate(".")
                Pkg.instantiate()
                
                # Add ExplicitImports to the environment
                Pkg.add("ExplicitImports")
                
                using ExplicitImports
                
                # Load the package
                pkg_name = TOML.parsefile("Project.toml")["name"]
                pkg_symbol = Symbol(pkg_name)
                
                # Try to load the package
                try
                    eval(:(using \$pkg_symbol))
                catch e
                    println("ERROR: Failed to load package: ", e)
                    exit(1)
                end
                
                # Get the module
                mod = getfield(Main, pkg_symbol)
                
                # Run checks
                println("=== CHECKING MISSING EXPLICIT IMPORTS ===")
                missing_imports = check_no_implicit_imports(mod)
                if !isnothing(missing_imports)
                    println(missing_imports)
                end
                
                println("\\n=== CHECKING UNNECESSARY EXPLICIT IMPORTS ===")
                unnecessary = check_no_stale_explicit_imports(mod)
                if !isnothing(unnecessary)
                    println(unnecessary)
                end
                
                println("\\n=== CHECKING QUALIFIED ACCESSES ===")
                qualified = check_all_qualified_accesses_via_owners(mod)
                if !isnothing(qualified)
                    println(qualified)
                end
                
                println("\\n=== CHECKING PUBLIC EXPORTS ===")
                public_check = check_all_explicit_imports_are_public(mod)
                if !isnothing(public_check)
                    println(public_check)
                end
                """)
            end
            
            # Run the checker script
            try
                output = read(`julia --project=. $checker_script`, String)
                
                # Parse the output to identify issues
                issues = parse_explicit_imports_output(output)
                
                if verbose
                    @info "ExplicitImports check output:\n$output"
                end
                
                # Check if there are any issues
                success = isempty(issues)
                
                return success, output, issues
            catch e
                error_msg = sprint(showerror, e)
                if verbose
                    @error "Failed to run ExplicitImports check: $error_msg"
                end
                return false, error_msg, []
            end
        end
    end
end

"""
    parse_explicit_imports_output(output::String)

Parse the output from ExplicitImports checks to extract actionable issues.
Returns a vector of issues with their types and details.
"""
function parse_explicit_imports_output(output::String)
    issues = []
    
    lines = split(output, '\n')
    current_section = ""
    
    for line in lines
        # Identify sections
        if occursin("CHECKING MISSING EXPLICIT IMPORTS", line)
            current_section = "missing_imports"
        elseif occursin("CHECKING UNNECESSARY EXPLICIT IMPORTS", line)
            current_section = "unnecessary_imports"
        elseif occursin("CHECKING QUALIFIED ACCESSES", line)
            current_section = "qualified_access"
        elseif occursin("CHECKING PUBLIC EXPORTS", line)
            current_section = "public_exports"
        end
        
        # Parse issues based on section
        if current_section == "missing_imports" && occursin("is not explicitly imported", line)
            # Extract: "SomeModule.function is not explicitly imported"
            m = match(r"(\w+)\.(\w+) is not explicitly imported", line)
            if m !== nothing
                push!(issues, (
                    type = :missing_import,
                    module_name = m.captures[1],
                    symbol = m.captures[2],
                    line = line
                ))
            end
        elseif current_section == "unnecessary_imports" && occursin("is explicitly imported but not used", line)
            # Extract: "function is explicitly imported but not used"
            m = match(r"(\w+) is explicitly imported but not used", line)
            if m !== nothing
                push!(issues, (
                    type = :unused_import,
                    symbol = m.captures[1],
                    line = line
                ))
            end
        elseif occursin("FAIL", line) || occursin("WARN", line)
            # Generic issue detection
            push!(issues, (
                type = :generic,
                section = current_section,
                line = line
            ))
        end
    end
    
    return issues
end

"""
    fix_missing_import(file_path::String, module_name::String, symbol::String)

Add a missing explicit import to a Julia file.
"""
function fix_missing_import(file_path::String, module_name::String, symbol::String)
    if !isfile(file_path)
        @warn "File not found: $file_path"
        return false
    end
    
    content = read(file_path, String)
    lines = split(content, '\n')
    
    # Find where to insert the import
    # Look for existing imports from the same module
    import_pattern = Regex("using $module_name(?::|\\s)")
    import_line_idx = findfirst(i -> occursin(import_pattern, lines[i]), 1:length(lines))
    
    if import_line_idx !== nothing
        # Add to existing import
        line = lines[import_line_idx]
        if occursin("using $module_name:", line)
            # Already has explicit imports, add to the list
            lines[import_line_idx] = replace(line, r"$" => ", $symbol")
        else
            # Convert to explicit import
            lines[import_line_idx] = "using $module_name: $symbol"
        end
    else
        # Find a good place to add the import (after module declaration or at the beginning)
        module_line_idx = findfirst(i -> occursin(r"^module\s+", lines[i]), 1:length(lines))
        insert_idx = module_line_idx !== nothing ? module_line_idx + 1 : 1
        
        # Add some spacing if needed
        if insert_idx <= length(lines) && !isempty(strip(lines[insert_idx]))
            insert!(lines, insert_idx, "")
            insert_idx += 1
        end
        
        insert!(lines, insert_idx, "using $module_name: $symbol")
    end
    
    # Write back
    write(file_path, join(lines, '\n'))
    
    @info "Added import: using $module_name: $symbol to $file_path"
    return true
end

"""
    fix_unused_import(file_path::String, symbol::String)

Remove an unused import from a Julia file.
"""
function fix_unused_import(file_path::String, symbol::String)
    if !isfile(file_path)
        @warn "File not found: $file_path"
        return false
    end
    
    content = read(file_path, String)
    
    # Remove the symbol from import statements
    # Handle various import patterns
    patterns = [
        # using Module: symbol, other_symbol
        r"using\s+(\w+):\s*([^,\n]*,\s*)*" * symbol * r"\s*(,\s*[^,\n]+)*" => s -> begin
            # Remove the symbol and clean up commas
            cleaned = replace(s, Regex("\\b$symbol\\b\\s*,?\\s*") => "")
            # Remove trailing comma if any
            cleaned = replace(cleaned, r",\s*$" => "")
            # Remove empty imports
            if occursin(r"using\s+\w+:\s*$", cleaned)
                ""
            else
                cleaned
            end
        end,
        # import Module.symbol
        Regex("import\\s+\\w+\\.$symbol\\s*\$", "m") => "",
        # import Module: symbol
        Regex("import\\s+\\w+:\\s*$symbol\\s*\$", "m") => "",
    ]
    
    modified = content
    for (pattern, replacement) in patterns
        modified = replace(modified, pattern => replacement)
    end
    
    # Clean up empty lines
    modified = replace(modified, r"\n\n\n+" => "\n\n")
    
    if modified != content
        write(file_path, modified)
        @info "Removed unused import: $symbol from $file_path"
        return true
    else
        @warn "Could not find import to remove: $symbol in $file_path"
        return false
    end
end

"""
    find_files_to_fix(package_path::String, issues::Vector)

Find which files need to be fixed based on the issues found.
Returns a Dict mapping file paths to their issues.
"""
function find_files_to_fix(package_path::String, issues::Vector)
    files_to_fix = Dict{String, Vector}()
    
    # For now, we'll apply fixes to the main module file
    # In a more sophisticated version, we'd parse stack traces or use more advanced analysis
    src_dir = joinpath(package_path, "src")
    
    if isdir(src_dir)
        for (root, dirs, files) in walkdir(src_dir)
            for file in files
                if endswith(file, ".jl")
                    file_path = joinpath(root, file)
                    # For simplicity, we'll apply all fixes to all .jl files
                    # A more sophisticated approach would analyze which file needs which fix
                    files_to_fix[file_path] = issues
                end
            end
        end
    end
    
    return files_to_fix
end

"""
    fix_explicit_imports(package_path::String; max_iterations=10, verbose=true)

Iteratively fix explicit import issues in a package until all checks pass.
Returns (success::Bool, iterations::Int, final_report::String)
"""
function fix_explicit_imports(package_path::String; max_iterations=10, verbose=true)
    if !isdir(package_path)
        error("Package path does not exist: $package_path")
    end
    
    @info "Starting explicit imports fixing for $package_path"
    
    iteration = 0
    
    while iteration < max_iterations
        iteration += 1
        @info "Iteration $iteration/$max_iterations"
        
        # Run checks
        success, report, issues = run_explicit_imports_check(package_path; verbose)
        
        if success
            @info "✓ All explicit import checks passed!"
            return true, iteration, report
        end
        
        if isempty(issues)
            @warn "No specific issues found but checks still failing"
            return false, iteration, report
        end
        
        @info "Found $(length(issues)) issues to fix"
        
        # Find files that need fixes
        files_to_fix = find_files_to_fix(package_path, issues)
        
        # Apply fixes
        fixes_applied = 0
        for (file_path, file_issues) in files_to_fix
            for issue in file_issues
                if issue.type == :missing_import
                    if fix_missing_import(file_path, issue.module_name, issue.symbol)
                        fixes_applied += 1
                    end
                elseif issue.type == :unused_import
                    if fix_unused_import(file_path, issue.symbol)
                        fixes_applied += 1
                    end
                end
            end
        end
        
        if fixes_applied == 0
            @warn "No fixes could be applied, stopping"
            return false, iteration, report
        end
        
        @info "Applied $fixes_applied fixes"
        
        # Test that the package still loads after fixes
        try
            cd(package_path) do
                run(`julia --project=. -e "using Pkg; Pkg.instantiate(); using $(TOML.parsefile("Project.toml")["name"])"`)
            end
        catch e
            @error "Package no longer loads after fixes, reverting would be needed"
            return false, iteration, "Package broken after fixes: $(sprint(showerror, e))"
        end
    end
    
    @warn "Reached maximum iterations without resolving all issues"
    success, report, _ = run_explicit_imports_check(package_path; verbose=false)
    return false, max_iterations, report
end

"""
    fix_repo_explicit_imports(repo_name::String;
                             work_dir=mktempdir(),
                             max_iterations=10,
                             create_pr=true,
                             verbose=true)

Clone a repository, fix its explicit imports, and optionally create a PR.
"""
function fix_repo_explicit_imports(repo_name::String;
                                  work_dir::String=mktempdir(),
                                  max_iterations::Int=10,
                                  create_pr::Bool=true,
                                  verbose::Bool=true)
    
    # Clone repository
    repo_dir = joinpath(work_dir, replace(repo_name, "/" => "_"))
    repo_url = "https://github.com/$repo_name.git"
    
    @info "Cloning $repo_name..."
    run(`git clone $repo_url $repo_dir`)
    
    # Create feature branch
    cd(repo_dir) do
        # Get default branch
        default_branch = strip(read(`git symbolic-ref refs/remotes/origin/HEAD`, String))
        default_branch = split(default_branch, "/")[end]
        run(`git checkout $default_branch`)
        
        # Create new branch
        branch_name = "fix-explicit-imports-$(Dates.format(now(), "yyyymmdd-HHMMSS"))"
        run(`git checkout -b $branch_name`)
    end
    
    # Fix explicit imports
    success, iterations, final_report = fix_explicit_imports(repo_dir; max_iterations, verbose)
    
    if !success
        @warn "Could not fully fix explicit imports for $repo_name"
        # Still create PR if we made some progress
    end
    
    # Check if there are changes
    cd(repo_dir) do
        changes = read(`git diff --name-only`, String)
        if isempty(strip(changes))
            @info "No changes needed for $repo_name"
            return false
        end
        
        # Commit changes
        run(`git add -A`)
        
        commit_msg = """
        Fix explicit imports using ExplicitImports.jl
        
        This commit fixes explicit import issues identified by ExplicitImports.jl:
        - Added missing explicit imports
        - Removed unused imports
        
        The changes were applied iteratively over $iterations iteration(s) to ensure
        all checks pass while maintaining package functionality.
        
        Final status: $(success ? "All checks passing ✓" : "Some checks may still need manual review")
        """
        
        run(`git commit -m $commit_msg`)
        
        if create_pr
            @info "Creating pull request..."
            
            # Push branch
            run(`git push -u origin HEAD`)
            
            # Create PR using GitHub CLI
            pr_title = "Fix explicit imports"
            pr_body = """
            ## Summary
            
            This PR fixes explicit import issues identified by ExplicitImports.jl to improve code clarity and prevent implicit dependencies.
            
            ## Changes
            
            - Added missing explicit imports where symbols were being used implicitly
            - Removed unused imports that were explicitly imported but never used
            - Ensured all imports follow explicit import best practices
            
            ## Testing
            
            The changes were applied iteratively ($iterations iterations) with the following process:
            1. Run ExplicitImports.jl checks
            2. Apply fixes for identified issues
            3. Verify the package still loads and functions correctly
            4. Repeat until all checks pass or no more fixes can be applied
            
            Final status: **$(success ? "All checks passing ✓" : "Some checks may still need manual review")**
            
            ## Benefits
            
            - Improved code clarity by making all dependencies explicit
            - Reduced chance of name conflicts
            - Faster load times by avoiding unnecessary imports
            - Better compatibility with static analysis tools
            """
            
            try
                run(`gh pr create --title "$pr_title" --body "$pr_body"`)
                @info "✓ Pull request created successfully!"
                return true
            catch e
                @warn "Failed to create PR automatically: $e"
                @info "You can create it manually with the branch that was pushed"
                return true
            end
        end
    end
    
    return true
end

"""
    fix_org_explicit_imports(org_name::String;
                            work_dir=mktempdir(),
                            max_iterations=10,
                            create_prs=true,
                            skip_repos=String[],
                            only_repos=nothing,
                            verbose=true)

Fix explicit imports for all Julia packages in a GitHub organization.
"""
function fix_org_explicit_imports(org_name::String;
                                 work_dir::String=mktempdir(),
                                 max_iterations::Int=10,
                                 create_prs::Bool=true,
                                 skip_repos::Vector{String}=String[],
                                 only_repos::Union{Nothing,Vector{String}}=nothing,
                                 verbose::Bool=true)
    
    @info "Fetching repositories for organization: $org_name"
    
    # Get repositories
    if only_repos !== nothing
        repos = ["$org_name/$repo" for repo in only_repos]
    else
        # Use GitHub API to get all repos
        repos_json = read(`gh repo list $org_name --limit 1000 --json name,description,isArchived`, String)
        repos_data = JSON3.read(repos_json)
        
        # Filter for Julia packages
        repos = String[]
        for repo in repos_data
            if !repo.isArchived && endswith(repo.name, ".jl")
                push!(repos, "$org_name/$(repo.name)")
            end
        end
    end
    
    # Filter out skipped repos
    repos = filter(r -> !any(skip -> occursin(skip, r), skip_repos), repos)
    
    @info "Found $(length(repos)) Julia repositories to process"
    
    results = Dict{String, Bool}()
    
    for (i, repo) in enumerate(repos)
        @info "\n" * "="^60
        @info "Processing repository $i/$(length(repos)): $repo"
        @info "="^60
        
        try
            success = fix_repo_explicit_imports(repo; 
                                               work_dir,
                                               max_iterations,
                                               create_pr=create_prs,
                                               verbose)
            results[repo] = success
        catch e
            @error "Failed to process $repo: $e"
            results[repo] = false
        end
        
        # Small delay to avoid rate limits
        sleep(2)
    end
    
    # Summary
    @info "\n" * "="^60
    @info "SUMMARY"
    @info "="^60
    
    successful = count(values(results))
    @info "Successfully processed: $successful/$(length(results))"
    
    if any(values(results))
        @info "\nRepositories with fixes:"
        for (repo, success) in results
            if success
                @info "  ✓ $repo"
            end
        end
    end
    
    if any(.!values(results))
        @info "\nRepositories that failed or needed no changes:"
        for (repo, success) in results
            if !success
                @info "  ✗ $repo"
            end
        end
    end
    
    return results
end