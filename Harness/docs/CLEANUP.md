<!-- What a run leaves and how to remove it (plan R2 §10.8 "Owner resources, cleanup and revocation"). -->
# Cleanup

`lisa-verify cleanup <run-id>` lists what the run created under `~/LisaVerify/runs/<run-id>/` and removes that directory after you type the run ID (or with `--yes`). It refuses any path that isn't one of the store's run directories. It never touches another run, your configuration or anything outside the store.

| Session | What it leaves | Who removes it |
|---|---|---|
| Fixture runs | The run directory only. The controlled servers ran in memory on `127.0.0.1` and kept nothing | `lisa-verify cleanup` |
| X1 | The run directory. Lisa Proof on each device, with its Keychain items, its Secure Enclave TLS keys and certificates, and its exported files | You: `lisa-verify cleanup`, then delete Lisa Proof from each device. Deleting the app removes its Keychain items and keys on iPhone and iPad; on the Mac, also delete the "Lisa proof-only TLS certificate" items in Keychain Access |
| M3 onward | The verification Core's container and volume, named `lisa-verify-<run-id>` | `lisa-verify cleanup`, after the stopped-target check (arrives with M3) |
| M7 and M8 | Provider-side items named `LISA-VERIFY <run-id> <case>`: test messages, test calendars and events | You, in the provider's own UI (this page will list each one by case when those cases arrive) |

Lisa's integrations are read-only, so the harness never deletes anything on a provider. Revoking a grant is a separate, explicitly selected step under the isolation checks of plan §10.8.
