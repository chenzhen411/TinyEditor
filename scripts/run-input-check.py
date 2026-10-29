#!/usr/bin/env python3
"""Run the optional, explicitly authorized TinyEditor input driver without rebuilding it."""
import pathlib
import subprocess
import sys
import tempfile

base = pathlib.Path(__file__).resolve().parents[1]
driver = base / 'artifacts/TestSupport/TinyEditorInputCheck.app'
if not driver.is_dir():
    raise SystemExit('Build the optional driver before granting its temporary system permission.')
with tempfile.NamedTemporaryFile(prefix='TinyEditor-input-', suffix='.log', dir='/tmp') as log:
    # open -W does not propagate the GUI application's exit code. The driver reports all
    # refusals on stderr, so retain/check it instead of mistaking open's zero status for success.
    subprocess.run(['open', '-g', '-n', '-W', '--stderr', log.name, '-a', str(driver),
                    '--args', *sys.argv[1:]], check=True, timeout=15)
    error = pathlib.Path(log.name).read_text()
    if error:
        raise SystemExit(error)
