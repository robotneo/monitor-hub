# Contributing

Create a focused branch and add a failing test before implementation. Preserve
component/stack contracts, keep credentials out of Git, and avoid mutable image
tags. Required local checks:

```bash
make lint
make validate
make test
make smoke
```

If Docker is unavailable, `make smoke` reports an explicit skip; CI smoke must
still pass before a stack is promoted. Update operator docs and the changelog for
behavioral changes. Never mark an unexecuted platform or deployment mode tested.
