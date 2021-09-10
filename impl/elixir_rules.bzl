# Primitive elixir rules which operate at the file level and don't know anything
# about projects or external dependencies or configuration or anything like that

load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

def _path(f):
    return f.path

def _ebin_dir(f, mapper = _path):
    path = mapper(f)

    # .ez archives must be named e.g. `hex-0.20.1.ez` and must include e.g. `hex-0.20.1` as a top directory
    if f.extension == "ez":
        path = path + "/" + f.basename[0:-3]
    return path + "/ebin"

# Suitable for use with Args.map_each which expects you to return a list
def _loadpath_arg(lib_dir):
    return ["--loadpath", _ebin_dir(lib_dir)]

def _elixir_library_impl(ctx):
    out = ctx.actions.declare_directory("lib/" + ctx.label.name)
    compile_deps_lib_dirs = depset(transitive = [dep[ElixirLibrary].lib_dirs for dep in ctx.attr.compile_deps])

    args = ctx.actions.args()
    args.add_all(compile_deps_lib_dirs, expand_directories = False, map_each = _loadpath_arg)
    args.add("--output-base-dir", _ebin_dir(out))
    args.add_all(ctx.files.srcs)

    ctx.actions.run(
        executable = ctx.executable._elixir_prim_compiler,
        outputs = [out],
        inputs = depset(
            direct = [],
            transitive = [depset(ctx.files.srcs), compile_deps_lib_dirs],
        ),
        progress_message = "elixir_compile {}".format(", ".join([s.basename for s in ctx.files.srcs])),
        arguments = [args],
        tools = [ctx.executable._elixir_prim_compiler],
    )

    return [
        DefaultInfo(
            files = depset([out]),
        ),
        ElixirLibrary(
            lib_dirs = depset(
                direct = [out],
                transitive = [compile_deps_lib_dirs],
            ),
        ),
    ]

elixir_library = rule(
    _elixir_library_impl,
    attrs = dict(elixir_common_attrs.items() + {
        "srcs": attr.label_list(
            allow_files = [".ex"],
            doc = "Source files",
        ),
        "compile_deps": attr.label_list(
            default = [],
            providers = [ElixirLibrary],
            doc = "Libraries that must be on the loadpath to compile this library",
        ),
        "_elixir_prim_compiler": attr.label(
            default = Label("@rules_elixir//impl/tools:elixir_prim_compiler"),
            allow_single_file = True,
            executable = True,
            cfg = "target",
        ),
    }.items()),
    toolchains = [
        "@rules_elixir//impl/toolchains/otp:toolchain_type",
        "@rules_elixir//impl/toolchains/elixir:toolchain_type",
    ],
    doc = "Builds a directory containing .beam files for all modules in the source file(s)",
)

def _elixir_prebuilt_library_impl(ctx):
    libs = depset(ctx.files.lib_dirs)
    return [
        DefaultInfo(
            files = libs,
        ),
        ElixirLibrary(
            lib_dirs = libs,
        ),
    ]

elixir_prebuilt_library = rule(
    _elixir_prebuilt_library_impl,
    attrs = {
        "lib_dirs": attr.label_list(allow_files = True),
    },
)

_elixir_script_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex", ".exs"],
        doc = "Script source files to interpret",
    ),
    "eval": attr.string_list(
        default = [],
        doc = "Expressions to evaluate with the -e option",
    ),
    # since scripts don't have a separate compilation step, they just have `deps`,
    # unlike elixir_libraries, which must specify compile and runtime deps separately
    "deps": attr.label_list(allow_files = True),
    "data": attr.label_list(
        allow_files = True,
        doc = "Additional files needed by the script -- these will be added to the script's runfiles",
    ),
    "env": attr.string_dict(
        default = {},
        doc = "Environment variables to set before running the script",
    ),
    "elixir_args": attr.string_list(
        default = [],
        doc = "Additional arguments to be passed to elixir itself",
    ),
    "erl_startup": attr.string(
        default = "-s elixir start_cli",
        doc = "Arguments for telling `erl` to start Elixir (or IEx).",
    ),
    "_script_template": attr.label(
        allow_single_file = True,
        default = Label("//:elixir_script.template"),
    ),
    "_runfiles_lib": attr.label(
        default = Label("@bazel_tools//tools/bash/runfiles"),
    ),
}

# Massage the paths that Bazel gives us so that we can build shell scripts that can find their runfiles
def _rlocation(ctx, f):
    s = f.short_path
    if s[0] == "/":
        # Already an absolute path
        return s
    if s[0:3] == "../":
        # Reference to external workspace, rlocation prefers the absolute path
        return "$(rlocation {})".format(s[3:])

    wsname = f.owner.workspace_name
    if wsname == "":
        # Implicit, but helpful to rlocation
        wsname = ctx.workspace_name
    return "$(rlocation {}/{})".format(wsname, s)

def loadpath_element(ctx, f):
    # .ez archives must be named e.g. `hex-0.20.1.ez` and must include e.g. `hex-0.20.1` as a top directory
    path = _rlocation(ctx, f)
    if f.extension == "ez":
        path = path + "/" + f.basename[0:-3]
    return path + "/ebin"

def _elixir_script_impl(ctx):
    elixir_toolchain = ctx.toolchains["@rules_elixir//impl/toolchains/elixir:toolchain_type"].elixirinfo
    erlang_toolchain = ctx.toolchains["@rules_elixir//impl/toolchains/otp:toolchain_type"].otpinfo
    lib_dirs = depset(
        transitive = [
            elixir_toolchain.lib_dirs,
            depset(transitive = [dep[ElixirLibrary].lib_dirs for dep in ctx.attr.deps if ElixirLibrary in dep]),
        ],
    )

    script_runfiles = ctx.runfiles(
        # Our source files
        files = ctx.files.srcs,
        transitive_files = depset(
            transitive = [
                # erlang/OTP itself
                erlang_toolchain.files,
                # The lib dirs for all the ElixirLibrary targets that we depend on (including elixir itself)
                lib_dirs,
                # Any files passed through the `data` parameter.
                depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.data]),
                # The runfiles of our dependencies.
                depset(transitive = [dep[DefaultInfo].default_runfiles.files for dep in ctx.attr.deps]),
                # The runfiles library itself.
                ctx.attr._runfiles_lib[DefaultInfo].default_runfiles.files,
            ],
        ),
    )
    arg_groups = [
        ["-r {}".format(_rlocation(ctx, f)) for f in ctx.files.srcs],
        ["-e '{}'".format(expr) for expr in ctx.attr.eval],
        [ctx.expand_location(a) for a in ctx.attr.elixir_args],
    ]

    exe = ctx.actions.declare_file("{}_runner.bash".format(ctx.label.name))

    ctx.actions.expand_template(
        template = ctx.file._script_template,
        output = exe,
        substitutions = {
            "%%loadpath%%": " ".join([loadpath_element(ctx, f) for f in lib_dirs.to_list()]),
            "%%erl%%": _rlocation(ctx, erlang_toolchain.erl),
            "%%erl_startup%%": ctx.attr.erl_startup,
            "%%elixir_args%%": " ".join([arg for g in arg_groups for arg in g]),
            "%%env_vars%%": "\n".join([
                "export {}={}".format(var, val)
                for (var, val) in ctx.attr.env.items() + [("LC_ALL", ctx.attr._elixir_locale)]
            ]),
        },
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = exe,
            runfiles = script_runfiles,
        ),
        ElixirLibrary(
            lib_dirs = lib_dirs,
        ),
    ]

elixir_script = rule(
    _elixir_script_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_script_attrs.items()),
    executable = True,
    toolchains = [
        "@rules_elixir//impl/toolchains/otp:toolchain_type",
        "@rules_elixir//impl/toolchains/elixir:toolchain_type",
    ],
    doc = "Elixir script, intended for use with `bazel run` -- does not work outside bazel context",
)

elixir_script_test = rule(
    _elixir_script_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_script_attrs.items()),
    test = True,
    toolchains = [
        "@rules_elixir//impl/toolchains/otp:toolchain_type",
        "@rules_elixir//impl/toolchains/elixir:toolchain_type",
    ],
    doc = "Elixir test; exactly the same as elixir_script but tagged as a test",
)

def elixir_iex(name = None, elixir_args = [], erl_flags = "", **kwargs):
    elixir_script(
        name = name,
        erl_startup = "-user Elixir.IEx.CLI " + erl_flags,
        elixir_args = ["--no-halt"] + elixir_args,
        **kwargs
    )

def elixir_cli_tool(name = None, srcs = [], deps = [], main = None):
    script_deps = []
    gen_lib = name + "__script_compile"
    elixir_library(
        name = gen_lib,
        srcs = srcs,
        compile_deps = deps,
    )

    entrypoint = None
    if main:
        entrypoint = ["{}.main(System.argv)".format(main)]

    elixir_script(
        name = name,
        eval = entrypoint,
        deps = [gen_lib],
        visibility = ["//visibility:public"],
    )
