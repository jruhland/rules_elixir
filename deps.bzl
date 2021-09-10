load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("//impl/toolchains/otp:prebuilt.bzl", "prebuilt_otp_release")
load("//impl/toolchains/elixir:from_source.bzl", "elixir_source_archive")
load("//impl/toolchains/elixir:from_system.bzl", "elixir_from_system_path")
load("//impl/toolchains/otp:from_system.bzl", "erlang_from_system_path")

def define_toolchains():
    elixir_source_archive(
        name = "elixir1.8.1",
        version = "1.8.1",
        url = "https://github.com/elixir-lang/elixir/archive/v1.8.1.tar.gz",
        sha256 = "de8c636ea999392496ccd9a204ccccbc8cb7f417d948fd12692cda2bd02d9822",
    )
    elixir_source_archive(
        name = "elixir1.9.4",
        version = "1.9.4",
        url = "https://github.com/elixir-lang/elixir/archive/v1.9.4.tar.gz",
        sha256 = "f3465d8a8e386f3e74831bf9594ee39e6dfde6aa430fe9260844cfe46aa10139",
    )
    elixir_source_archive(
        name = "elixir1.10.4",
        version = "1.10.4",
        url = "https://github.com/elixir-lang/elixir/archive/v1.10.4.tar.gz",
        sha256 = "8518c78f43fe36315dbe0d623823c2c1b7a025c114f3f4adbb48e04ef63f1d9f",
    )
    elixir_from_system_path(
        name = "local_elixir",
    )
    erlang_from_system_path(
        name = "local_erlang",
    )
    prebuilt_otp_release(
        name = "otp22.0.7_macos",
        url = "https://github.com/brexhq/otp_bin/releases/download/release-436418361/otp_22.0.7_macos-10.15_graphical_no-src.tar.gz",
        repository_os = "mac os x",
        strip_prefix = "R22.0.7",
        otp_version = "22.0.7",
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    )
    prebuilt_otp_release(
        name = "otp22.0.7_linux",
        url = "https://github.com/brexhq/otp_bin/releases/download/release-436418361/otp_22.0.7_ubuntu-18.04_headless_no-src.tar.gz",
        repository_os = "linux",
        strip_prefix = "R22.0.7",
        otp_version = "22.0.7",
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )

def register_elixir_toolchains():
    native.register_toolchains(
        # These rules may or may not actually define a toolchain so we use //...
        "@local_erlang//...",
        "@otp22.0.7_macos//...",
        "@otp22.0.7_linux//...",
        "@local_elixir//...",
        # These are always defined
        "@elixir1.8.1//:toolchain",
        "@elixir1.9.4//:toolchain",
        "@elixir1.10.4//:toolchain",
    )

def rules_elixir_dependencies():
    define_toolchains()

    http_file(
        name = "hex",
        downloaded_file_path = "hex-0.20.5.ez",
        urls = ["https://repo.hex.pm/installs/1.8.0/hex-0.20.5.ez"],
        sha256 = "1a3363e4e53d688361eeba8486a24fcd26c389601f1772e822014c79092ab41b",
    )

    http_file(
        name = "rebar",
        urls = ["https://repo.hex.pm/installs/1.0.0/rebar-2.6.2"],
        downloaded_file_path = "rebar",
        executable = True,
        sha256 = "d3eddf77b8448620a650c6d68fd2c4dc01a9060cc808ee0c3f330960dc108a56",
    )

    http_file(
        name = "rebar3",
        urls = ["https://repo.hex.pm/installs/1.0.0/rebar3-3.5.1"],
        downloaded_file_path = "rebar3",
        executable = True,
        sha256 = "a196c84a860bea5d5e68d0146cb04aa0f55332c640f3895a5400a05d684915a1",
    )

    # In case anyone is not satisfied with `erl` not reaping zombies in their containers
    http_file(
        name = "tini",
        urls = ["https://github.com/krallin/tini/releases/download/v0.19.0/tini-amd64"],
        downloaded_file_path = "tini",
        executable = True,
        sha256 = "93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c",
    )
