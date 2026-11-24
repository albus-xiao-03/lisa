<!-- Paired-device sessions (plan R2 §10.8 "Paired-device sessions (X1, X4, X7)"). -->
# Paired-device sessions

A paired case (X1's and X4's nearby cells, X7's timing) involves two devices. Their results must join without a shared clock, and every measurement must stay on one device.

## Starting a session

```sh
swift run lisa-verify pair-session <case> --devices mac,iphone|mac,ipad|iphone,ipad \
    --condition shared-wifi|no-internet|no-access-point [--run <run-id>]
```

It prints:
- the run ID (a new device run unless `--run` names one);
- the **session nonce**, twelve characters in three groups, which you enter on both devices;
- for each device: its **role** (the first device in `--devices` is the `sender`, the second the `receiver`), its correlated case ID `<case>@<role>`, and the scheme, test plan and `xcodebuild` destination to launch.

Each session is appended to the run's `pair-sessions.jsonl`.

## Joining the results

Each device writes one record under `<case>@<role>`. The record carries `pairSession`: the base case, role, devices, condition, the nonce you entered, and the session codes the device showed. `lisa-verify report` joins a case's records by the case and the nonce. A paired case shows `PASS` only when both roles reported under one nonce for each design recorded, and every record passed. Otherwise it shows `waiting (one device's result)`, or the first failing status with its cause.

## Timing

- Each device records its monotonic clock.
- Latency and the 100-operation timing are round trips measured on one device: the sender.
- A four-timestamp exchange over the session (20 exchanges; the sample with the smallest delay) estimates the clock offset. It is used only to report one-way events.
- Wall-clock times are recorded for correlation, never for a measurement.
