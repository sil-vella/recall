import argparse
import os
import sys
from typing import List, Optional

import libcst as cst
from libcst import CSTTransformer, RemoveFromParent, SimpleStatementLine, SimpleStatementSuite


def is_custom_log_callee(func: cst.BaseExpression) -> bool:
    """
    Returns True if the function expression refers to a callee named 'custom_log',
    either directly (Name) or as the last attribute in an Attribute chain.
    """
    # Name('custom_log')
    if isinstance(func, cst.Name):
        return func.value == "custom_log"

    # Attribute(..., attr=Name('custom_log')) possibly chained
    if isinstance(func, cst.Attribute):
        # Unwind to get the final attribute name
        attr = func.attr
        return isinstance(attr, cst.Name) and attr.value == "custom_log"

    return False


class RemoveCustomLogAndFixTransformer(CSTTransformer):
    """
    Transformer that:
    - Removes statements that are solely `custom_log(...)`
    - If a suite (indented block or simple suite) becomes empty, inserts `pass`
    """

    def leave_SimpleStatementLine(
        self, original_node: SimpleStatementLine, updated_node: SimpleStatementLine
    ) -> Optional[cst.BaseStatement]:
        # Filter out small statements that are `custom_log(...)` expression statements
        new_small_stmts: List[cst.BaseSmallStatement] = []
        for small in updated_node.body:
            if isinstance(small, cst.Expr) and isinstance(small.value, cst.Call):
                if is_custom_log_callee(small.value.func):
                    # Drop this log call
                    continue
            new_small_stmts.append(small)

        if len(new_small_stmts) == 0:
            return RemoveFromParent()

        if len(new_small_stmts) != len(updated_node.body):
            return updated_node.with_changes(body=new_small_stmts)

        return updated_node

    def leave_SimpleStatementSuite(
        self, original_node: SimpleStatementSuite, updated_node: SimpleStatementSuite
    ) -> cst.BaseSuite:
        # Same filtering for one-line suites: `if cond: custom_log("x")`
        new_small_stmts: List[cst.BaseSmallStatement] = []
        for small in updated_node.body:
            if isinstance(small, cst.Expr) and isinstance(small.value, cst.Call):
                if is_custom_log_callee(small.value.func):
                    continue
            new_small_stmts.append(small)

        if len(new_small_stmts) == 0:
            # Replace with a simple suite containing `pass`
            return cst.SimpleStatementSuite(body=[cst.Pass()])

        if len(new_small_stmts) != len(updated_node.body):
            return updated_node.with_changes(body=new_small_stmts)

        return updated_node

    def leave_IndentedBlock(
        self, original_node: cst.IndentedBlock, updated_node: cst.IndentedBlock
    ) -> cst.BaseSuite:
        # Determine if the block has any non-empty statements (ignore empty lines)
        real_body: List[cst.BaseStatement] = [
            stmt for stmt in updated_node.body if not isinstance(stmt, cst.EmptyLine)
        ]
        if len(real_body) == 0:
            # Insert `pass`
            return cst.IndentedBlock(body=[cst.SimpleStatementLine(body=[cst.Pass()])])
        return updated_node


def iter_python_files(root: str, exclude_dirs: List[str]) -> List[str]:
    results: List[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune excluded directories in-place for efficiency
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for fname in filenames:
            if fname.endswith(".py"):
                results.append(os.path.join(dirpath, fname))
    return results


def process_file(path: str) -> bool:
    """
    Parse and transform a Python file. Returns True if content changed.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
    except Exception:
        # Fallback with default encoding
        with open(path, "r", errors="ignore") as f:
            src = f.read()

    try:
        module = cst.parse_module(src)
    except Exception as e:
        print(f"[parse-error] {path}: {e}", file=sys.stderr)
        return False

    transformed = module.visit(RemoveCustomLogAndFixTransformer())
    new_code = transformed.code

    if new_code != src:
        return write_back_if_changed(path, new_code)

    return False


def write_back_if_changed(path: str, new_code: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as f:
            old = f.read()
    except Exception:
        with open(path, "r", errors="ignore") as f:
            old = f.read()

    if old == new_code:
        return False

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(new_code)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Remove custom_log(...) calls and add pass to emptied blocks using libcst."
        )
    )
    parser.add_argument(
        "--root",
        default=os.path.abspath(os.path.dirname(__file__)),
        help="Root directory to process (defaults to project root)",
    )
    parser.add_argument(
        "--exclude-dir",
        action="append",
        default=[
            "libs",
            "venv",
            "__pycache__",
            ".git",
            "tools",
            "static",
            "templates",
            "secrets",
        ],
        help="Directory name to exclude (can be passed multiple times)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only report files that would change, do not write",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Verbose output"
    )

    args = parser.parse_args()

    root = os.path.abspath(args.root)
    files = iter_python_files(root, exclude_dirs=args.exclude_dir)

    changed_count = 0
    processed_count = 0

    for path in files:
        processed_count += 1
        try:
            with open(path, "r", encoding="utf-8") as f:
                src = f.read()
        except Exception:
            with open(path, "r", errors="ignore") as f:
                src = f.read()

        try:
            module = cst.parse_module(src)
            transformed = module.visit(RemoveCustomLogAndFixTransformer())
            new_code = transformed.code
        except Exception as e:
            print(f"[transform-error] {path}: {e}", file=sys.stderr)
            continue

        if new_code != src:
            if args.dry_run:
                print(path)
                changed_count += 1
            else:
                if write_back_if_changed(path, new_code):
                    if args.verbose:
                        print(f"[updated] {path}")
                    changed_count += 1

    if args.dry_run:
        print(f"Would update {changed_count} files (scanned {processed_count}).")
    else:
        print(f"Updated {changed_count} files (scanned {processed_count}).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
