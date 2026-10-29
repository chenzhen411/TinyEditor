#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
python3 - <<'PY'
import re
source=open('Tests/TinyEditorTests/CoreTests.swift').read().replace('import XCTest','import AppKit').replace('@testable import TinyEditor','')
methods=re.findall(r'func (test\w+)\(',source)
source+='\nlet suite = CoreTests()\n'
for method in methods:
 signature=re.search(r'func '+method+r'\([^)]*\)\s*(throws)?',source)
 if signature.group(1): source+=f'do {{ try suite.{method}() }} catch {{ failures.append("{method}: \\(error)") }}\n'
 else: source+=f'suite.{method}()\n'
source+='\nprint("Assertions: \\(assertionCount), failures: \\(failures.count)")\nlet payload:[String:Any] = ["assertions":assertionCount,"failures":failures,"passed":failures.isEmpty,"tests":'+str(len(methods))+']\nlet json = try! JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys])\ntry! json.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))\nexit(failures.isEmpty ? 0:1)\n'
open('.build/checks/main.swift','w').write(source)
PY
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/tinyeditor-module-cache" swiftc -O -target arm64-apple-macos13.0 -module-cache-path "${TMPDIR:-/tmp}/tinyeditor-module-cache" $(find Sources/TinyEditor -name '*.swift' ! -name main.swift | sort) Tests/Standalone/Assertions.swift .build/checks/main.swift -o .build/checks/CoreChecks
TINYEDITOR_DATA_DIR="$(mktemp -d /tmp/TinyEditor-core.XXXXXX)" .build/checks/CoreChecks "$PWD/docs/core-results.json"
