"""Unit tests for fortran_import."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//fortran:defs.bzl", "FortranInfo", "fortran_import", "fortran_library", "fortran_test")

_NOT_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

def _prebuilt_impl(ctx):
    """Builds vendor.mod and libvendor.a the way an outside build would have left them."""
    toolchain = ctx.toolchains["//fortran:toolchain_type"].fortran
    src = ctx.file.src
    mod = ctx.actions.declare_file(ctx.label.name + "/vendor.mod")
    obj = ctx.actions.declare_file(ctx.label.name + "/vendor.o")
    lib = ctx.actions.declare_file(ctx.label.name + "/libvendor.a")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = toolchain.compiler_flags + [
            toolchain.module_flag_format.format(mod.dirname),
            "-c",
            src.path,
            "-o",
            obj.path,
        ],
        inputs = depset([src], transitive = [toolchain.all_files]),
        outputs = [mod, obj],
        mnemonic = "TestPrebuiltCompile",
    )
    ctx.actions.run(
        executable = toolchain.archiver,
        arguments = ["rcs", lib.path, obj.path],
        inputs = [obj],
        outputs = [lib],
        mnemonic = "TestPrebuiltArchive",
    )
    return [
        DefaultInfo(files = depset([mod, lib])),
        OutputGroupInfo(mod = depset([mod]), lib = depset([lib])),
    ]

_prebuilt = rule(
    implementation = _prebuilt_impl,
    attrs = {"src": attr.label(allow_single_file = True)},
    toolchains = ["//fortran:toolchain_type"],
)

def _libraries(target):
    return [
        library
        for linker_input in target[CcInfo].linking_context.linker_inputs.to_list()
        for library in linker_input.libraries
    ]

def _own_library(target):
    for linker_input in target[CcInfo].linking_context.linker_inputs.to_list():
        if linker_input.owner == target.label:
            return linker_input.libraries[0]
    return None

def _provides_modules_and_archive_test_impl(ctx):
    """Test that the import offers its .mod files and its archive like a fortran_library."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    modules = [f.basename for f in target[FortranInfo].transitive_modules.to_list()]
    asserts.equals(env, ["vendor.mod"], modules)

    library = _own_library(target)
    asserts.true(env, library != None, "Expected the import to own a library in its CcInfo")
    asserts.equals(env, "libvendor.a", library.static_library.basename)
    asserts.false(env, library.alwayslink, "alwayslink is off unless asked for")

    # the archive holds Fortran code, so the runtime has to come along for cc_binary
    asserts.true(env, len(_libraries(target)) > 1, "Expected the Fortran runtime next to the archive")

    return analysistest.end(env)

provides_modules_and_archive_test = analysistest.make(_provides_modules_and_archive_test_impl)

def _alwayslink_is_passed_on_test_impl(ctx):
    """Test that alwayslink reaches the library dependents link."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, _own_library(target).alwayslink, "Expected alwayslink on the imported archive")

    return analysistest.end(env)

alwayslink_is_passed_on_test = analysistest.make(_alwayslink_is_passed_on_test_impl)

def _modules_only_test_impl(ctx):
    """Test that an import without a library offers modules and nothing to link."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(env, 1, len(target[FortranInfo].transitive_modules.to_list()))
    asserts.equals(env, [], _libraries(target), "Nothing to link, not even the runtime")

    return analysistest.end(env)

modules_only_test = analysistest.make(_modules_only_test_impl)

def _module_file_directory_is_searched_test_impl(ctx):
    """Test that a dependent searches the directory of an imported .mod file."""
    env = analysistest.begin(ctx)

    compiles = [a for a in analysistest.target_actions(env) if a.mnemonic == "FortranCompile"]
    asserts.equals(env, 1, len(compiles))
    searched = [arg for arg in compiles[0].argv if arg.startswith("-I") and arg.endswith("/vendor_prebuilt")]
    asserts.equals(env, 1, len(searched), "Expected one -I for the directory holding vendor.mod")

    return analysistest.end(env)

module_file_directory_is_searched_test = analysistest.make(_module_file_directory_is_searched_test_impl)

def fortran_import_test_suite(name):
    """Test suite for fortran_import.

    Args:
      name: name of the test suite.
    """

    # the "outside" build. everything below takes only its two output files
    _prebuilt(
        name = "vendor_prebuilt",
        src = "vendor.f90",
        tags = ["manual"],
    )

    native.filegroup(
        name = "vendor_mod",
        srcs = [":vendor_prebuilt"],
        output_group = "mod",
        tags = ["manual"],
    )

    native.filegroup(
        name = "vendor_lib",
        srcs = [":vendor_prebuilt"],
        output_group = "lib",
        tags = ["manual"],
    )

    fortran_import(
        name = "vendor",
        modules = [":vendor_mod"],
        static_library = ":vendor_lib",
        tags = ["manual"],
    )

    # Scenario: a program uses a prebuilt module and links its archive
    # Given a fortran_import with a .mod file and a static library
    # When a fortran_test that uses the module is built and run
    # Then it compiles against the .mod file and calls into the archive
    fortran_test(
        name = "uses_imported_module_test",
        srcs = ["main.f90"],
        deps = [":vendor"],
    )

    fortran_library(
        name = "wrapper",
        srcs = ["wrapper.f90"],
        tags = ["manual"],
        deps = [":vendor"],
    )

    # Scenario: imported modules reach dependents of dependents
    # Given a fortran_library whose module uses an imported module
    # And a program that depends on that library only
    # When the program is built and run
    # Then the imported .mod file is found through the library
    # And the imported archive is linked
    fortran_test(
        name = "import_reaches_indirect_dependents_test",
        srcs = ["via_wrapper_main.f90"],
        deps = [":wrapper"],
    )

    # Scenario: an imported module and several sources in one target
    # Given a target with two sources that use each other
    # And one of them using an imported module
    # When it is built and run
    # Then the module pass of the target finds the imported .mod file too
    fortran_test(
        name = "import_with_several_sources_test",
        srcs = [
            "via_wrapper_main.f90",
            "wrapper.f90",
        ],
        deps = [":vendor"],
    )

    # Scenario: what the import hands to dependents
    # Given a fortran_import with a .mod file and a static library
    # When its providers are read
    # Then FortranInfo holds the .mod file
    # And CcInfo holds the archive, not alwayslink, and the Fortran runtime
    provides_modules_and_archive_test(
        name = "provides_modules_and_archive_test",
        target_under_test = ":vendor",
    )

    # Scenario: the directory of an imported .mod file is searched
    # Given a fortran_library depending on a fortran_import
    # When its compile action is created
    # Then the directory holding the .mod file is on the compile line, once
    module_file_directory_is_searched_test(
        name = "module_file_directory_is_searched_test",
        target_under_test = ":wrapper",
    )

    fortran_import(
        name = "vendor_alwayslink",
        alwayslink = True,
        modules = [":vendor_mod"],
        static_library = ":vendor_lib",
        tags = ["manual"],
    )

    # Scenario: alwayslink on an import
    # Given a fortran_import with alwayslink = True
    # When its CcInfo is read
    # Then the archive is marked alwayslink
    alwayslink_is_passed_on_test(
        name = "alwayslink_is_passed_on_test",
        target_under_test = ":vendor_alwayslink",
    )

    fortran_import(
        name = "vendor_modules_only",
        modules = [":vendor_mod"],
        tags = ["manual"],
    )

    # Scenario: an import with modules and no library
    # Given a fortran_import with only .mod files
    # When its providers are read
    # Then FortranInfo holds the .mod file
    # And CcInfo has nothing to link
    modules_only_test(
        name = "modules_only_test",
        target_under_test = ":vendor_modules_only",
    )

    # a library that exists only in shared form
    # macos: the dylib has to carry an @rpath install name (bazel 7.x sets none)
    cc_binary(
        name = "libvendor_shared.so",
        srcs = ["shared.c"],
        linkopts = select({
            "@platforms//os:macos": ["-Wl,-install_name,@rpath/libvendor_shared.so"],
            "//conditions:default": [],
        }),
        linkshared = True,
        tags = ["manual"],
        target_compatible_with = _NOT_WINDOWS,
    )

    fortran_import(
        name = "vendor_shared",
        shared_library = ":libvendor_shared.so",
        tags = ["manual"],
        target_compatible_with = _NOT_WINDOWS,
    )

    # Scenario: an import that only has a shared library
    # Given a fortran_import with a shared library and no static one
    # When a fortran_test linking it is built and run
    # Then the library is linked and found again when the test starts
    # (not on windows: a dll cannot be linked without its import library)
    fortran_test(
        name = "imported_shared_library_runs_test",
        srcs = ["shared_main.f90"],
        target_compatible_with = _NOT_WINDOWS,
        deps = [":vendor_shared"],
    )

    native.test_suite(
        name = name,
        tests = [
            ":alwayslink_is_passed_on_test",
            ":import_reaches_indirect_dependents_test",
            ":import_with_several_sources_test",
            ":imported_shared_library_runs_test",
            ":module_file_directory_is_searched_test",
            ":modules_only_test",
            ":provides_modules_and_archive_test",
            ":uses_imported_module_test",
        ],
    )
