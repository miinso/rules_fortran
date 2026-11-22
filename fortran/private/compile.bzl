"""Fortran compilation: the attrs and actions every rule with srcs shares."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":providers.bzl", "FortranInfo")

CompileResultInfo = provider(
    "Compilation outputs for a single Fortran source file.",
    fields = ["object", "module"],
)

# the one place source extensions are listed (without the dot, as File.extension gives them)
_FIXED_FORM_EXTENSIONS = ["f", "F"]
_FREE_FORM_EXTENSIONS = ["f90", "f95", "f03", "f08", "F90", "F95", "F03", "F08"]
_PREPROCESSED_EXTENSIONS = ["F", "F90", "F95", "F03", "F08"]

# attrs of every rule that compiles sources (fortran_library, fortran_binary, fortran_test)
COMPILE_ATTRS = {
    "copts": attr.string_list(
        doc = "Additional compiler options.",
    ),
    "defines": attr.string_list(
        doc = "Preprocessor defines (e.g., ['_OPENMP', 'USE_MPI']). They apply to this target's " +
              "preprocessed sources only, i.e. those with an uppercase extension (.F, .F90, ...).",
    ),
    "deps": attr.label_list(
        providers = [[FortranInfo], [CcInfo]],
        doc = "List of fortran_library or cc_library targets this target depends on. " +
              "Their modules are visible to srcs, and they are linked into the final executable.",
    ),
    "hdrs": attr.label_list(
        allow_files = [".inc", ".mod"],
        doc = "Header/include files (.inc, .mod) for INCLUDE statements and pre-built modules. " +
              "Used by this target's srcs only; they are not passed on to dependents.",
    ),
    "includes": attr.string_list(
        doc = "List of include directories, relative to this package, to add to the compile line. " +
              "They apply to this target only.",
    ),
    "srcs": attr.label_list(
        allow_files = ["." + ext for ext in _FIXED_FORM_EXTENSIONS + _FREE_FORM_EXTENSIONS],
        doc = "List of Fortran source files to compile, in any order. Sources may USE modules " +
              "defined by other sources of the same target; the order is worked out from the sources.",
    ),
}

# the scanner that orders a target's modules. kept out of COMPILE_ATTRS because
# the scanner is a Fortran program itself, built by a rule that must not depend on it
MODULE_ORDER_ATTRS = {
    "_module_order": attr.label(
        default = Label("//fortran/private/tools:module_order"),
        executable = True,
        cfg = "exec",
    ),
}

def _is_free_form(src):
    """Check if source file is free-form Fortran."""
    return src.extension in _FREE_FORM_EXTENSIONS

def _needs_preprocessing(src):
    """Check if source file needs preprocessing."""
    return src.extension in _PREPROCESSED_EXTENSIONS

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

def check_defines(srcs, defines):
    """Fails when defines are set but no source would see them (see #14).

    Only sources with an uppercase extension are preprocessed. A target may
    mix both kinds; the defines then apply to the preprocessed ones.

    Args:
        srcs: list of source Files of the target
        defines: the target's defines
    """
    if defines and srcs and not [src for src in srcs if _needs_preprocessing(src)]:
        fail(
            "defines = {} specified but no source is preprocessed. ".format(defines) +
            "Use an uppercase extension (.F90, .F95, etc.) on the sources that need them.",
        )

def _module_search_dir(module):
    """The directory to search for one entry of FortranInfo.transitive_modules.

    an entry is a directory of .mod files (compiled here), or a single
    prebuilt .mod file (fortran_import)
    """
    return module.path if module.is_directory else module.dirname

def _include_dirs(ctx, includes):
    """Execroot paths for the `includes` attr (resolved relative to the package, like rules_cc)."""
    dirs = []
    package = ctx.label.package
    for inc in includes:
        # no "." and ".." to protect the workspace (see cc_helper.bzl#L827-L833)
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
        dirs.append(inc_path)
    return dirs

def _module_pass(ctx, toolchain, srcs, modules_from_deps):
    """Builds the .mod files of all srcs up front, in dependency order.

    Sources of one target may USE each other's modules in any order, which
    only the source text knows. So:
      1. module_order (a small scanner) reads the srcs and writes the
         module-defining ones in the order they have to be seen
      2. one compiler run, semantics only, takes them in that order and
         writes every .mod file into one directory
    The real per-source compiles then all read that directory and run in
    parallel.

    Args:
        ctx: Rule context
        toolchain: FortranToolchainInfo provider
        srcs: the target's source Files (more than one)
        modules_from_deps: depset of the deps' module directories

    Returns:
        the directory holding every .mod file of this target
    """
    prefix = ctx.label.name + "_module_pass/"
    order = ctx.actions.declare_file(prefix + "order.params")
    empty = ctx.actions.declare_file(prefix + "empty.f90")
    module_dir = ctx.actions.declare_directory(prefix + "modules")

    scan_args = ctx.actions.args()
    scan_args.add(order)
    scan_args.add(empty)
    scan_args.add_all(srcs)
    scan_args.use_param_file("%s", use_always = True)
    scan_args.set_param_file_format("multiline")
    ctx.actions.run(
        executable = ctx.executable._module_order,
        arguments = [scan_args],
        inputs = srcs,
        outputs = [order, empty],
        mnemonic = "FortranModuleOrder",
        progress_message = "Ordering Fortran modules of %{label}",
    )

    args = ctx.actions.args()
    args.add_all(toolchain.compiler_flags)
    args.add_all(ctx.attr.copts)

    # no form or preprocessing switches here: one run sees every kind of
    # source, and the compiler picks both from each file's extension
    if [src for src in srcs if _needs_preprocessing(src)]:
        args.add_all(toolchain.preprocessor_flags)
        args.add_all(ctx.attr.defines, format_each = "-D%s")
    args.add(toolchain.module_flag_format.format(module_dir.path))
    args.add_all(
        modules_from_deps,
        map_each = _module_search_dir,
        format_each = "-I%s",
        uniquify = True,
        expand_directories = False,
    )
    args.add_all(_include_dirs(ctx, ctx.attr.includes), format_each = "-I%s")
    args.add("-fsyntax-only")
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")
    ctx.actions.run(
        executable = toolchain.compiler,
        # the order file is a response file too, read after the flags
        arguments = [args, "@" + order.path],
        inputs = depset(
            direct = srcs + ctx.files.hdrs + [order, empty],
            transitive = [modules_from_deps, toolchain.all_files],
        ),
        outputs = [module_dir],
        mnemonic = "FortranModules",
        progress_message = "Building Fortran modules of %{label}",
    )
    return module_dir

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

        # Add target-specific preprocessor defines.
        # sources that are not preprocessed get none; check_defines() rejects
        # a target where that leaves the defines unused
        for define in defines:
            args.add("-D" + define)

    # Module output directory - where this compilation writes .mod files
    args.add(toolchain.module_flag_format.format(module_output_dir.path))

    # Module search paths from dependencies.
    # the depset is expanded at execution time, so a large dependency graph
    # is not flattened once per source during analysis
    args.add_all(
        modules,
        map_each = _module_search_dir,
        format_each = "-I%s",
        uniquify = True,
        expand_directories = False,
    )

    args.add_all(_include_dirs(ctx, includes), format_each = "-I%s")

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

def compile_sources(ctx, toolchain):
    """Compiles all srcs of a target that has COMPILE_ATTRS.

    Args:
        ctx: Rule context
        toolchain: FortranToolchainInfo provider

    Returns:
        struct with
          objects: list of object files, one per source
          modules: list of the module directories dependents need
          dep_modules: list of the deps' transitive module depsets
    """
    srcs = ctx.files.srcs

    # sources that USE a module need its `*.mod` file at compile time
    dep_modules = [dep[FortranInfo].transitive_modules for dep in ctx.attr.deps if FortranInfo in dep]
    modules_from_deps = depset(transitive = dep_modules)

    check_defines(srcs, ctx.attr.defines)

    # with several sources, their modules are built first so the sources can
    # USE each other. a single source has no siblings and skips that (so does
    # the rule that builds the scanner itself, which has no _module_order)
    shared_modules = None
    if len(srcs) > 1 and hasattr(ctx.executable, "_module_order"):
        shared_modules = _module_pass(ctx, toolchain, srcs, modules_from_deps)
        visible_modules = depset([shared_modules], transitive = dep_modules)
    else:
        visible_modules = modules_from_deps

    # `*.f90` -> `*.o` (always) + `*.mod` (if the source defines a MODULE)
    # https://fortran-lang.org/learn/building_programs/include_files/#include-files-and-modules
    objects = []
    modules = []
    for src in srcs:
        result = compile_fortran(
            ctx = ctx,
            toolchain = toolchain,
            src = src,
            modules = visible_modules,
            copts = ctx.attr.copts,
            defines = ctx.attr.defines,
            includes = ctx.attr.includes,
            hdrs = ctx.files.hdrs,
        )
        objects.append(result.object)
        modules.append(result.module)

    return struct(
        objects = objects,
        # after a module pass one directory holds them all; the per-source
        # directories are then just where each compile wrote its own copy
        modules = [shared_modules] if shared_modules else modules,
        dep_modules = dep_modules,
    )
