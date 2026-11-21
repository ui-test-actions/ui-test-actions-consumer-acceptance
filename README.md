# Independent UI Test Actions consumer

This repository uses the public Action at `672f07488d17d39375d8895398d72e4fb94b4437` for Quick Tunnel, private networking, loopback, and fallback. The desktop workflow comes from the public example with consumer launch and readiness hooks. Other workflows exercise checksum-verified upstream editors and the paired native P2pKit samples. The app LAN and the UI-control WireGuard overlay each have their own setup and cleanup. [Public setup guide](https://github.com/ui-test-actions/ui-test-actions#add-the-action-to-a-workflow) · [Consumer evidence](https://github.com/ui-test-actions/ui-test-actions/tree/main/verification/consumer-acceptance)

## Named Tunnel

The Named workflow uses `aa993a101396b7cfa1aab0891ad37a46a94153af` and the documented secret names. Configure a dedicated hostname and its scoped connector and Access credentials before dispatch. Workflow concurrency is repository-local. Use distinct dedicated tunnel hostnames when more than one repository can run concurrently. [Named Tunnel setup](https://github.com/ui-test-actions/ui-test-actions/blob/main/docs/transports.md#named-tunnel-and-access)
