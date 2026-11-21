# Independent UI Test Actions consumer

This repository uses the public action at `672f07488d17d39375d8895398d72e4fb94b4437`. The desktop workflow comes from the public desktop example with consumer build, launch and readiness hooks for a synthetic fixture. The mobile IP link and WireGuard are separate test infrastructure. Client helpers are checked out at the published pin. The source of the action is maintained by its publisher.

## Named Tunnel

The repository-scoped preflight uses the same credential names and published pin as the public documentation. Configure a dedicated hostname and its scoped connector and Access credentials in this repository before dispatching an actual Named session. Workflow concurrency is repository-local. Use distinct dedicated tunnel hostnames when more than one repository can run concurrently.
