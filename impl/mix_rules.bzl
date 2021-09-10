load("//impl:common.bzl", "ElixirLibrary", "elixir_common_attrs")
load("//impl:providers.bzl", "MixBuild", "MixDepsCached", "MixLock", "MixProject")
load("//impl:mix_lock.bzl", "add_mix_deps_to_args")

# All of the weird and wonderful files you might encounter while building dependencies
project_build_file_names = [
    "mix.exs",
    "mix.lock",
    "hex_metadata.config",
    ".hex",
    ".fetch",
    "**/*.script",
    "rebar.config",
    "rebar.config.script",
    "rebar.lock",
    "Makefile",
    "erlang.mk",
    "VERSION",
    ".git/**",  # gross
]

def package_as_directory(t):
    p = t.label.package
    if p == "":
        return "."
    return p

################################################################
## `mix_config_group`
## This rule is where we collect configuration and actually compile stuff

_dep_builder_implicit_attrs = {
    "_dep_builder": attr.label(
        default = Label("@rules_elixir//impl/tools:dep_builder"),
        executable = True,
        cfg = "host",
    ),
    "_rebar": attr.label(
        default = Label("@rebar//file"),
        allow_single_file = True,
        executable = True,
        cfg = "host",
    ),
    "_rebar3": attr.label(
        default = Label("@rebar3//file"),
        allow_single_file = True,
        executable = True,
        cfg = "host",
    ),
}

_mix_config_group_attrs = {
    "projects": attr.label_list(),
    "root": attr.label(),
    "mix_env": attr.string(),
    "friendly_name": attr.string(doc = "used in progress_messages"),
    "mix_lock": attr.label(providers = [MixLock]),
    "_subtree_copier": attr.label(
        default = Label("@rules_elixir//impl/tools:subtree_copier"),
        executable = True,
        cfg = "host",
    ),
    "mix_deps_cached": attr.label(providers = [MixDepsCached]),
}

def _mix_config_group_impl(ctx):
    if ctx.attr.root and ctx.attr.projects:
        fail("cannot specify `root` and `projects` at the same time")

    projects = [ctx.attr.root] if ctx.attr.root else ctx.attr.projects

    transitive_map = {
        dep[MixProject].app: dep
        for dep in depset(
            direct = projects,
            transitive = [dep[MixProject].deps for dep in projects],
        ).to_list()
    }

    all_build_files = depset(transitive = [dep[MixProject].build_files for dep in projects])
    all_config_files = depset(transitive = [dep[MixProject].config_files for dep in projects])

    # Declare output lib dirs; actual directories
    app_lib_dirs = {
        dep_name: ctx.actions.declare_directory(
            "{}/_build/{}/lib/{}".format(ctx.label.name, ctx.attr.mix_env, dep_name),
        )
        for (dep_name, dep) in transitive_map.items()
    }

    # Declare output archives; these are used to pass intermediate results along
    app_lib_archives = {
        dep_name: ctx.actions.declare_file(
            "{}/archive/{}/{}".format(ctx.label.name, ctx.attr.mix_env, dep_name),
        )
        for (dep_name, dep) in transitive_map.items()
    }

    # Trick bazel into telling us the name of the parent of the parent of all app lib dirs
    dir_marker = ctx.actions.declare_file("{}/_build/{}/-".format(ctx.label.name, ctx.attr.mix_env))
    ctx.actions.write(dir_marker, "-")

    build_environment = {
        "HOME": ".",
        "MIX_REBAR_RELATIVE": ctx.file._rebar.path,
        "MIX_REBAR3_RELATIVE": ctx.file._rebar3.path,
        "MIX_BUILD_PATH_RELATIVE": dir_marker.dirname + "/lib",
        #        "ERL_COMPILER_OPTIONS": "deterministic",
        "PATH": "/bin:/usr/bin:/usr/local/bin",
        "MIX_ENV": ctx.attr.mix_env,
    }

    for (dep_name, dep) in transitive_map.items():
        # Get the apps we will need to know about, along with their configs and build outputs
        apps = dep[MixProject].configured_applications.to_list()

        args = ctx.actions.args()
        if dep == ctx.attr.root:
            # If this is the root project, compile it with `mix compile` in its own directory
            args.add("--subdir", dep[MixProject].mix_exs[0].dirname)
            args.add("--mode", "compile")
        else:
            # If not, compile it with `deps.compile` in from the root directory
            args.add("--subdir", ctx.attr.root[MixProject].mix_exs[0].dirname)
            args.add("--mode", "deps.compile")

        cached_deps = ctx.attr.mix_deps_cached[MixDepsCached].mix_deps_cached
        args.add("--mix-deps-cached", cached_deps)

        args.add(dep_name)

        args.add_all(
            [app_lib_archives[a] for a in apps],
            before_each = "--ar",
        )

        args.add("--output-archive", app_lib_archives[dep_name].path)

        md = ctx.attr.mix_lock
        add_mix_deps_to_args(args, md[MixLock])

        ctx.actions.run(
            progress_message = "[{} :{}] {}".format(ctx.attr.friendly_name or ctx.label.name, ctx.attr.mix_env, dep_name),
            executable = ctx.executable._dep_builder,
            inputs = depset(
                direct = [app_lib_archives[a] for a in apps] + [cached_deps],
                transitive = [
                    # Our own source/build files
                    dep[MixProject].source_files,
                    # Transitive config files (config files of in-umbrella deps)
                    dep[MixProject].config_files,
                    # Config files of the root project
                    ctx.attr.root[MixProject].config_files,
                    # files of the root project
                    ctx.attr.root[MixProject].build_files,
                    # Since we have cached the Mix.Dep structure, we do not need to the other mix.exs files.
                    # They would otherwise be necessary so we can find deps not explicitly mentioned in our mix.exs
                ],
            ),
            arguments = [args],
            outputs = [app_lib_archives[dep_name]],
            env = build_environment,
            tools = [ctx.file._rebar, ctx.file._rebar3],
        )

        # We may want to expand the archives into actual directories for use by things other than dep_builder
        # Do that in a separate action to avoid uploading lots of tiny .beam files to the cache individually
        sc_args = ctx.actions.args()
        sc_args.add("--ar", app_lib_archives[dep_name])
        sc_args.add("--output", app_lib_dirs[dep_name].dirname)
        ctx.actions.run(
            executable = ctx.executable._subtree_copier,
            inputs = [app_lib_archives[dep_name]],
            outputs = [app_lib_dirs[dep_name]],
            arguments = [sc_args],
            execution_requirements = {
                "no-cache": "1",
                "no-remote": "1",
            },
        )

    output_lib_dirs = depset(app_lib_dirs.values())
    return [
        DefaultInfo(
            files = output_lib_dirs,
            runfiles = ctx.runfiles(transitive_files = depset(transitive = [all_build_files, all_config_files])),
        ),
        ElixirLibrary(
            lib_dirs = output_lib_dirs,
        ),
        MixBuild(
            mix_lock = md,
            root_project = ctx.attr.root,
            archives = app_lib_archives,
        ),
    ]

mix_config_group = rule(
    _mix_config_group_impl,
    attrs = dict(
        elixir_common_attrs.items() +
        _mix_config_group_attrs.items() +
        _dep_builder_implicit_attrs.items(),
    ),
)

################################################################
## `mix_project_rule`
## This rule does not actually build anything, it just propagates
## the information in the MixProject provider.

_mix_project_attrs = {
    "app": attr.string(mandatory = True),
    "deps": attr.label_list(),
    "build_files": attr.label_list(allow_files = True),
    "mix_env": attr.string(default = "prod"),
    "config_files": attr.label_list(allow_files = True),
    "umbrella": attr.label(),
    "source_files": attr.label_list(allow_files = True),
    "external": attr.bool(default = False),
    # optional, inferred based on package if not present
    "mix_exs": attr.label_list(allow_files = ["mix.exs"]),
    # These are for specifying where the project files are located.
    # Useful for dependency projects downloaded by repository rules.
    "directory": attr.label(allow_single_file = True),
    "deps_path": attr.string(),
    "build_path": attr.string(),
    "imports_config_from": attr.label(
        providers = [MixProject],
        doc = "Another MixProject whose config we import, making it part of our config",
    ),
}

def _mix_project_impl(ctx):
    # If we are in the umbrella, we depend on its root mixfile and config files
    umbrella_config = [ctx.attr.umbrella[MixProject].config_files] if ctx.attr.umbrella else []
    umbrella_build = [ctx.attr.umbrella[MixProject].build_files] if ctx.attr.umbrella else []

    # If we are not in the umbrella maybe we are still importing someone else's config for some reason
    extra_config = [ctx.attr.imports_config_from[MixProject].config_files] if ctx.attr.imports_config_from else []

    dir_path = None
    if ctx.file.directory:
        dir_path = ctx.file.directory.path

    dep_projects = depset(
        direct = ctx.attr.deps,
        transitive = [dep[MixProject].deps for dep in ctx.attr.deps],
    )

    transitive_build_files = depset(
        direct = ctx.files.build_files + ctx.files.mix_exs,
        transitive = umbrella_build + [dep[MixProject].build_files for dep in ctx.attr.deps],
    )

    return [
        DefaultInfo(
            files = depset(ctx.files.source_files),
        ),
        MixProject(
            app = ctx.attr.app,
            mix_env = ctx.attr.mix_env,
            mix_exs = ctx.files.mix_exs,
            deps = dep_projects,
            build_files = transitive_build_files,
            config_files = depset(
                direct = ctx.files.config_files,
                transitive = umbrella_config + extra_config + [dep[MixProject].config_files for dep in ctx.attr.deps],
            ),
            source_files = depset(ctx.files.source_files),
            umbrella = ctx.attr.umbrella,
            configured_applications = depset(
                direct = [d[MixProject].app for d in ctx.attr.deps],
                transitive = [dep[MixProject].configured_applications for dep in ctx.attr.deps],
            ),
            directory = dir_path,
            build_path = ctx.attr.build_path,
            deps_path = ctx.attr.deps_path,
            external = ctx.attr.external,
        ),
    ]

mix_project_rule = rule(
    _mix_project_impl,
    attrs = dict(
        elixir_common_attrs.items() +
        _mix_project_attrs.items() +
        _dep_builder_implicit_attrs.items(),
    ),
)

def _mix_project_in_context_impl(ctx):
    a = ctx.attr.like[MixProject]
    dep_projects = depset(
        direct = ctx.attr.deps,
        transitive = [dep[MixProject].deps for dep in ctx.attr.deps],
    )
    transitive_build_files = depset(
        transitive = [a.build_files] + [dep[MixProject].build_files for dep in ctx.attr.deps],
    )

    return [
        MixProject(
            app = a.app,
            mix_env = a.mix_env,
            mix_exs = a.mix_exs,
            deps = dep_projects,
            build_files = transitive_build_files,
            config_files = depset(
                transitive = [a.config_files] + [dep[MixProject].config_files for dep in ctx.attr.deps],
            ),
            source_files = a.source_files,
            umbrella = a.umbrella,
            configured_applications = depset(
                direct = [dep[MixProject].app for dep in ctx.attr.deps],
                transitive = [a.configured_applications] + [dep[MixProject].configured_applications for dep in ctx.attr.deps],
            ),
            directory = a.directory,
            external = a.external,
            build_path = a.build_path,
            deps_path = a.deps_path,
            source_project = ctx.attr.like,
        ),
    ]

mix_project_in_context = rule(
    _mix_project_in_context_impl,
    attrs = {
        "like": attr.label(providers = [MixProject]),
        "deps": attr.label_list(providers = [MixProject]),
    },
)

# This is called by the build files we generate for external dependencies with the repo rules
def mix_external_project(name = None, mix_env = None, **kwargs):
    mix_project_rule(
        name = name,
        visibility = ["//visibility:public"],
        build_files = native.glob(project_build_file_names),
        mix_exs = native.glob(["mix.exs"]),
        config_files = [],
        mix_env = mix_env,
        external = True,
        **kwargs
    )

def mix_project2(
        name = None,
        mix_env = None,
        # elixirc_paths = None,
        elixir_sources = [],
        extra_build_files = [],
        extra_config_files = [],
        **kwargs):
    mix_project_rule(
        name = name,
        visibility = ["//visibility:public"],
        # source_files = native.glob(["priv/**"] + elixirc_globs),
        source_files = native.glob(["priv/**"]) + elixir_sources,
        build_files = native.glob(["mix.exs", "mix.lock"]) + extra_build_files,
        mix_exs = native.glob(["mix.exs"]),
        # HACK: This is config/** instead of config/*.exs so that we can see
        # the config/docker-compose.env files from root in the mix_test rules
        config_files = native.glob(["config/**"]) + extra_config_files,
        mix_env = mix_env,
        **kwargs
    )
