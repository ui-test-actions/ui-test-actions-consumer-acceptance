# Independent UI Test Actions consumer

The v3.0.1 stability workflows use `ui-test-actions/ui-test-actions@0c818c5d72e8c30c59bd1287c330a40392bf8e89`. Start with the desktop or mobile workflow and use your own app's launch and readiness hooks. Quick Tunnel uses locally generated session authentication and requires no repository secrets. The paired P2pKit app network and the private WireGuard UI-control route each have their own setup and cleanup. [Public setup guide](https://github.com/ui-test-actions/ui-test-actions/tree/0c818c5d72e8c30c59bd1287c330a40392bf8e89#add-the-action-to-a-workflow) · [Stability evidence](verification/stability-v3.0.1/) · [v3.0.0 acceptance](verification/release-v3.0.0/)

## Named Tunnel

The Named workflow retains the v3.0.0 live acceptance pin and uses the documented secret names. Configure a dedicated hostname and its scoped connector and Access credentials before dispatch. Workflow concurrency is repository-local. Use distinct dedicated tunnel hostnames when more than one repository can run concurrently. [Named Tunnel setup](https://github.com/ui-test-actions/ui-test-actions/blob/0c818c5d72e8c30c59bd1287c330a40392bf8e89/docs/transports.md#named-tunnel-and-access)
