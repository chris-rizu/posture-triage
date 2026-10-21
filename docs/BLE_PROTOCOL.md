# BLE protocol

Device name `PostureTriage`. One primary service, three characteristics.

| Characteristic | UUID | Properties |
|---|---|---|
| Service | `7a1e0001-5c3b-4f2a-9d7e-2b8c4a6f1d00` | |
| Measurement | `7a1e0002-5c3b-4f2a-9d7e-2b8c4a6f1d00` | notify (5 Hz) |
| Result | `7a1e0003-5c3b-4f2a-9d7e-2b8c4a6f1d00` | read, notify |
| Command | `7a1e0004-5c3b-4f2a-9d7e-2b8c4a6f1d00` | write, write without response |

The firmware asks for an ATT MTU of 517 and the app for 512. Messages are designed to stay under 500 bytes.

## Measurement (binary, little-endian, 49 bytes, version 1)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | version = 1 |
| 1 | u8 | state: 0 idle, 1 calibrating, 2 stand, 3 bend, 4 monitor, 5 error, 6 low battery |
| 2 | u16 | sequence number |
| 4 | i16 × 5 | θs per pod, centidegrees |
| 14 | i16 × 5 | θf per pod, centidegrees |
| 24 | i16 × 5 | θr per pod, centidegrees |
| 34 | i16 × 6 | live K, L, N, F, S, R, centidegrees |
| 46 | u16 | battery, millivolts (0 = not measured) |
| 48 | u8 | flags: bit0 moving, bit1 calibrated, bit2 low battery, bit3 simulated, bit4 sensor fault |

The value −32768 means "not defined" (NaN).
`app/test/protocol_test.dart` decodes a packet produced by the firmware code, so both sides stay in step.

## Commands (UTF-8 text)

| Command | Effect | Reply on Result |
|---|---|---|
| `PING` | | `{"t":"pong"}` |
| `STATUS` | | `status` |
| `CAL` | 3 s calibration | `cal`, then `status` |
| `STAND` | 30 s standing trial | `progress` each second, then `trial` |
| `BEND` | 5 s forward-bend trial | `progress`, then `trial` |
| `RESULT` | combine the last three trials of each kind | `result` |
| `CLEAR` | forget all trials | `status` |
| `MONITOR` | posture monitoring until `STOP` | `alert` on each vibration |
| `STOP` | stop a trial or monitoring | `trial` (aborted) and/or `status` |
| `THR {json}` | store thresholds in flash | `thr` or `err bad_thresholds` |
| `GETTHR` | | `thr` |
| `SIM ...` | simulated build only (see CLAUDE.md) | `status` or `err sim_unavailable` |

## Result messages (JSON, field "t")

```json
{"t":"status","state":"idle","cal":true,"bat":3.95,"sim":false,"fw":"1.0.0","stand":3,"bend":1,"provisional":true,"sensors":[1,1,1,1,1]}
{"t":"cal","ok":false,"why":"moved","pod":3}
{"t":"progress","kind":"stand","sec":12,"of":30}
{"t":"trial","kind":"stand","ok":true,"why":"","n":2,"ind":{"K":38.05,"L":-22.07,"N":27.89,"F":0.26,"S":0.46},"pods":{"s":[...5],"f":[...5]}}
{"t":"trial","kind":"bend","ok":false,"why":"not_bent","n":0,"ind":{"R":null},"pods":{"s":[...5],"r":[...5]}}
{"t":"result","complete":true,"agree":true,"risk":"monitor","stand":3,"bend":3,"retake":[],"provisional":true,
 "ind":{"K":[38.04,0.01,"healthy"],"L":[...],"N":[...],"F":[...],"S":[...],"R":[3.4,0.2,"monitor"]}}
{"t":"alert","ind":"K","v":55.1}
{"t":"thr","provisional":false,"K":[38.20,11.40,15.20],"L":[...],"N":[...],"F":[...],"S":[...],"R":[0.00,3.00,5.00]}
{"t":"err","msg":"not_calibrated"}
```

`result.ind` values are `[mean of the three trials, max − min across them, level]`. `risk` is null
until three valid trials of each kind agree within 3°; `retake` lists which kind needs one more trial.
Trial failure reasons: `moved`, `not_bent`, `not_upright`, `sensor`, `aborted`. Error codes:
`not_calibrated`, `busy`, `low_battery`, `bad_thresholds`, `unknown_command`, `sim_unavailable`.
