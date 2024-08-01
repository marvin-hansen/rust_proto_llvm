"""Helper fules for generating a filegroup from a list of filegroups

Code partly from: https://stackoverflow.com/questions/38905256/bazel-copy-multiple-files-to-binary-directory

Copyright (c) 2023 Felix Geilert
"""

def _process_files(target, base, prefix = None):
    """Retrieves files from a specific target.

    Args:
        target (list of files): The target to retrieve the files from.
        base (str): The base path to remove from the files.
        prefix (str): The prefix to add to the files.

    Returns:
        A list of tuples containing the file and the path to copy it to.
    """
    outs = []
    for f in target:
        # get current path
        f_path = f.path

        # remove any bazel prefix (from bazel-out to bin folder)
        if f_path.startswith("bazel-out"):
            # find first match of bin folder
            f_path = f_path[f_path.find("bin") + 4:]

        # rebases the file
        if base and f_path.startswith(base):
            f_path = f.path[len(base):]

        # checks for prefix
        if prefix and prefix != "":
            f_path = prefix + "/" + f_path

        # appends to output
        outs.append((f, f_path))
    return outs

def _copy_targets_impl(ctx):
    # retrieve the prefix
    prefix = ctx.attr.prefix
    all_input_files = []
    py_retain = ctx.attr.retain_python_path

    def copy_py_files(files, base):
        if py_retain:
            return _process_files(files, None)
        else:
            return _process_files(files, base, prefix)

    # iterate through all targets available
    for t in ctx.attr.targets:
        # skip project external references
        if ctx.attr.copy_external == False and t.label.workspace_name != "":
            continue

        # retrieve the current base package from the file (for removal)
        base = t.label.package + "/"

        # validate type of package
        if PyInfo in t:
            # retreive the info
            py_info = t[PyInfo]
            files = [src for src in py_info.transitive_sources.to_list() if not src.path.startswith("external")]

            # get workspace root for current package
            # base = t.label.workspace_root + "/" if py_retain else base

            #fail("test")
            all_input_files += copy_py_files(files, base)

            # Include the main file in the case of py_binary
            if DefaultInfo in t and hasattr(t[DefaultInfo], "executable"):
                # retrieve main file
                main_file = t[DefaultInfo].executable

                # rebase the file
                f_path = main_file.path if py_retain else main_file.path.replace(base, "")
                if not py_retain and prefix and prefix != "":
                    f_path = prefix + "/" + f_path

                # add to outputs
                all_input_files.append((main_file, f_path))
        elif hasattr(t, "files"):
            # default copy process for file groups
            all_input_files += _process_files(t.files.to_list(), base, prefix)
        else:
            fail("Unsupported target type: {}. Currently only filegroups and py_* are supported!".format(t.label))

    # Deduplicate all_input_files
    unique_files = {}
    for f, f_path in all_input_files:
        if f_path not in unique_files:
            unique_files[f_path] = f

    all_input_files = [(f, f_path) for f_path, f in unique_files.items()]

    # iterate through all detected files
    all_outputs = []
    for f, f_path in all_input_files:
        # declare the target as an explicit file and add to outputs
        out = ctx.actions.declare_file(f_path)
        all_outputs.append(out)

        # run a shell script to actually copy the file
        ctx.actions.run_shell(
            outputs = [out],
            inputs = depset([f]),
            arguments = [f.path, out.path],
            command = "cp $1 $2",
        )

    # sanity check (assume all files are copied)
    if len(all_input_files) != len(all_outputs):
        fail("Output count should be 1-to-1 with input count.")

    # return info of outputs to the build system (and files modified)
    return [
        DefaultInfo(
            files = depset(all_outputs),
            runfiles = ctx.runfiles(files = all_outputs),
        ),
    ]

#! Rule that will copy provided targets to the given directory
copy_targets = rule(
    implementation = _copy_targets_impl,
    attrs = {
        # label list of targets to copy
        "targets": attr.label_list(),
        # optional folder prefix to apply to the copied files
        "prefix": attr.string(default = ""),
        # defines if external data should be copied
        "copy_external": attr.bool(default = False),
        # defines if python elements should retain full path
        "retain_python_path": attr.bool(default = True),
    },
)

def _copy_py_binary_deps_impl(ctx):
    output_dir = ctx.attr.output_dir

    # Gather all input files from the py_binary target and its dependencies
    all_input_files = []
    for dep in ctx.attr.py_binary[DefaultInfo].data_runfiles.files.to_list():
        all_input_files.append(dep)

    all_outputs = []
    for f in all_input_files:
        out = ctx.actions.declare_file("{}/{}".format(output_dir, f.basename))
        all_outputs.append(out)
        ctx.actions.run_shell(
            outputs = [out],
            inputs = depset([f]),
            arguments = [f.path, out.path],
            command = "cp $1 $2",
        )

    return [
        DefaultInfo(
            files = depset(all_outputs),
            runfiles = ctx.runfiles(files = all_outputs),
        ),
    ]

copy_py_binary_deps = rule(
    implementation = _copy_py_binary_deps_impl,
    attrs = {
        "py_binary": attr.label(),
        "output_dir": attr.string(),
    },
)

# DEBT: this code should be refactored to be more readable [LIN:MED-641]
def _generate_requirements_txt_impl(ctx):
    py_target = ctx.attr.py_target

    # Check if the provided target is a py_library, py_binary, or py_test
    if (
        not hasattr(py_target[DefaultInfo], "runfiles") and
        not hasattr(py_target[DefaultInfo], "executable") and
        not hasattr(py_target[DefaultInfo], "files_to_run")
    ):
        fail("Provided target is not a py_binary (required for materialization).")

    # Get the prefix and the requirements file
    prefix = ctx.attr.prefix
    if len(prefix) > 0:
        prefix += "/"
    req_file = ctx.actions.declare_file("{}{}".format(prefix, ctx.attr.req_file))

    # Collect all materialized output files of the py_binary
    materialized_output_files = py_target[DefaultInfo].data_runfiles.files.to_list()

    # Collect metadata for external dependencies
    metadata_files = [f for f in materialized_output_files if f.basename == "METADATA"]

    # DEBT: old script is deprecated and should be removed [LIN:MED-641]
    # Generate a shell script to process METADATA files and create the requirements.txt
    # script = "\n".join([
    #     "#!/bin/bash",
    #     "set -eu",
    #     "",
    #     "update_version() {",
    #     "  name=\"$1\"",
    #     "  version=\"$2\"",
    #     # NOTE: pytorch hack to ensure proper installation
    #     "  if [ \"$name\" == \"torch\" ]; then",
    #     "    name=\"-f https://download.pytorch.org/whl/torch_stable.html\ntorch\"",
    #     "    version=\"$version+cpu\"",
    #     "  fi",
    #     "  for i in \"${!library_names[@]}\"; do",
    #     "    if [ \"${library_names[$i]}\" = \"$name\" ]; then",
    #     "      if [ \"$(printf '%s\\n' \"$version\" \"${library_versions[$i]}\")\" = \"$version\" ]; then",
    #     "        library_versions[$i]=\"$version\"",
    #     "      fi",
    #     "      return",
    #     "    fi",
    #     "  done",
    #     "  library_names+=(\"$name\")",
    #     "  library_versions+=(\"$version\")",
    #     "}",
    #     "",
    #     "library_names=()",
    #     "library_versions=()",
    #     "output_file=\"$1\"",
    #     "shift",
    #     "",
    #     "for path in \"$@\"; do",
    #     "  if [ ! -f \"$path\" ]; then",
    #     "    continue",
    #     "  fi",
    #     "  name=\"\"",
    #     "  version=\"\"",
    #     "  while IFS= read -r line; do",
    #     "    case $line in",
    #     "      Name:*)",
    #     "        name=\"${line#Name: }\"",
    #     "        name=\"$(echo \"$name\" | tr -d '\r' | tr -d '\n')\"",
    #     "        ;;",
    #     "      Version:*)",
    #     "        version=\"${line#Version: }\"",
    #     "        version=\"$(echo \"$version\" | tr -d '\r' | tr -d '\n')\"",
    #     "        ;;",
    #     "    esac",
    #     "    if [ -n \"$name\" ] && [ -n \"$version\" ]; then",
    #     "      update_version \"$name\" \"$version\"",
    #     "      name=\"\"",
    #     "      version=\"\"",
    #     "    fi",
    #     "  done < \"$path\"",
    #     "done",
    #     "touch \"$output_file\"",
    #     "{",
    #     "  for i in \"${!library_names[@]}\"; do",
    #     "    echo \"${library_names[$i]}==${library_versions[$i]}\"",
    #     "  done",
    #     "} > \"$output_file\"",
    # ])

    # Create a file for the script
    # script_file = ctx.actions.declare_file("metadata_processing_script.sh")
    # ctx.actions.write(script_file, script, is_executable = True)

    # NEW VERSION: use py_meta_script in the same folder as rule
    script_file = ctx.executable._meta_script

    mfiles = ""
    for f in metadata_files:
        mfiles += f.path + " "

    # Run the script with the metadata files as input
    ctx.actions.run_shell(
        inputs = metadata_files + [script_file],
        outputs = [req_file],
        command = "bash {script} {req_file} {metadata_files}".format(
            script = script_file.path,
            metadata_files = mfiles,
            req_file = req_file.path,
        ),
    )

    return [
        DefaultInfo(
            files = depset([req_file]),
            runfiles = ctx.runfiles(files = [req_file]),
        ),
    ]

py_gen_reqs = rule(
    implementation = _generate_requirements_txt_impl,
    attrs = {
        # binary to generate requirements.txt for
        "py_target": attr.label(),
        # output directory for requirements.txt
        "prefix": attr.string(default = ""),
        # file name
        "req_file": attr.string(default = "requirements.txt"),
        "_meta_script": attr.label(
            default = Label("//.build/bazel/utils:py_meta_script"),
            cfg = "exec",
            executable = True,
        ),
    },
)

def _zip_folder_impl(ctx):
    # Define the output zip file
    out_name = ctx.attr.out if ctx.attr.out != "" else ctx.label.name
    target = ctx.attr.target_folder
    if target != "" and not target.endswith("/"):
        target += "/"

    # check if zip extension is already present
    if not out_name.endswith(".zip"):
        out_name += ".zip"
    output_zip = ctx.actions.declare_file(out_name)

    # TODO: limit the zip command to the specified folder (and extract all sources)
    files = {}
    apx = "*"

    for f in ctx.files.srcs:
        # check for prefix match either against regex .*/bin or **/bin/${target}
        # and set the resulting full path to the fldr variable
        fldr = "."
        path_seg = f.path.split("/")
        found_bin = False
        cur_path = ""
        for i in range(len(path_seg)):
            cur_path += path_seg[i] + "/"
            if cur_path.endswith(target):
                fldr = cur_path
                break
            if cur_path.endswith("bin/") and not found_bin:
                fldr = cur_path
                found_bin = True
        if fldr == ".":
            fldr = f.path

        # get the output directory for the files
        #zip_cmd = "zip -u -r {out} {pos}".format(out = output_zip.path, pos = fldr)
        files[fldr] = True

    folders = list(files.keys())
    zip_cmd = "cur=$(pwd) && cd {pos} && zip -r {out} . && cd $cur".format(out = output_zip.path, pos = folders[0])
    folders = folders[1:]
    for f in folders:
        zip_cmd += " && cur=$(pwd) && cd {pos} && zip -u -r {out} . && cd $cur".format(out = output_zip.path, pos = f)

    # Create the action that runs the zip command
    ctx.actions.run_shell(
        outputs = [output_zip],
        inputs = ctx.files.srcs,
        command = zip_cmd,
        mnemonic = "ZipFolder",
        use_default_shell_env = True,
    )

    # Return the output zip file as DefaultInfo
    return DefaultInfo(files = depset([output_zip]))

zip_folder = rule(
    implementation = _zip_folder_impl,
    attrs = {
        "out": attr.string(
            default = "",
            doc = "Name of the output zip file.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "List of files to be included in the zip.",
        ),
        "target_folder": attr.string(
            doc = "Inner folder that is targeted for the zip file.",
        ),
    },
    doc = "Zips a complete folder into a single zip file.",
)

# def _py_run_impl(ctx):
#     # Get the name of the py_binary
#     py_binary = ctx.attr.py_binary

#     # Execute the py_binary and generate the output folder
#     # output_dir = ctx.actions.declare_directory(ctx.outputs.out)

#     # Declare the output directory as a directory that needs to be created
#     # ctx.actions.declare_directory(output_dir)

#     ctx.actions.run(
#         inputs = [py_binary],
#         outputs = ctx.outputs.out,
#         # arguments = ["--output_dir", output_dir],
#         executable = py_binary,
#     )

#     # Declare the output files
#     # output_files = ctx.actions.glob([f"{output_dir}/**"])
#     # for output_file in output_files:
#     #     ctx.actions.declare_file(output_file)

#     # Create the pkg_files rule
#     # ctx.actions.run(
#     #     inputs = [output_dir],
#     #     outputs = [ctx.outputs.out],
#     #     arguments = ["--output_dir", output_dir],
#     #     executable = "@my_pkg_files//:pkg_files",
#     # )

# py_run = rule(
#     implementation = _py_run_impl,
#     attrs = {
#         "py_binary": attr.label(providers = [PyRuntimeInfo], cfg = "exec", executable = True, mandatory = True),
#         "out": attr.output_list(doc = "Content of output folder of the rule execution"),
#     },
# )

# def _py_run_impl(ctx):
#     # Get the name of the py_binary
#     py_binary = ctx.attr.py_binary

#     # get name
#     bin_name = py_binary.label.name

#     # Execute the py_binary and generate the output folder
#     output_dir = ctx.actions.declare_directory("_run_{}".format(bin_name))
#     ctx.actions.run(
#         inputs = [py_binary],
#         outputs = [output_dir],
#         arguments = [],
#         executable = str(py_binary.path),
#     )

#     # Declare the output files
#     output_files = ctx.actions.glob(["{}/**".format(output_dir)])
#     for output_file in output_files:
#         ctx.actions.declare_file(output_file)

#     # Return the output directory as the output of the rule
#     return [DefaultInfo(files = depset([output_dir]))]

# py_run = rule(
#     implementation = _py_run_impl,
#     attrs = {
#         "py_binary": attr.label(
#             providers = [PyRuntimeInfo],
#             cfg = "exec",
#             executable = True,
#             mandatory = True,
#         ),
#         "out": attr.output_list(
#             doc = "Content of output folder of the rule execution",
#         ),
#     },
# )

def absolute_label(label):
    if label.startswith("@") or label.startswith("/"):
        return label
    if label.startswith(":"):
        return "//" + native.package_name() + label
    return "@" + native.repository_name() + "//" + native.package_name() + ":" + label

def py_run(
        name,
        py_binary,
        out,
        out_arg = "zip",
        **kwargs):
    """Executes a py_binary and stores the output in a zip file.

    Args:
        name (str): The name of the rule.
        py_binary (str): The label of the py_binary to execute.
        out (str): The name of the output zip file (without ending)
        out_arg (str): The name of the argument to pass to the py_binary.
        **kwargs: Additional arguments to pass to the native.genrule function.
    """
    fail("py_run is not yet implemented")
    # native.genrule(
    #     name = name,
    #     srcs = [py_binary],
    #     outs = ["{}.zip".format(out)],
    #     # cmd = "bazel run {0} -- --{1} $@".format(absolute_label(py_binary), out_arg),
    #     cmd = "echo \"$(locations {0})\" | cut -d \" \" -f 1 | {{ read cmd; eval \"$$cmd --{1} $@\" }}".format(py_binary, out_arg),
    #     **kwargs
    # )
