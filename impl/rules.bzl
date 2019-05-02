ElixirLibrary = provider(
    doc = "Provider for compiled .beam modules stored in `ebin` directories",
    fields = {
        "loadpath": "depset of `ebin` directories"
    }
)

# we need to make an attribute with the default value of a Label in order to
# introduce an implicit dependency on elixir itself
_elixir_common_attrs = {
    "_elixir_tool": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@elixir//:elixir_tool"),
    ),
}

# invoke the elixir compiler on `srcs`, producing a single ebin dir `out`
def elixir_compile(ctx, srcs, out, loadpath = []):
    args = ctx.actions.args()
    args.add("elixirc")
    args.add_all(loadpath, expand_directories=False, before_each = "-pa")
    args.add("-o", out.path)
    args.add_all(srcs)

    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        outputs = [out],
        inputs = depset(direct = srcs, transitive = [loadpath]),
        arguments = [args],
        env = {"HOME": ".",
               "LANG": "en_US.UTF-8"}
    )

_elixir_library_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex"],
        doc = "Source files",
    ),
    "compile_deps": attr.label_list(),
    "runtime_deps": attr.label_list(),
}

def _elixir_library_impl(ctx):
    ebin_dir = ctx.actions.declare_directory(ctx.label.name + "_ebin")
    compile_loadpath = depset(transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.compile_deps])
    elixir_compile(
        ctx,
        srcs = ctx.files.srcs,
        loadpath = compile_loadpath,
        out = ebin_dir,
    )
    runtime_loadpath = depset(transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.runtime_deps])
    return [
        DefaultInfo(
            files = depset([ebin_dir]),
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir],
                transitive = [runtime_loadpath]
            ),
        )
    ]

elixir_library = rule(
    _elixir_library_impl,
    attrs = dict(_elixir_common_attrs.items() + _elixir_library_attrs.items()),
    doc = "Builds a directory containing .beam files for all modules in the source file(s)",
)

_elixir_script_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex", ".exs"],
        doc = "Source files",
    ),
    # since scripts don't have a separate compilation step, they just have `deps`,
    # unlike elixir_libraries, which must specify compile and runtime deps separately
    "deps": attr.label_list(),
    "_script_template": attr.label(
        allow_single_file = True,
        default = Label("//impl:elixir_script.template"),
    ),
}

# helper to find paths to our runfiles, might need to get smarter to work cross-platform... 
def _rlocation(ctx, runfile):
    # NOTE: Windows runfiles manifest file includes workspace name...
    # but if we have real symlinks they don't have workspace name... 
    #return "$(rlocation {}/{})".format(ctx.workspace_name, runfile.short_path)
    return runfile.short_path

def _elixir_script_impl(ctx):
    # collect all transitive loadpaths into runfiles, since we need them at runtime 
    lib_runfiles = ctx.runfiles(
        transitive_files = depset(
            transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.deps]
        ),
    )
    src_runfiles = ctx.runfiles(files = ctx.files.srcs)

    ctx.actions.expand_template(
        template = ctx.file._script_template,
        output = ctx.outputs.executable,
        substitutions = {
            "{elixir_tool}": ctx.executable._elixir_tool.path,
            "{loadpath}":    " ".join(["-pa {}".format(_rlocation(ctx, f)) for f in lib_runfiles.files]),
            "{srcs}":        " ".join([_rlocation(ctx, f) for f in src_runfiles.files]),
        },
        is_executable = True,
    )
    return [
        DefaultInfo(runfiles = src_runfiles.merge(lib_runfiles))
    ]


elixir_script_runner = rule(
    _elixir_script_impl,
    attrs = dict(_elixir_common_attrs.items() + _elixir_script_attrs.items()),
    executable = True,
    doc = "Elixir script, intended for use with `bazel run` -- does not work outside bazel context"
)

def elixir_script(name = None, **kwargs):
    runner = name + "_runner"
    elixir_script_runner(name = runner, **kwargs)
    native.sh_binary(
        name = name,
        deps = ["@bazel_tools//tools/bash/runfiles", "@elixir//:elixir_tool_lib"],
        srcs = [runner],
        visibility = ["//visibility:public"],
    )


# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro  
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),        
    "mix_env":        attr.string(),
    "elixirc_files":  attr.label_list(allow_files = True),
    "build_path":     attr.string(),
    "deps_tree":      attr.label_list(allow_files = True),
    "deps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True)
}
        
# implementation of mix_third_party_deps rule -- compile ALL third_party deps as a single unit
# simpler to implement and avoids duplicate work if one dep depends on another
def _mix_third_party_deps_impl(ctx):
    out_name = "third_party"
    # declare the root directory so that we know where bazel wants us to put everything
    out_dir = ctx.actions.declare_directory(out_name)
    # declare all ebin dirs that will be created so we can provide them with ElixirLibrary 
    ebin_dirs = [
        ctx.actions.declare_file(
            "{output}/{env}/lib/{pkg}/ebin".format(
                output = out_name,
                env = ctx.attr.mix_env,
                pkg = dep,
                )
        )
        for dep in ctx.attr.deps_names
    ]
    
    args = ctx.actions.args()
    args.add_all(["elixir", "-e",
        """
        File.cd!("{project_dir}", fn -> Mix.start; Mix.CLI.main; end)
        0 = System.cmd("cp", ["-r", "{project_dir}/{build_path}", "{out_dir}"]) |> elem(1)
        """.format(
            project_dir = ctx.file.mixfile.dirname,
            build_path = ctx.attr.build_path,
            out_dir = out_dir.path,
        ),
        "deps.compile",
    ])
    args.add_all(ctx.attr.deps_names)

    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        inputs = (
            ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + ctx.files.deps_tree
        ),
        progress_message = "Compiling {} third-party Mix dependencies".format(len(ctx.attr.deps_names)),
        outputs = [out_dir] + ebin_dirs,
        arguments = [args],
        env = {
            "HOME": "/Users/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        }
    )

    return [
        ElixirLibrary(
            loadpath = depset(ebin_dirs),
        ),
        DefaultInfo(
            files = depset(ebin_dirs),
        )
    ]

mix_third_party_deps = rule(
    _mix_third_party_deps_impl,
    attrs = dict(_elixir_common_attrs.items() + _mix_project_attrs.items()),
)



def mix_project(name = None,
                elixirc_paths = [],
                deps_path = None,
                apps_path = None,
                **kwargs):
    mix_third_party_deps(
        name = name + "_third_party",
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        elixirc_files = native.glob([d + "/**" for d in elixirc_paths]),
        deps_tree = native.glob(["{}/**".format(deps_path)]),
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        visibility = ["//visibility:public"],
        **kwargs
    )

