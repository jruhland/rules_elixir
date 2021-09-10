# Use subtree_copy rules to create a multi-layer container image with
# all of the sources and binaries we need at runtime.

load("@io_bazel_rules_docker//container:container.bzl", "container_image", "container_layer", "container_push")
load("@rules_elixir//impl:subtree_copy.bzl", "generated_files_copy", "source_files_copy")
load("@brex_docker//:def.bzl", "brex_elixir_image")

def docker_elixir(name = None, build = None, base_image = None, layers = [], container_push_repo = None, env = {}, root = "app"):
    # These actions just shuffle data around so there is no real point in caching them
    source_copy = name + "_copy_sources"
    source_files_copy(
        name = source_copy,
        mix_build = build,
        root = root,
    )

    sources_layer = name + "_sources_layer"
    container_layer(
        name = sources_layer,
        files = [source_copy],
        data_path = source_copy,
    )

    brexec_layer = "brexec"
    container_layer(
        name = brexec_layer,
        directory = "/usr/bin",
        files = ["@brex//systems/brexinit/brexec"],
    )

    kill_envoy_layer = "kill_envoy"
    container_layer(
        name = kill_envoy_layer,
        directory = "/usr/bin",
        files = ["@brex//systems/brexinit/kill_envoy"],
    )

    bin_copy = name + "_copy_bin"
    generated_files_copy(
        name = bin_copy,
        mix_build = build,
        root = root,
    )

    binaries_layer = name + "_binaries_layer"
    container_layer(
        name = binaries_layer,
        files = [bin_copy],
        data_path = bin_copy,
    )

    tini_layer = name + "_tini"
    container_layer(
        name = tini_layer,
        files = ["@tini//file"],
    )

    # Embed datestamp file into docker image to get around ECR tags-per-digest limit.
    # https://brexhq.atlassian.net/browse/DEVINFRA-442
    # FIXME: Deprecated in favor of d- image tags
    # Will remove once system is stable
    # same_digest_buster = name + "_timestamp_hack"
    # native.genrule(
    #     name = same_digest_buster,
    #     srcs = [],
    #     outs = [same_digest_buster + "_file"],
    #     cmd = "date '+%Y-%m-%d' >$@",
    # )
    # timestamp_layer = name + "_timestamp_layer"
    # container_layer(
    #     name = timestamp_layer,
    #     files = [same_digest_buster],
    #     directory = "/etc",
    # )

    which_base_image = select({
        "@rules_elixir//impl:is_elixir19": "@elixir-run-1.9.4-otp-22.3//image",
        "//conditions:default": "@elixir-run-1.8.1//image",
    })

    brex_elixir_image(
        name = name,
        base = base_image or which_base_image,
        workdir = "/{}/{}".format(root, native.package_name()),
        env = env,
        container_push_repo = container_push_repo,
        layers = [
            tini_layer,
            brexec_layer,
            kill_envoy_layer,
            sources_layer,
            binaries_layer,
        ] + layers,
    )
