"""Fortran compilation actions."""

CompileResultInfo = provider(
    "Compilation outputs for a single Fortran source file.",
    fields = ["object", "module"],
)

def _is_free_form(src):
    """Check if source file is free-form Fortran."""
    ext = src.extension
    return ext in ["f90", "f95", "f03", "f08", "F90", "F95", "F03", "F08"]

def _needs_preprocessing(src):
    """Check if source file needs preprocessing."""
    ext = src.extension
    return ext in ["F", "F90", "F95", "F03", "F08"]

def _output_stem(ctx, src):
    """Package-relative output stem for a source, e.g. `sub/util.f90` -> `sub/util_f90`.

    keeps the source dir so same-basename srcs in one target dont collide.
    """
    path = src.short_path
    prefix = ctx.label.package + "/" if ctx.label.package else ""
    if path.startswith("../"):
        # external repo file: `../repo/pkg/file` -> `repo/pkg/file`
        path = path[len("../"):]
        prefix = ctx.label.workspace_root[len("external/"):] + "/" + prefix
    if path.startswith(prefix):
        # src lives under this target's package
        path = path[len(prefix):]
    dirname, sep, basename = path.rpartition("/")
    return dirname + sep + basename.replace(".", "_")

def compile_fortran(ctx, toolchain, src, modules, copts, defines = [], includes = [], hdrs = []):
    """Compile a single Fortran source file.

    Args:
        ctx: Rule context
        toolchain: FortranToolchainInfo provider
        src: Source file to compile
        modules: depset of module directories from deps (FortranInfo.transitive_modules)
        copts: Additional compilation options
        defines: Preprocessor defines (e.g., ['_OPENMP', 'USE_MPI'])
        includes: List of include directories to add to compile line
        hdrs: Header/include files to make available in sandbox

    Returns:
        CompileResultInfo with object and module files
    """

    # Declare output files
    src_base = _output_stem(ctx, src)
    obj = ctx.actions.declare_file(
        "{}_objs/{}.o".format(ctx.label.name, src_base),
    )

    # Declare a directory for module outputs (one per source file)
    # This allows 0 or more .mod files to be created
    module_output_dir = ctx.actions.declare_directory(
        "{}_modules/{}".format(ctx.label.name, src_base),
    )

    # Build arguments
    args = ctx.actions.args()

    # Compiler flags
    args.add_all(toolchain.compiler_flags)
    args.add_all(copts)

    # Free-form or fixed-form
    if _is_free_form(src):
        args.add("-ffree-form")
    else:
        args.add("-ffixed-form")

    # Preprocessing
    if _needs_preprocessing(src):
        # Add preprocessor enable flag (e.g., -cpp or -fpp)
        args.add(toolchain.preprocessor_flag)

        # Add toolchain-level preprocessor flags
        args.add_all(toolchain.preprocessor_flags)

        # Add target-specific preprocessor defines
        for define in defines:
            args.add("-D" + define)
    elif defines:
        # warn user that defines are ignored for lowercase extensions (see #14)
        fail(
            "defines = {} specified but source '{}' has lowercase extension. ".format(
                defines,
                src.basename,
            ) + "Use uppercase extension (.F90, .F95, etc.) for preprocessing.",
        )

    # Module output directory - where this compilation writes .mod files
    args.add(toolchain.module_flag_format.format(module_output_dir.path))

    # Module search paths from dependencies.
    # the depset is expanded at execution time, so a large dependency graph
    # is not flattened once per source during analysis
    args.add_all(modules, format_each = "-I%s", expand_directories = False)

    # Include directories (resolved relative to package, like rules_cc)
    # Validate against "." and ".." to protect workspace (see cc_helper.bzl#L827-L833)
    package = ctx.label.package
    for inc in includes:
        if ".." in inc:
            fail("includes cannot contain '..': " + inc)
        if package:
            inc_path = package + "/" + inc
        else:
            inc_path = inc
        if inc_path == "." or inc_path == "":
            fail("includes resolves to workspace root, which would expose the entire workspace")

        # targets in an external repo live under external/<repo> in the execroot
        if ctx.label.workspace_root:
            inc_path = ctx.label.workspace_root + "/" + inc_path
        args.add("-I" + inc_path)

    # Compile command
    args.add("-c")
    args.add(src.path)
    args.add("-o", obj.path)
    # args.add("-###")

    # Use param file to avoid "Argument list too long" errors on Windows/Linux
    # This is especially important for large projects like LAPACK with thousands of module directories
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    # Run compilation
    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            direct = [src] + hdrs,
            transitive = [modules, toolchain.all_files],
        ),
        outputs = [obj, module_output_dir],
        mnemonic = "FortranCompile",
        progress_message = "Compiling Fortran {}".format(src.short_path),
    )

    return CompileResultInfo(
        object = obj,
        module = module_output_dir,  # Return directory instead of specific file
    )
