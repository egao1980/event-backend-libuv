# event-backend-libuv

MIT. **libuv** backend for [`event-protocol`](https://github.com/egao1980/event-protocol) — default / Windows-primary.

| | |
|--|--|
| Protocol | `egao1980/event-protocol` |
| Native | `libuv` (+ `cffi-grovel` at overlay build) |
| Matrix | linux/amd64+arm64, darwin/arm64, **windows/amd64** |

## Load / test

Needs `event-protocol` on the ASDF registry and `libuv` (+ headers for first grovel).

```bash
export HOMEBREW_PREFIX=/opt/homebrew   # macOS local-dev
ros -e '(asdf:load-asd "event-backend-libuv.asd")' \
    -e '(asdf:test-system "event-backend-libuv")' -q
```

Conformance suite is shared (`event-protocol/conformance`); this repo sets the backend maker.

## Overlay

```bash
./scripts/build-libuv.sh          # Unix
./scripts/build-libuv.ps1         # Windows: MSVC + CMake → lib/windows-amd64 + uv.h
./scripts/stage-grovel.sh event-backend-libuv
```

Windows split: **MSVC (`VsDevCmd` + NMake) builds `libuv.dll`**; **MinGW `gcc` is only for
cffi-grovel** against the same installed headers (`EVENT_PROTOCOL_UV_INCLUDE`). No Chocolatey
cmake — use the runner/VS-provided one.

Ship `native-library` + `cffi-grovel-output` via cl-repository (see `:cl-repo` in the `.asd`).
Publish: Actions → **Publish OCI Package** (`workflow_dispatch`, version `0.1.0`).

Clean-container proof (no `gcc` / `libuv-dev`):

```bash
./scripts/smoke-clean-container.sh 0.1.0
```

When `grovel-cache/grovel.cffi.lisp` is present next to the `.asd`, load skips `grovel-file` (no CC).

Tracking: [cl-stack#16](https://github.com/egao1980/cl-stack/issues/16).
