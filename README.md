# Independent UI Test Actions consumer

The unified acceptance workflows use `ui-test-actions/ui-test-actions@a56957b05ce72ed15c0c35daad572a2add0d173e` (`v3.0.0`). Start with the desktop or mobile workflow and use your own app's launch and readiness hooks. Quick Tunnel uses the locally generated session authentication described in the public guide and requires no repository secrets. Other workflows exercise upstream editors and coordinated native P2pKit samples. App LAN forwarding and the UI-control WireGuard overlay each have their own setup and cleanup. [Public setup guide](https://github.com/ui-test-actions/ui-test-actions/tree/a56957b05ce72ed15c0c35daad572a2add0d173e#add-the-action-to-a-workflow) · [Unified acceptance evidence](verification/release-v3.0.0/)

## Named Tunnel

The Named workflow uses the same release and the documented secret names. Configure a dedicated hostname and its scoped connector and Access credentials before dispatch. Workflow concurrency is repository-local. Use distinct dedicated tunnel hostnames when more than one repository can run concurrently. [Named Tunnel setup](https://github.com/ui-test-actions/ui-test-actions/blob/a56957b05ce72ed15c0c35daad572a2add0d173e/docs/transports.md#named-tunnel-and-access)
