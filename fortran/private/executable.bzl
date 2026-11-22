"""Shared implementation of the executable rules (fortran_binary, fortran_test)."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "check_defines", "compile_fortran")
load(":providers.bzl", "FortranInfo")

def fortran_executable_impl(ctx, mnemonic, kind):
    """Compiles srcs and links them with deps into an executable.

    Args:
        ctx: rule context of a fortran_binary or fortran_test.
        mnemonic: mnemonic of the link action.
        kind: word for the progress message, "binary" or "test".

    Returns:
        list of providers (DefaultInfo).
    """
    toolchain = ctx.toolchains["@rules_fortran//fortran:toolchain_type"].fortran

    # Collect dependencies from both Fortran and C/C++ libraries.
    # modules come from FortranInfo; everything link-related comes from CcInfo
    # only (fortran_library puts its archive, linkopts and the runtime there),
    # so the link line keeps the one order CcInfo already got right.
    dep_modules = []
    link_flags = []
    cc_libraries = []
    cc_objects = []
    cc_dynamic_libs = []
    cc_linker_inputs = []

    for dep in ctx.attr.deps:
        if FortranInfo in dep:
            dep_modules.append(dep[FortranInfo].transitive_modules)
        if CcInfo in dep:
            cc_linker_inputs.append(dep[CcInfo].linking_context.linker_inputs)

    # merge first: a linker input shared by several deps is visited once,
    # so its libraries and link flags are not repeated
    for linker_input in depset(transitive = cc_linker_inputs, order = "topological").to_list():
        for library in linker_input.libraries:
            # one artifact per library, like rules_cc does for a static link:
            # static > pic static > interface lib > dynamic
            if library.static_library != None:
                archive = library.static_library
                objects = library.objects
            elif library.pic_static_library != None:
                archive = library.pic_static_library
                objects = library.pic_objects
            else:
                archive = None
                objects = None

            if archive != None:
                if library.alwayslink and objects:
                    # alwayslink: every object must be linked, even unreferenced ones.
                    # the linker only pulls needed members out of an archive, so pass
                    # the objects in its place.
                    # TODO: alwayslink archives without objects (cc_import) need
                    # whole-archive flags
                    cc_objects.extend(objects)
                else:
                    cc_libraries.append(archive)
            elif library.interface_library != None:  # .lib on windows
                cc_libraries.append(library.interface_library)
                if library.dynamic_library != None:
                    cc_dynamic_libs.append(library.dynamic_library)
            elif library.dynamic_library != None:
                cc_libraries.append(library.dynamic_library)
                cc_dynamic_libs.append(library.dynamic_library)

        link_flags.extend(linker_input.user_link_flags)

    # Compile sources
    fortran_objects = []
    modules_from_deps = depset(transitive = dep_modules)
    check_defines(ctx.files.srcs, ctx.attr.defines)
    for src in ctx.files.srcs:
        result = compile_fortran(
            ctx = ctx,
            toolchain = toolchain,
            src = src,
            modules = modules_from_deps,
            copts = ctx.attr.copts,
            defines = ctx.attr.defines,
            includes = ctx.attr.includes,
            hdrs = ctx.files.hdrs,
        )
        fortran_objects.append(result.object)

    # Libraries stay in CcInfo's topological order (dependents before their
    # dependencies), which single-pass linkers like GNU ld need.
    # Always include runtime libraries from toolchain (even if no deps), and
    # keep them last: fortran_library deps also carry them via CcInfo, at
    # whatever position the merge gave them.
    runtime_libs = toolchain.runtime_libraries
    all_libraries = [lib for lib in cc_libraries if lib not in runtime_libs] + runtime_libs

    # Combine all object files (Fortran + C/C++)
    all_objects = fortran_objects + cc_objects

    # Link executable. named from the target platform (not the host), so
    # cross builds get it right
    is_windows = ctx.target_platform_has_constraint(
        ctx.attr._windows_constraint[platform_common.ConstraintValueInfo],
    )
    executable = ctx.actions.declare_file(ctx.label.name + (".exe" if is_windows else ""))

    args = ctx.actions.args()

    # Add all object files first (both Fortran and C/C++)
    for obj in all_objects:
        args.add(obj)

    # Add libraries in topological order with deduplication
    # rules_cc did use a set to dedup libraries
    seen_libraries = {}
    for lib in all_libraries:
        if lib not in seen_libraries:
            args.add(lib)
            seen_libraries[lib] = True

    args.add("-o", executable.path)
    args.add_all(toolchain.linker_flags)

    # Add link flags from dependencies
    # say we trust `cc_common.merge_cc_infos` to do its job
    args.add_all(link_flags)
    args.add_all(ctx.attr.linkopts)

    # Use param file to avoid (possible) "Argument list too long" errors
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    ctx.actions.run(
        executable = toolchain.linker,
        arguments = [args],
        inputs = depset(
            direct = all_objects + all_libraries,
            transitive = [toolchain.all_files],
        ),
        outputs = [executable],
        mnemonic = mnemonic,
        progress_message = "Linking Fortran {} {}".format(kind, executable.short_path),
        use_default_shell_env = True,
    )

    # symlink shared libs next to exe for app-local DLL resolution (windows)
    # mirrors rules_cc _create_dynamic_libraries_copy_actions:
    # only copy DLLs from different packages to avoid conflicting actions
    dll_copies = []
    for dll in cc_dynamic_libs:
        if ctx.label.package != dll.owner.package or ctx.label.workspace_name != dll.owner.workspace_name:
            dll_copy = ctx.actions.declare_file(dll.basename)
            ctx.actions.symlink(output = dll_copy, target_file = dll)
            dll_copies.append(dll_copy)
        else:
            dll_copies.append(dll)

    # Create runfiles
    # See: https://bazel.build/extending/rules#runfiles
    runfiles = ctx.runfiles(files = [executable] + dll_copies + ctx.files.data).merge_all([
        target[DefaultInfo].default_runfiles
        for target in ctx.attr.deps + ctx.attr.data
    ])

    # env for `bazel run` and `bazel test`; values may use $(location) of data
    environment = {
        key: ctx.expand_location(value, ctx.attr.data)
        for key, value in ctx.attr.env.items()
    }

    return [
        DefaultInfo(
            files = depset([executable]),
            executable = executable,
            runfiles = runfiles,
        ),
        RunEnvironmentInfo(
            environment = environment,
            # env_inherit exists on fortran_test only
            inherited_environment = getattr(ctx.attr, "env_inherit", []),
        ),
    ]

# attrs only fortran_test has, on top of EXECUTABLE_ATTRS
TEST_ONLY_ATTRS = {
    "env_inherit": attr.string_list(
        doc = "Names of environment variables to pass through from the environment `bazel test` runs in.",
    ),
}

# attrs common to fortran_binary and fortran_test
EXECUTABLE_ATTRS = {
    "_windows_constraint": attr.label(
        default = Label("@platforms//os:windows"),
    ),
    "copts": attr.string_list(
        doc = "Additional compiler options.",
    ),
    "data": attr.label_list(
        allow_files = True,
        doc = "Files needed at run time, added to the runfiles.",
    ),
    "defines": attr.string_list(
        doc = "Preprocessor defines for .F files (e.g., ['_OPENMP', 'USE_MPI']).",
    ),
    "env": attr.string_dict(
        doc = "Environment variables to set when the executable is run by `bazel run` or `bazel test`. " +
              "Values may use `$(location)` of targets in `data`.",
    ),
    "deps": attr.label_list(
        providers = [[FortranInfo], [CcInfo]],
        doc = "List of fortran_library or cc_library targets to link against.",
    ),
    "hdrs": attr.label_list(
        allow_files = [".inc", ".mod"],
        doc = "Header/include files (.inc, .mod) for INCLUDE statements and pre-built modules.",
    ),
    "includes": attr.string_list(
        doc = "List of include directories to add to the compile line.",
    ),
    "linkopts": attr.string_list(
        doc = "Additional linker options.",
    ),
    "srcs": attr.label_list(
        allow_files = [".f", ".f90", ".f95", ".f03", ".f08", ".F", ".F90", ".F95", ".F03", ".F08"],
        doc = "List of Fortran source files to compile.",
    ),
}
