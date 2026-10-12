"""QX++ bridge - run QX++ code, read-only.

Locates a QX++ interpreter and runs a .QX+ program, returning its stdout.

IMPORTANT: this module NEVER writes inside the QX++ installation. It only
reads the interpreter and stdlib. All output files are written into the Null
Address project (or a caller-supplied directory).

Two interpreters exist:
  * C++  (qxpp.exe / qxpp-v2.1.4.exe) - fast, but its for-loop scoping is
    broken (a loop accumulator stays 0) and it has no `.size()`.
  * Python (interpreter/qxpp.py) - correct for loops and list methods.

Because the layout rules need loops and list sizes, this bridge prefers the
Python interpreter and falls back to the C++ binary only for simple programs.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

# --- where QX++ lives (read-only) -----------------------------------------
QXPP_SOURCE = Path("C:/Users/Santi/QIX AI/QX++")
QXPP_INSTALLED = Path(os.environ.get("LOCALAPPDATA", "")) / "QX++"

# The Python driver we inject. Runs a .QX+ file and prints its output.
_DRIVER = r"""
import sys, io, contextlib
sys.path.insert(0, r"{interp}")
sys.path.insert(0, r"{stdlib}")
from lexer import Lexer
from parser import Parser
from runtime import Runtime

src = open(r"{program}", "r", encoding="utf-8").read()
lx = Lexer(src, r"{name}")
toks = lx.tokenize()
pr = Parser(toks, r"{name}")
prog = pr.parse()
rt = Runtime(r"{name}")
rt.execute(prog)
"""


class QXPPError(RuntimeError):
    """Raised when QX++ cannot be located or a program fails."""


@dataclass
class QXPPResult:
    ok: bool
    stdout: str
    stderr: str
    interpreter: str

    def values(self) -> dict[str, str]:
        """Parse `key=value` lines out of stdout."""
        out: dict[str, str] = {}
        for line in self.stdout.splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("//"):
                k, _, v = line.partition("=")
                out[k.strip()] = v.strip()
        return out

    def series(self, prefix: str) -> list[str]:
        """Collect `prefix=value` lines in order, as a list."""
        got = []
        for line in self.stdout.splitlines():
            line = line.strip()
            if line.startswith(prefix + "="):
                got.append(line.split("=", 1)[1].strip())
        return got


def find_python_interpreter() -> Path | None:
    """Locate the QX++ Python interpreter directory, read-only."""
    for base in (QXPP_SOURCE / "interpreter", QXPP_INSTALLED / "interpreter"):
        if (base / "runtime.py").is_file() and (base / "lexer.py").is_file():
            return base
    return None


def find_stdlib() -> Path | None:
    for base in (QXPP_SOURCE / "stdlib", QXPP_INSTALLED / "stdlib"):
        if (base / "neuron_math.py").is_file() or (base / "phase2").is_dir():
            return base
    return None


def find_cpp_binary() -> Path | None:
    """Locate a C++ qxpp binary, read-only."""
    for base in (QXPP_INSTALLED / "bin", QXPP_SOURCE / "cpp" / "build"):
        for name in ("qxpp.exe", "qxpp-v2.1.4.exe"):
            p = base / name
            if p.is_file():
                return p
    return None


def available() -> dict[str, str | None]:
    """Report what is installed, without changing anything."""
    py = find_python_interpreter()
    std = find_stdlib()
    cpp = find_cpp_binary()
    return {
        "python_interpreter": str(py) if py else None,
        "stdlib": str(std) if std else None,
        "cpp_binary": str(cpp) if cpp else None,
    }


def _python_candidates() -> Iterable[str]:
    for exe in ("python3.11", "python3", "python", sys.executable):
        if exe:
            yield exe


def run_source(source: str, name: str = "asset_ai", timeout: int = 120) -> QXPPResult:
    """Run QX++ source text and return its output. Writes only to a temp file."""
    interp = find_python_interpreter()
    stdlib = find_stdlib()
    if interp is None:
        raise QXPPError(
            "QX++ Python interpreter not found. Looked in "
            f"{QXPP_SOURCE / 'interpreter'} and {QXPP_INSTALLED / 'interpreter'}."
        )

    # The program goes in the OS temp dir - never inside the QX++ tree.
    tmp = Path(tempfile.mkdtemp(prefix="qxpp_ai_"))
    program = tmp / f"{name}.QX+"
    program.write_text(source, encoding="utf-8")

    driver = _DRIVER.format(
        interp=str(interp),
        stdlib=str(stdlib) if stdlib else str(interp),
        program=str(program),
        name=name,
    )
    driver_path = tmp / "_driver.py"
    driver_path.write_text(driver, encoding="utf-8")

    last_err = ""
    for exe in _python_candidates():
        try:
            proc = subprocess.run(
                [exe, "-u", str(driver_path)],
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(interp),          # read-only: interpreter's own dir
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
            last_err = f"{exe}: {exc}"
            continue
        out = proc.stdout or ""
        err = proc.stderr or ""
        if proc.returncode == 0 or out.strip():
            return QXPPResult(True, out, err, f"python:{exe}")
        last_err = err.strip() or out.strip()

    return QXPPResult(False, "", last_err, "python:none")


def run_file(path: str | Path, timeout: int = 120) -> QXPPResult:
    """Run a .QX+ file that already exists on disk."""
    p = Path(path)
    if not p.is_file():
        raise QXPPError(f"no such QX++ file: {p}")
    return run_source(p.read_text(encoding="utf-8"), p.stem, timeout)


if __name__ == "__main__":
    import json

    print(json.dumps(available(), indent=2))
