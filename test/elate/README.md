# meow-ghostel shell command matrix (elate)

Reusable [`elate`](https://github.com/dakra/elate) scenarios that drive a live `ghostel`
+ `meow-ghostel` session and assert that meow editing over the PTY works, across shells.
(`elate` is a CLI for spawning and driving sandboxed, observable Emacs sessions.)
Each op types a command, applies a meow edit, executes the edited line, and asserts its
output — so the shell/REPL itself proves the edit landed.

## Files

- `lib/meow-ghostel-setup.el` — shared startup: puts `meow`/`ghostel`/`meow-ghostel`
  on the load-path (self-locating), defines meow's documented qwerty `meow-setup`,
  enables `meow-global-mode` + `meow-ghostel-mode`, disables
  `ghostel-macos-login-shell`. `meow` resolves from `ELATE_MEOW_DIR`, `../meow`, or
  `$XDG_CACHE_HOME/meow`; `ghostel` from `ELATE_GHOSTEL_DIR`, `../ghostel`, or
  `$XDG_CACHE_HOME/ghostel` — the ghostel checkout must have its native module built.
- `matrix/meow-shells.json` — **one templated scenario driven once per shell** (`bash,
  zsh, fish, nu`). Meow is selection-first, so word ops select backward from the input
  end with `b` (back-word) before `s`/`c`/`r`; `x s`/`x c` are the line kill/change;
  `s` with no selection exercises the C-k fallback; plus a keypad smoke (`SPC` in
  normal state) and insert-state Ctrl passthrough groups. `{{u_expect}}` flips the
  nu-only undo xfail (meow has no paste-before, so there is no `P` group).
  meow-ghostel adds no insert-state passthrough layer, so `C-u` follows
  `ghostel-keymap-exceptions` (Emacs `universal-argument`, not shell kill-line) —
  the passthrough group uses `C-a` + `C-k` instead.
- `matrix/meow-python3.json` — the REPL, kept separate because it has no `echo` and
  PyREPL editing doesn't word-split cleanly (word-heavy ops omitted).
- `matrix/meow-boundary-<shell>-ghostel.json` — the input-region boundary suite
  (autosuggestion, right prompt, syntax-highlight tail, multi-line) on
  bash/zsh/fish/nu: `x a` (select line + append) exercises the autosuggestion clamp
  through the region-end path, `A` (open-below) through the input-end target,
  `x s` must not eat the right prompt.

## Running (elate 0.11.0+)

The shells share co-varying template holes (`shell`/`echo`/`setup`), so drive one
shell per `elate run --keep-going` and read the per-group grid from the JSON:

```sh
S=test/elate/matrix/meow-shells.json
elate run --keep-going --format json --set shell=/opt/homebrew/bin/bash --set echo=echo --set setup= "$S"
elate run --keep-going --format json --set shell=/bin/zsh               --set echo=echo --set setup= "$S"
elate run --keep-going --format json --set shell=/opt/homebrew/bin/fish --set echo=echo \
  --set 'setup=function fish_prompt; echo -n "> "; end; function fish_right_prompt; end' "$S"
elate run --keep-going --format json --set shell=/opt/homebrew/bin/nu   --set echo=e \
  --set 'setup=def e [...rest] { $rest | str join " " }' --set u_expect=fail "$S"

elate run --keep-going --format json test/elate/matrix/meow-python3.json
for s in bash zsh fish nu; do
  elate run --keep-going --format json test/elate/matrix/meow-boundary-$s-ghostel.json; done
```

Each run's JSON carries a `groups[]` array (`name` + `status` = `PASS`/`FAIL`/`XFAIL`/
`XPASS`). The run exits non-zero on any genuine `FAIL` or `XPASS` (`xfail` is
non-gating).

## Scenario gotchas

- `meow-keypad` runs a **blocking `read-key` loop**, which stalls elate's
  emacsclient stepping — the keypad group therefore sends `<escape> SPC <escape>`
  as ONE `keys` chunk so the loop consumes its own exit.
- Repeated `meow-back-word` REPLACES the selection (it does not expand), so
  "kill two words" is two successive `b s` kills.
- The boundary suites' autosuggestion cells are the load-bearing ones: the
  color-based `meow-ghostel--input-end` detection is what stops a rightward
  PTY key from accepting the ghost text (the #493-class bug); it is only
  exercisable live (`color-values` needs a display frame).

## Known xfails

- **`u` (undo) on `nu` and `python3`** — `meow-ghostel-undo` sends `C-_`
  (readline/zle undo); reedline and PyREPL don't bind it.

## Overrides

- `ELATE_GHOSTEL_SHELL` — overrides `ghostel-shell` (setup reads it).
- `ELATE_MEOW_DIR` / `ELATE_GHOSTEL_DIR` — absolute paths to the checkouts
  (the sandbox hides `$HOME`, so the scenarios' `session.env` blocks pin them).
