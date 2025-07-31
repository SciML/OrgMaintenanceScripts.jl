# Utilities for handling repositories with multiple Project.toml files

"""
    find_all_project_tomls(repo_path::String)

Find all Project.toml files in a repository, including those in the /lib subdirectory.
Returns a vector of absolute paths to Project.toml files.
"""
function find_all_project_tomls(repo_path::String)
    project_files = String[]

    # Check for main Project.toml
    main_project = joinpath(repo_path, "Project.toml")
    if isfile(main_project)
        push!(project_files, main_project)
    end

    # Check for JuliaProject.toml as alternative
    alt_project = joinpath(repo_path, "JuliaProject.toml")
    if isfile(alt_project)
        push!(project_files, alt_project)
    end

    # Check for lib directory with subprojects
    lib_dir = joinpath(repo_path, "lib")
    if isdir(lib_dir)
        for subdir in readdir(lib_dir; join = false)
            subproject_path = joinpath(lib_dir, subdir, "Project.toml")
            if isfile(subproject_path)
                push!(project_files, subproject_path)
            end
        end
    end

    return project_files
end

"""
    get_project_info(project_path::String)

Extract package name and other information from a Project.toml file.
Returns a NamedTuple with name, uuid, and path fields.
"""
function get_project_info(project_path::String)
    project = TOML.parsefile(project_path)
    name = get(project, "name", basename(dirname(project_path)))
    uuid = get(project, "uuid", nothing)

    return (name = name, uuid = uuid, path = project_path, project_dict = project)
end

"""
    is_subpackage(project_path::String, repo_path::String)

Check if a Project.toml file is a subpackage (i.e., in the /lib directory).
"""
function is_subpackage(project_path::String, repo_path::String)
    lib_dir = joinpath(repo_path, "lib")
    return startswith(project_path, lib_dir)
end

"""
    get_relative_project_path(project_path::String, repo_path::String)

Get the relative path of a Project.toml file from the repository root.
"""
function get_relative_project_path(project_path::String, repo_path::String)
    return relpath(project_path, repo_path)
end
