# Local intent probe

An exploratory, non-shipping Foundation Models probe. Requires macOS 26+ and an available Apple Intelligence on-device model. It uses synthetic requests only. It does not read documents, change settings or connect to a cloud model.

From the repository root:

```sh
source scripts/environment.sh
swiftc -parse-as-library design/intelligence/probe.swift -o build/intent-probe
build/intent-probe
```

See [the evaluation](../../docs/local-intelligence.md) for results and release criteria. Timings vary by machine, operating system, model availability and system load.
