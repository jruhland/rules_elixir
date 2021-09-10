# It is useful to define all the providers in one place so we can import them
# without worrying about creating circular dependencies in .bzl files

OTPInfo = provider(
    doc = "Toolchain provider for erlang/OTP",
    fields = {
        "otp_version": "string, e.g. 22.0.7",
        "erts_version": "string, e.g. 10.4.4",
        "erl": "file, the `erl` executable",
        "lib_dir": """
        depset of files in lib/ dir.  named relative to release root,
        i.e. including lib/ in their names
        """,
        "erts_dir": "likewise for erts-x.y.z dir",
        "files": "depset of all the files you need to see",
        "c_headers": "a cc_library which contains all the .h files in erts-version/include",
    },
)

MixLock = provider(
    doc = """
    Maps dep names to the actual targets for those deps by version.
    Basically the bazel provider version of the same info in mix.lock.
    """,
    fields = {
        "by_app_name": "dict mapping app names to their `MixProject`s",
        "lockfile": "the corresponding mix.lock file",
        "all_files": "depset of all files in all deps",
    },
)

MixProject = provider(
    doc = """
    Provider for sources and metadata of a mix project.  Because Mix deps are consumed
    in source form, and can have optional dependencies, we don't actually know what our
    deps will be until someone depends on us.  
    """,
    fields = {
        "app": "string, app name",
        "mix_env": "string",
        "deps": "depset<Label>, dependency MixProjects",
        "build_files": """
        depset<File>, transitive build files.  Build files (eg mix.exs, rebar.config) are important because
        Mix uses them to find dependencies; if a dependency's build file is missing, Mix will not find the 
        transitive dependencies, so it will not know to add the transitive dep's modules to the loadpath. 
        """,
        "config_files": "despet<File>, transitive config files",
        "source_files": "depset<File>, NON-transitive source files.",
        "umbrella": "Label, the enclosing umbrella project, or None if this is not an umbrella app",
        "mix_exs": "Label list containing either mix.exs or nothing",
        "external": "Boolean, true when this dep is an external dep (ie from deps/ folder)",
        "configured_applications": "depset<string>, all transitive dependency applications, NOT including this one",
        "directory": "string, path to the root directory where this project's source files are located",
        "manager": "string; mix, rebar, or rebar3",
        "build_path": "string, relative to workspace root",
        "deps_path": "string, relative to workspace root",
        "source_project": """
        Label, the MixProject from the source folder for this project.
        Useful when we need to know the real directory of a project and we only have a mix_project_in_context
        """,
    },
)

MixDep = provider(
    doc = """
    Once a MixProject becomes part of a build, we can know it's configuration and dependencies,
    and it gets upgraded into a MixDep.
    """,
)

MixBuild = provider(
    doc = "information about a completed build",
    fields = {
        "mix_lock": "label, MixLock that was used in the build",
        "root_project": "label, root MixProject that was built",
        "archives": "map, app name to compiled binaries archive file",
    },
)

MixDepsCached = provider(
    doc = """
    Mix.Dep.load_and_cache is so incredibly slow it positively beggars belief.
    """,
    fields = {
        "mix_deps_cached": "label",
    },
)
