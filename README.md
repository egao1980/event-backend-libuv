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

## IO callbacks

`register-io` / `update-io` callbacks are called as `(status &optional code)`, the
`event-protocol` contract:

- `(funcall callback :ok)`: the fd is ready (`uv_poll_cb` status 0).
- `(funcall callback :error code)`: the poll failed. `code` is libuv's negative
  `UV_E*` status. On Unix libuv reports `POLLERR` (a peer reset, for example) as
  `UV_EBADF` and has already stopped the poll: treat it as a connection failure,
  cancel the handle and close the fd.

An error signalled from a callback is caught and turned into a warning so the loop
keeps running. A callback that takes only one argument therefore loses the poll
error, and its owner never completes
([http-backend-async#62](https://github.com/egao1980/http-backend-async/issues/62)).

`submit` with no `:executor` uses a per-loop [`cl-stack-executors`](https://github.com/egao1980/cl-stack-executors) thread pool (not `uv_queue_work`). Pass a function of one thunk to override. `close-event-loop` does not wait for a thunk that is still running (0.2.4): the pool stops, the thunk finishes on its own, and its callback is dropped because the loop is closed. Queued thunks that had not started never run.

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
