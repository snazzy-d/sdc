#!/usr/bin/env python3
"""A utility to update LLVM IR CHECK lines in SDC FileCheck test files.

Example RUN lines in .d test files:

// RUN: %sdc %s -O2 -S --emit-llvm -o - | FileCheck %s

Usage:

% tools/update_sdc_test_checks.py --sdc-bin=bin/sdc test/llvm/downcast.d
"""

from __future__ import print_function

from sys import stderr
from traceback import print_exc
import argparse
import collections
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

# UpdateTestChecks is not installed with LLVM. It must already be on
# PYTHONPATH, or LLVM_UTILS must name the LLVM source tree or its utils/.
try:
    from UpdateTestChecks import common
except ModuleNotFoundError:
    llvm_utils = os.environ.get("LLVM_UTILS", "")
    found = None
    if llvm_utils:
        root = os.path.abspath(llvm_utils)
        for rel in ("", "utils", os.path.join("llvm", "utils")):
            candidate = os.path.join(root, rel)
            if os.path.isdir(os.path.join(candidate, "UpdateTestChecks")):
                found = candidate
                break
    if not found:
        sys.stderr.write(
            "UpdateTestChecks not found on PYTHONPATH. "
            "Set LLVM_UTILS to the LLVM source tree or its utils/ directory.\n"
        )
        sys.exit(1)
    sys.path.insert(0, found)
    from UpdateTestChecks import common

# get_autogennote_suffix skips a fixed set of destinations (--clang, --opt,
# --llvm-bin). There is no flag to add one. Hide --sdc-bin from that walk.
_autogennote_suffix = common.get_autogennote_suffix


def _autogennote_suffix_without_sdc(parser, args):
    class _Parser(object):
        def __getattr__(self, name):
            return getattr(parser, name)

    wrapped = _Parser()
    wrapped._actions = [
        action for action in parser._actions if action.dest != "sdc_bin"
    ]
    return _autogennote_suffix(wrapped, args)


common.get_autogennote_suffix = _autogennote_suffix_without_sdc

SUBST = {
    "%sdc": [],
}


def d_name(mangled):
    """Last identifier of a D mangled qualified name, before the type encoding."""
    if not mangled.startswith("_D"):
        return mangled
    index = 2
    last = None
    while index < len(mangled) and mangled[index].isdigit():
        end = index
        while end < len(mangled) and mangled[end].isdigit():
            end += 1
        length = int(mangled[index:end])
        ident = mangled[end : end + length]
        if (
            len(ident) != length
            or not ident
            or not (ident[0].isalpha() or ident[0] == "_")
        ):
            break
        last = ident
        index = end + length
    return last or mangled


def get_line2func_list(filename, mangled_names):
    """Map source line -> (spell, mangled, search), as clang's AST dump did.

    sdc has no -ast-dump=json, and -g dies in DebugInfoTypeGen. The tuples
    are the same shape the rest of this file already consumes: the search
    string must appear on the source line.
    """
    with open(filename) as handle:
        lines = handle.read().splitlines()
    ret = collections.defaultdict(list)
    used = set()
    for mangled in mangled_names:
        spell = d_name(mangled)
        for index, line in enumerate(lines):
            if index in used:
                continue
            # A member call (a.foo()) is not a definition. Otherwise B.foo
            # binds to the call in fooA and the real method is left unmatched.
            if re.search(r"(?<!\.)\b%s\s*\(" % re.escape(spell), line):
                ret[index].append((spell, mangled, spell))
                used.add(index)
                break
    if not ret:
        common.warn("Did not find any functions in " + filename)
    return ret


def str_to_commandline(value):
    if not value:
        return []
    return shlex.split(value)


def infer_dependent_args(args):
    if not args.sdc_bin:
        args.sdc_bin = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../bin/sdc")
        )


def find_executable(executable):
    _, ext = os.path.splitext(executable)
    if sys.platform == "win32" and ext != ".exe":
        executable = executable + ".exe"

    return shutil.which(executable)


def config():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--sdc-bin", help='"sdc" executable, defaults to bin/sdc next to this script'
    )
    parser.add_argument(
        "--sdc-args",
        default=[],
        type=str_to_commandline,
        help="Space-separated extra args to sdc, e.g. --sdc-args=-v",
    )
    parser.add_argument(
        "--functions",
        nargs="+",
        help="A list of function name regexes. "
        "If specified, update CHECK lines for functions matching at least one regex",
    )
    parser.add_argument(
        "--x86_extra_scrub",
        action="store_true",
        help="Use more regex for x86 matching to reduce diffs between various subtargets",
    )
    parser.add_argument(
        "--function-signature",
        action="store_true",
        help="Keep function signature information around for the check line",
    )
    parser.add_argument(
        "--check-attributes",
        action="store_true",
        help='Check "Function Attributes" for functions',
    )
    parser.add_argument(
        "--check-globals",
        nargs="?",
        const="all",
        default="default",
        choices=["none", "smart", "all"],
        help="Check global entries (global variables, metadata, attribute sets, ...) for functions",
    )
    parser.add_argument("tests", nargs="+")
    args = common.parse_commandline_args(parser)
    infer_dependent_args(args)

    if not find_executable(args.sdc_bin):
        print("Please specify --sdc-bin", file=sys.stderr)
        sys.exit(1)
    return args, parser


def invoke_sdc(sdc_bin, sdc_args, filename):
    """Run sdc. Unlike clang, the module name must match the working directory."""
    proc = subprocess.run(
        [sdc_bin] + sdc_args,
        cwd=os.path.dirname(os.path.abspath(filename)),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        sys.stderr.write("Failed to run %s %s\n" % (sdc_bin, " ".join(sdc_args)))
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        sys.exit(2)
    if b"\x00" in proc.stdout:
        raise RuntimeError("binary output from %s" % filename)
    return proc.stdout.decode("utf-8", "replace")


def get_function_body(
    builder, args, filename, sdc_args, extra_commands, prefixes, raw_tool_output
):
    for extra_command in extra_commands:
        extra_args = shlex.split(extra_command)
        with tempfile.NamedTemporaryFile() as f:
            f.write(raw_tool_output.encode())
            f.flush()
            raw_tool_output = common.invoke_tool(extra_args[0], extra_args[1:], f.name)
    if "--emit-llvm" in sdc_args:
        builder.process_run_line(
            common.OPT_FUNCTION_RE, common.scrub_body, raw_tool_output, prefixes
        )
        builder.processed_prefixes(prefixes)
    else:
        print(
            "The sdc command line should include -S --emit-llvm.",
            file=sys.stderr,
        )
        sys.exit(1)


def exec_run_line(exe):
    popen = subprocess.Popen(
        exe, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True
    )
    stdout, stderr = popen.communicate()
    if popen.returncode != 0:
        sys.stderr.write("Failed to run " + " ".join(exe) + "\n")
        sys.stderr.write(stderr)
        sys.stderr.write(stdout)
        sys.exit(3)


def update_test(ti: common.TestInfo):
    # Build a list of filechecked and non-filechecked RUN lines.
    run_list = []
    line2func_list = collections.defaultdict(list)

    subs = {
        "%s": os.path.basename(os.path.abspath(ti.path)),
        "%t": tempfile.NamedTemporaryFile().name,
        "%S": os.path.dirname(os.path.abspath(ti.path)),
    }

    for l in ti.run_lines:
        commands = [cmd.strip() for cmd in l.split("|")]

        triple_in_cmd = None
        m = common.TRIPLE_ARG_RE.search(commands[0])
        if m:
            triple_in_cmd = m.groups()[0]

        # Parse executable args.
        exec_args = shlex.split(commands[0])
        # Execute non-sdc runline.
        if exec_args[0] not in SUBST:
            # Do lit-like substitutions.
            for s in subs:
                exec_args = [i.replace(s, subs[s]) if s in i else i for i in exec_args]
            run_list.append((None, exec_args, None, None))
            continue
        # This is an sdc runline, apply %sdc substitution, do lit-like substitutions,
        # and append args.sdc_args
        sdc_args = exec_args
        sdc_args[0:1] = SUBST[sdc_args[0]]
        for s in subs:
            sdc_args = [i.replace(s, subs[s]) if s in i else i for i in sdc_args]
        sdc_args += ti.args.sdc_args

        # Extract -check-prefix in FileCheck args
        filecheck_cmd = commands[-1]
        common.verify_filecheck_prefixes(filecheck_cmd)
        if not filecheck_cmd.startswith("FileCheck "):
            # Execute non-filechecked clang runline.
            exe = [ti.args.sdc_bin] + sdc_args
            run_list.append((None, exe, None, None))
            continue

        check_prefixes = common.get_check_prefixes(filecheck_cmd)
        run_list.append((check_prefixes, sdc_args, commands[1:-1], triple_in_cmd))

    # Execute clang, generate LLVM IR, and extract functions.

    # Store only filechecked runlines.
    filecheck_run_list = [i for i in run_list if i[0]]
    ginfo = common.make_ir_generalizer(ti.args.version, ti.args.check_globals == "none")
    builder = common.FunctionTestBuilder(
        run_list=filecheck_run_list,
        flags=ti.args,
        scrubber_args=[],
        path=ti.path,
        ginfo=ginfo,
    )

    global_tbaa_records_for_prefixes = {}
    for prefixes, args, extra_commands, triple_in_cmd in run_list:
        # Execute non-filechecked runline.
        if not prefixes:
            print(
                "NOTE: Executing non-FileChecked RUN line: " + " ".join(args),
                file=sys.stderr,
            )
            exec_run_line(args)
            continue

        sdc_args = args
        common.debug("Extracted sdc cmd: sdc {}".format(sdc_args))
        common.debug("Extracted FileCheck prefixes: {}".format(prefixes))

        # Invoke external tool and extract function bodies.
        raw_tool_output = invoke_sdc(ti.args.sdc_bin, sdc_args, ti.path)
        get_function_body(
            builder,
            ti.args,
            ti.path,
            sdc_args,
            extra_commands,
            prefixes,
            raw_tool_output,
        )

        # Extract TBAA metadata for later usage in check lines.
        tbaa_map = common.get_tbaa_records(ti.args.version, raw_tool_output)
        global_tbaa_records_for_prefixes[tuple(prefixes)] = tbaa_map

        # Same (spell, mangled, search) tuples clang's AST dump produced.
        for k, v in get_line2func_list(
            ti.path, [func for func in builder.func_order().get(prefixes[0], [])]
        ).items():
            line2func_list[k].extend(v)

    func_dict = builder.finish_and_get_func_dict()
    global_vars_seen_dict = {}
    prefix_set = set([prefix for p in filecheck_run_list for prefix in p[0]])
    output_lines = []
    has_checked_pre_function_globals = False

    include_generated_funcs = common.find_arg_in_test(
        ti,
        lambda args: ti.args.include_generated_funcs,
        "--include-generated-funcs",
        True,
    )
    generated_prefixes = []
    if include_generated_funcs:
        # Generate the appropriate checks for each function.  We need to emit
        # these in the order according to the generated output so that CHECK-LABEL
        # works properly.  func_order provides that.

        # It turns out that when clang generates functions (for example, with
        # -fopenmp), it can sometimes cause functions to be re-ordered in the
        # output, even functions that exist in the source file.  Therefore we
        # can't insert check lines before each source function and instead have to
        # put them at the end.  So the first thing to do is dump out the source
        # lines.
        common.dump_input_lines(output_lines, ti, prefix_set, "//")

        # Now generate all the checks.
        def check_generator(my_output_lines, prefixes, func):
            return common.add_ir_checks(
                my_output_lines,
                "//",
                prefixes,
                func_dict,
                func,
                False,
                ti.args.function_signature,
                ginfo,
                global_vars_seen_dict,
                global_tbaa_records_for_prefixes,
                is_filtered=builder.is_filtered(),
            )

        if ti.args.check_globals != "none":
            generated_prefixes.extend(
                common.add_global_checks(
                    builder.global_var_dict(),
                    "//",
                    run_list,
                    output_lines,
                    ginfo,
                    global_vars_seen_dict,
                    global_tbaa_records_for_prefixes,
                    False,
                    True,
                    ti.args.check_globals,
                )
            )
        generated_prefixes.extend(
            common.add_checks_at_end(
                output_lines,
                filecheck_run_list,
                builder.func_order(),
                "//",
                lambda my_output_lines, prefixes, func: check_generator(
                    my_output_lines, prefixes, func
                ),
            )
        )
    else:
        # Normal mode.  Put checks before each source function.
        for line_info in ti.iterlines(output_lines):
            idx = line_info.line_number
            line = line_info.line
            args = line_info.args
            include_line = True
            m = common.CHECK_RE.match(line)
            if m and m.group(1) in prefix_set:
                continue  # Don't append the existing CHECK lines
            # Skip special separator comments added by commmon.add_global_checks.
            if line.strip() == "//" + common.SEPARATOR:
                continue
            if idx in line2func_list:
                added = set()
                for spell, mangled, search in line2func_list[idx]:
                    # One line may contain multiple function declarations.
                    # Skip if the mangled name has been added before.
                    # The line number may come from an included file, we simply require
                    # the search string (normally the function's spelling name, but is
                    # the class's spelling name for class specializations) to appear on
                    # the line to exclude functions from other files.
                    if mangled in added or search not in line:
                        continue
                    if args.functions is None or any(
                        re.search(regex, spell) for regex in args.functions
                    ):
                        last_line = output_lines[-1].strip()
                        while last_line == "//":
                            # Remove the comment line since we will generate a new  comment
                            # line as part of common.add_ir_checks()
                            output_lines.pop()
                            last_line = output_lines[-1].strip()
                        if (
                            ti.args.check_globals != "none"
                            and not has_checked_pre_function_globals
                        ):
                            generated_prefixes.extend(
                                common.add_global_checks(
                                    builder.global_var_dict(),
                                    "//",
                                    run_list,
                                    output_lines,
                                    ginfo,
                                    global_vars_seen_dict,
                                    global_tbaa_records_for_prefixes,
                                    False,
                                    True,
                                    ti.args.check_globals,
                                )
                            )
                            has_checked_pre_function_globals = True
                        if added:
                            output_lines.append("//")
                        added.add(mangled)
                        generated_prefixes.extend(
                            common.add_ir_checks(
                                output_lines,
                                "//",
                                filecheck_run_list,
                                func_dict,
                                mangled,
                                False,
                                args.function_signature,
                                ginfo,
                                global_vars_seen_dict,
                                global_tbaa_records_for_prefixes,
                                is_filtered=builder.is_filtered(),
                            )
                        )
                        if line.rstrip("\n") == "//":
                            include_line = False

            if include_line:
                output_lines.append(line.rstrip("\n"))

    if ti.args.check_globals != "none":
        generated_prefixes.extend(
            common.add_global_checks(
                builder.global_var_dict(),
                "//",
                run_list,
                output_lines,
                ginfo,
                global_vars_seen_dict,
                global_tbaa_records_for_prefixes,
                False,
                False,
                ti.args.check_globals,
            )
        )
    if ti.args.gen_unused_prefix_body:
        output_lines.extend(
            ti.get_checks_for_unused_prefixes(run_list, generated_prefixes)
        )
    common.debug("Writing %d lines to %s..." % (len(output_lines), ti.path))
    with open(ti.path, "wb") as f:
        f.writelines(["{}\n".format(l).encode("utf-8") for l in output_lines])


def main():
    initial_args, parser = config()
    script_name = os.path.basename(__file__)

    returncode = 0
    for ti in common.itertests(
        initial_args.tests,
        parser,
        "tools/" + script_name,
        comment_prefix="//",
        argparse_callback=infer_dependent_args,
    ):
        try:
            update_test(ti)
        except Exception:
            stderr.write(f"Error: Failed to update test {ti.path}\n")
            print_exc()
            returncode = 1

    return returncode


if __name__ == "__main__":
    sys.exit(main())
