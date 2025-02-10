import os
import subprocess
import difflib
import sys
import argparse


# ENVIRONMENT SETUP

if '__file__' not in globals() \
        or not __file__.endswith("testsuite/driver/runtests.py"):
    raise Exception("runtests.py meant to be run as script: python3 /path/to/testsuite/driver/runtests.py")

TESTSUITE_DIR = os.path.abspath(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
PROJECT_DIR = os.path.abspath(os.path.dirname(TESTSUITE_DIR))

INTERPRETER_PROJECT_DIR = os.path.join(PROJECT_DIR, "interpreter")

EXE = ''

# EXECUTE TESTS


class TestFailure (Exception):
    def __init__(self, msg):
        self.msg = msg


def collect_test_files(dir_path):
    test_files = {}
    for test_dir in os.listdir(dir_path):
        for test_file in os.listdir(os.path.join(dir_path, test_dir)):
            # skip dist/ and build/ directories
            if test_file in ['dist', 'build']:
                continue

            (name, ext) = os.path.splitext(os.path.basename(test_file))

            if name in test_files:
                files_dict = test_files[name]
            else:
                files_dict = {}
                test_files[name] = files_dict

            if ext == ".hl":
                files_dict["in"] = os.path.join(dir_path, test_dir, test_file)
            elif ext == ".out":
                files_dict["out"] = os.path.join(dir_path, test_dir, test_file)

    return test_files


def compile_file(hl_file):
    eval_proc = subprocess.run([EXE, hl_file],
                               cwd=os.path.dirname(hl_file),
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    if eval_proc.returncode != 0:
        raise TestFailure("Haskelite compilation failed: file='{}' exit-code='{}' output:\n{}".format(hl_file, eval_proc.returncode, eval_proc.stdout.decode("UTF-8")))

    (directory, filename) = os.path.split(hl_file)
    basefilename = os.path.splitext(filename)[0]  # no extension
    return os.path.join(directory, "dist", basefilename)  # the executable is in dist/[basefilename]


def eval_file(hl_bin):
    eval_proc = subprocess.run([hl_bin],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if eval_proc.returncode != 0:
        raise TestFailure("Binary output incorrect: file='{}' exit-code='{}' output:\n{}".format(hl_bin, eval_proc.returncode, eval_proc.stdout.decode("UTF-8")))

    return eval_proc.stdout.decode("utf-8")


class TestResult (object):
    PASSED = "PASSED"
    FAILED = "FAILED"
    EXCLUDED = "EXCLUDED"

    def __init__(self, result, msg=''):
        self.result = result
        self.msg = msg

    def print(self, test_name):
        if sys.stdout.isatty():
            print(self._get_ansi_color_code(), end='')

        print("[{}] {}".format(test_name, self.result))
        if self.msg:
            print(self.msg)

        if sys.stdout.isatty():
            print('\033[0m', end='')  # reset ANSI color

    def _get_ansi_color_code(self):
        if self.result == TestResult.PASSED:
            return '\033[0;32m'  # green
        elif self.result == TestResult.FAILED:
            return '\033[0;31m'  # red
        elif self.result == TestResult.EXCLUDED:
            return '\033[0;33m'  # yellow


def exec_test(file_dict):
    if "in" not in file_dict:
        return TestResult(TestResult.FAILED, "missing input file")
    elif "out" not in file_dict:
        return TestResult(TestResult.FAILED, "missing output file")

    hl_file = file_dict["in"]
    out_file = file_dict["out"]

    with open(hl_file, 'r') as f:
        if f.readline().startswith("-- EXCLUDE"):
            return TestResult(TestResult.EXCLUDED)

    try:
        hl_bin = compile_file(hl_file)
        eval_res = eval_file(hl_bin).splitlines(keepends=True)


        with open(out_file, 'r') as f:
            expected_out = f.readlines()

        diff = list(difflib.unified_diff(expected_out, eval_res, fromfile=hl_bin, tofile=out_file, lineterm='\n'))

        if len(diff) != 0:
            return TestResult(TestResult.FAILED, "Output did not match expected\n{}".format('\n'.join(diff)))

        return TestResult(TestResult.PASSED)
    except TestFailure as tf:
        return TestResult(TestResult.FAILED, tf.msg)


def install():
    install_proc = subprocess.run(["cabal", "install", "--installdir=testsuite/bin"],
                                  cwd=PROJECT_DIR,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    if install_proc.returncode != 0:
        raise TestFailure("Failed to install executable: exit-code='{}' output:\n{}".format(install_proc.returncode, install_proc.stdout.decode("UTF-8")))

    return os.path.abspath(os.path.join(PROJECT_DIR, "testsuite/bin/oxell"))


def parse_args():
    parser = argparse.ArgumentParser(
        prog='run-tests',
        description='Run test suite'
    )

    parser.add_argument(
        '-m', '--match',
        help="Only run tests that match the test name (i.e. 'contains' check on directory name)",
        action='store',
        required=False
    )

    return parser.parse_args()


if __name__ == '__main__':
    args = parse_args()
    subprocess.run(["cabal", "build"], check=True)
    exe = install()

    print("Using executable: {}".format(exe))
    EXE = exe

    for n, fs in collect_test_files(os.path.join(TESTSUITE_DIR, "tests/should-succeed")).items():
        if args.match and not args.match in n:
            TestResult(TestResult.EXCLUDED).print(n)
            continue

        exec_test(fs).print(n)
