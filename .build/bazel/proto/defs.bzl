"""Build a helper for Flywheel Proto Compile

Copyright (c) 2023 Felix Geilert
"""

load("@rules_proto//proto:defs.bzl", "proto_library")
load("@rules_python//python:proto.bzl", "py_proto_library")
load("@rules_rust//proto/protobuf:defs.bzl", "rust_proto_library")
load("@rules_rust//proto/prost:defs.bzl", "rust_prost_library")

# define the mode for output (NO_PREFIX, PREFIXED) allows to make imports easier
# NOTE: this is essential to make paths work correctly
# mode = "NO_PREFIX_FLAT"

def fly_proto(
        name,
        srcs = [],
        deps = [],
        visibility = ["//visibility:public"],
        **kwargs):
    """Macro to create proto rules in all languages.

    Args:
        name: The name of the proto.
        srcs: The source files of the proto.
        deps: The dependencies of the proto.
        visibility: The visibility of the proto.
        **kwargs: Additional arguments to pass to py_binary.
    """

    proto_library(
        name = name,
        srcs = srcs,
        deps = deps,
        visibility = visibility,
        **kwargs
    )

    py_proto_library(
        name = "{}.py".format(name),
        # output_mode = mode,
        visibility = visibility,
        deps = [":{}".format(name)],
    )

    rust_proto_library(
        name = "{}.rs".format(name),
        visibility = visibility,
        deps = [":{}".format(name)],
    )

    # FIXME: validate if needed
    rust_prost_library(
        name = "{}.prost".format(name),
        proto = ":{}".format(name),
        visibility = ["//visibility:public"],
    )

    # TODO: add go compiler [LIN:MED-762]
    # go_proto_library(
    #     name = "{}.go".format(name),
    #     importpath = "example.com/foo_proto",
    #     proto = ":{}".format(name),
    # )

    # TODO: add rust compiler [LIN:MED-441]
    # TODO: add typescript compiler [LIN:MED-763]

    # FEAT: Add DART compiler here
