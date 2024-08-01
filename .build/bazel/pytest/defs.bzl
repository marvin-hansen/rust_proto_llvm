"""Helper Modules to run pytest wrapper

Copyright (c) 2023 Felix Geilert
"""

load("@pydeps_libs//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_test")
load("//.build/bazel/utils:defs.bzl", "copy_targets")

def warn(msg):
    print("{red}WARNING: {msg}{nc}".format(red = "\033[0;31m", msg = msg, nc = "\033[0m"))

def py_test_wrap(
        name,
        srcs,
        deps = [],
        args = [],
        static = [],
        static_prefix = "tests",
        data = [],
        timeout = "moderate",
        **kwargs):
    """PyTests Wrapper that takes care of core dependency and generating main

    Note that the config files can be set to none if they should not be used

    Args:
        name: Name of the test
        srcs: List of test files
        deps: List of dependencies
        args: List of arguments to pass to pytest
        static: List of static files to copy to the test folder
        static_prefix: Prefix to use for the static files
        data: List of data files to include in python build
        timeout: Timeout for the test
        **kwargs: Additional arguments to pass to inner py_test
    """

    # check if name is same as folder prefix in srcs and print warning
    prefixes = [x.split("/")[0].strip(":") for x in srcs]
    prefixes = {x: x for x in prefixes}
    if name in prefixes:
        warn("The name ({}) is also a folder name. This might lead to unexpected behavior.".format(name))

    # copy static files
    cp_data = list(data)
    if len(static) > 0:
        copy_targets(
            name = "{}.static".format(name),
            prefix = static_prefix,
            targets = static,
        )
        cp_data.append(":{}.static".format(name))

    # execute pytest rule with main
    py_test(
        name = name,
        srcs = [
            "//.build/bazel/pytest:pytest_wrapper.py",
        ] + srcs,
        main = "pytest_wrapper.py",
        args = [
            "--capture=no",
            # FEAT: pass with config here? (also put on flags?)
            # NOTE: abandoned for now, since this would only check the pytest files
            # "--black",
            # "--pylint",
            # "--isort",
        ] + args + ["$(location :%s)" % x for x in srcs if not x.startswith("//") and not x.endswith("conftest.py")],
        python_version = "PY3",
        srcs_version = "PY3",
        deps = deps + [
            requirement("pytest"),
            requirement("pytest-cov"),
        ],
        timeout = timeout,
        data = cp_data,
        **kwargs
    )
