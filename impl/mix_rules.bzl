load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro  
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),        
    "mix_env":        attr.string(),
    "build_path":     attr.string(),
    "deps_tree":      attr.label_list(allow_files = True),
    "deps_names":     attr.string_list(),
    "apps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True)
}


# We will invoke Mix to compile the third_party deps for us, but we still
# need some information to copy the compiled deps into our generated _build dir later
BuildOverlay = provider(
    doc = "Provider for a directory which mirrors the Mix _build structure",
    fields = {
        "root_dir": "(File) the directory containing lib/{app}/ebin subfolders",
        "app_dirs": "(dict of string->Files) each app name and its directory",
    }
)
        
# implementation of mix_third_party_deps rule -- compile ALL third_party deps as a single unit
# simpler to implement and avoids duplicate work if one dep depends on another
def _mix_third_party_deps_impl(ctx):
    out_name = "third_party"
    # declare the root directory so that we know where bazel wants us to put everything
    out_dir = ctx.actions.declare_directory(out_name)

    # declare all ebin dirs that will be created so we can provide them with ElixirLibrary 
    ebin_dirs = dict([
        (dep,
         ctx.actions.declare_directory(
             "{output}/{env}/lib/{pkg}/ebin".format(
                 output = out_name,
                 env = ctx.attr.mix_env,
                 pkg = dep,
             )
         )
        )
        for dep in ctx.attr.deps_names
    ])
    
    args = ctx.actions.args()
    args.add_all([
        "elixir", "-e",
        """
        File.cd!("{project_dir}", fn -> Mix.start; Mix.CLI.main; end)
        0 = System.cmd("cp", ["-rL", "{project_dir}/{build_path}", "{out_dir}"]) |> elem(1)
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
        outputs = [out_dir] + ebin_dirs.values(),
        arguments = [args],
        env = {
            # mix needs the home directory to find Hex and rebar3
            "HOME": "/home/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        }
    )

    return [
        ElixirLibrary(
            loadpath = depset(ebin_dirs.values()),
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            root_dir = out_dir,
            app_dirs = ebin_dirs,
        ),
        DefaultInfo(
            files = depset(ebin_dirs.values()),
        )
    ]

mix_third_party_deps = rule(
    _mix_third_party_deps_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items()),
)
    
_elixir_link_attrs = {
    "app": attr.string(),
    "mix_env": attr.string(),
    "third_party": attr.label(),
    "libs": attr.label_list(),
    "dirname": attr.string(
        default = "_build",
    ),
}

def _elixir_link_impl(ctx):
    root_dir_name = "{build_dir}/{mix_env}".format(
        build_dir = ctx.attr.dirname,
        mix_env = ctx.attr.mix_env,
    )

    out_dir = ctx.actions.declare_directory(root_dir_name)

    ebin_dir = ctx.actions.declare_directory(
        "{}/lib/{}/ebin".format(root_dir_name, ctx.attr.app)
    )

    
    precompiled_deps = depset(
        transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.libs]
    )
    # Link time is when we traverse the runtime depset and force runtime deps to be compiled   
    runtime_dep_targets = depset(
        transitive = [dep[ElixirLibrary].runtime_deps for dep in ctx.attr.libs]
    )
    compiled_runtime_deps = depset(
        transitive = [dep[ElixirLibrary].loadpath for dep in runtime_dep_targets.to_list()]
    )
    third_party_dir = ctx.attr.third_party[BuildOverlay].root_dir
    third_party_app_dirs = [ctx.actions.declare_directory("{}/lib/{}/ebin".format(root_dir_name, app))
                            for app, _ in ctx.attr.third_party[BuildOverlay].app_dirs.items()]
    
    modules_to_link = depset(
        direct = [third_party_dir],
        transitive = [precompiled_deps, compiled_runtime_deps],
    )
    ctx.actions.run_shell(
        #inputs = depset(direct = third_party_dirs, transitive = [modules_to_link]),
        inputs = modules_to_link,
        outputs = [out_dir, ebin_dir] + third_party_app_dirs,
        arguments = [
            ctx.actions.args()
            .add(out_dir.path)
            .add(ebin_dir.path)
            .add(ctx.attr.mix_env)
            .add(third_party_dir.path)
            .add_all(precompiled_deps)
            .add_all(compiled_runtime_deps),
        ],
        command = """
        set -x
        echo "what the fuck"
        ROOT=$1 ; shift
        LOCAL_EBIN=$1 ; shift
        MIX_ENV=$1 ; shift
        THIRD_PARTY=$1 ;shift
        cp -r $THIRD_PARTY/$MIX_ENV/* $ROOT
        # since we copy all of OUR compiled code in one `cp`, we should be safe
        # from trying to copy multiple files into the same-named beam file
        cp $@ $LOCAL_EBIN
        find $THIRD_PARTY
        """
    )

    return [
        DefaultInfo(
            files = depset([out_dir]),
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir] + third_party_app_dirs,
                #transitive = [ctx.attr.third_party[ElixirLibrary].loadpath],
            ),
            runtime_deps = depset([]),
        )
    ]
    

elixir_link = rule(
    _elixir_link_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_link_attrs.items()),    
)


# SOURCES: the umbrella project compile_all target depends on the same target of all apps
# CONFIG: each child app depends on the config of the umbrella
# DEPS: each child app depends on the deps of the umbrella
# the reason that we care at all is so that we can build child apps individually?

def mix_project(name = None,
                deps_path = None,
                apps_path = None,
                lib_targets = [],
                mix_env = None,
                **kwargs):

    third_party = name + "_third_party"

    mix_third_party_deps(
        name = third_party,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        mix_env = mix_env,
        deps_tree = native.glob(["{}/**".format(deps_path)]),
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        visibility = ["//visibility:public"],
        **kwargs
    )

    elixir_link(
        name = name + "_all",
        app = name,
        mix_env = mix_env,
        third_party = third_party,
        libs = lib_targets,
        visibility = ["//visibility:public"],
    )
    


