# SOURCEPOS (cmark-gfm 0.29.0.gfm.13)

Pinned tarball SHA-256: `5abc61798ebd9de5660bc076443c07abad2b8d15dbc11094a3a79644b8ad243a`

Measured on this tag:

- `start_line` / `end_line` are 1-based. `\n`, `\r`, and `\r\n` each count as one break.
- `start_column` / `end_column` are 1-based. The column advances one per UTF-8 byte. Tabs jump to the next multiple of 4: `col = ((col - 1) / 4 + 1) * 4 + 1`.
- Do not normalize newlines before parse. `SourceMap` walks the same `String` fed to `cmark_parser_feed`.
