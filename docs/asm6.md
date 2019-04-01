ASM6
====

Pently is being ported to the ASM6 assembler.


Coding guidelines
-----------------
The ASM6 version of Pently is automatically translated from the ca65
version.  This means the code needs to avoid ca65 features for which
ASM6 lacks a counterpart.

- Do not use `::` to peek into a scope.  All scopes in ASM6 are
  anonymous; the name just applies to the scope's first address.
  If jumping to the end of a subroutine from outside, refactor it as
  two subroutines, one of which falls through into the other.
  Only references to the global scope are translated correctly, such
  as `.if ::PENTLY_USE_VIBRATO`.
- Do not rely on macros being variadic.  A macro in ASM6 takes a
  fixed argument count.
- Use `.ifblank` and `.ifnblank`, not `.if blank(...)` and
  `.if !blank()`.  The translator for variadic macros assumes all
  arguments as nonblank, and a separate keyword is easier for the
  translator to spot.
- When `*` means the current program counter, it must appear at the
  start or end of the operand or next to a parenthesis.  ASM6 uses
  `$` instead, and a dumb search for leading or trailing `*`, `(*`,
  or `*)` is easier than a full expression parser.  Consider `(*)`
  in more complex expressions.
- All include guards must use a label ending in `_INC`, and other
  labels used in `.ifdef` must not end in `_INC`.  This way,
  the translator process can strip them in order to avoid a spurious
  `Illegal instruction` on first use of a `macro` defined within an
  `ifndef` block.
- Prefer `.byte` and `.word` over `.byt` and `.addr` in dynamically
  generated code, such as `pentlyas.py` output.
- Minimize forward references.  ASM6's `=` command behaves as ca65
  `.set`, and sometimes it misrecognizes `(dd,X)` mode instructions
  (giving `Incomplete expression` errors) if `dd` is a forward
  reference.  If a `=` statement appears before the first `.segment`
  in a file, and it references a label within zero page or BSS, the
  translator moves the statement below zero page and BSS sections.
- `.pushseg` and `.popseg` are not implemented because their
  interaction with `.scope`/`.proc` is difficult to model.
