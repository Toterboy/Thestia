import re
from pathlib import Path

p = Path(r"C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\test\validators_test.dart")
src = p.read_text(encoding="utf-8")

# 1. Imports + Helper
src = src.replace(
    "import 'package:wisp/utils/validators.dart';\nimport 'package:flutter_test/flutter_test.dart';",
    "import 'package:flutter/material.dart';\n"
    "import 'package:wisp/utils/validators.dart';\n"
    "import 'package:flutter_test/flutter_test.dart';\n"
    "\n"
    "/// Liefert einen BuildContext (Default-Locale Deutsch, wie ohne Scope).\n"
    "Future<BuildContext> _ctx(WidgetTester tester) async {\n"
    "  late BuildContext ctx;\n"
    "  await tester.pumpWidget(MaterialApp(\n"
    "    home: Builder(builder: (c) {\n"
    "      ctx = c;\n"
    "      return const SizedBox();\n"
    "    }),\n"
    "  ));\n"
    "  return ctx;\n"
    "}",
)

# 2. test('name', () {  ->  testWidgets('name', (tester) async {\n  final context...
def repl_test(m):
    indent, name = m.group(1), m.group(2)
    return (
        f"{indent}testWidgets('{name}', (tester) async {{\n"
        f"{indent}  final context = await _ctx(tester);"
    )

src = re.sub(
    r"(?m)^( +)test\('((?:[^'\\]|\\.)*)', \(\) \{$",
    repl_test,
    src,
)
# Doppelte Quotes-Variante
src = re.sub(
    r'(?m)^( +)test\("((?:[^"\\]|\\.)*)", \(\) \{$',
    lambda m: (
        f'{m.group(1)}testWidgets("{m.group(2)}", (tester) async {{\n'
        f'{m.group(1)}  final context = await _ctx(tester);'
    ),
    src,
)

# 3. Validators-Aufrufe mit context als erstem Argument versehen.
for fn in [
    "required",
    "name",
    "age",
    "email",
    "password",
    "registrationPassword",
    "passwordStrength",
    "birthDate",
    "bio",
]:
    src = re.sub(
        r"Validators\." + fn + r"\((?!context, )",
        f"Validators.{fn}(context, ",
        src,
    )

p.write_text(src, encoding="utf-8")
print("done")
