# EV Smart Port Discovery

CASE does not yet know which local Sigenergy register represents the AC charger.

The Sigenergy cloud/web app shows the charger as an AC charger, not generic EV:

- Station serial: `82025112800221`
- AC charger serial: `120A63420073`
- Live cloud fields observed: `chargingPower`, `chargingOutputCurrent`, `chargingVoltage`, `internalTemperature`, `lastSetCurrent`, `maxCurrent`

CASE should still prefer local data. The Core add-on records known Sigenergy raw registers during the regular energy poll. It also exposes a manual scan endpoint for local Modbus input and holding registers through the Sigenergy gateway.

## Test Loop

1. Make sure the EV charger is idle.
2. Run a scan:

   ```bash
   curl -X POST "https://case.home.arpa/api/energy/sigenergy/scan?device_id=247&start=32000&end=32150&register_kind=input"
   ```

3. Turn on the charger or start a charging session.
4. Run the scan again.
5. Compare recent register movement:

   ```bash
   curl "https://case.home.arpa/api/energy/sigenergy/register-changes?minutes=10&limit=80"
   ```

The likely EV/smart-port candidates are registers whose decoded values jump when the charger starts and drop when it stops.

If the smart port is not in `32000-32150`, repeat the scan with another range. Keep ranges small so the inverter is not hit with a broad scan.

## Holding Register Probe

The AC charger may expose its telemetry in holding registers rather than input registers. Probe through the gateway, not the charger Wi-Fi IP:

```bash
curl -X POST "https://case.home.arpa/api/energy/sigenergy/scan?device_id=247&start=32000&end=32150&register_kind=holding"
```

Try likely unit IDs one at a time with a tiny range first:

```bash
curl -X POST "https://case.home.arpa/api/energy/sigenergy/scan?device_id=2&start=30004&end=30004&register_kind=holding"
```

Only expand a unit ID/range after it responds.

## Local AC Charger Clue

With the charger on and CASE Core `0.1.19`, local Modbus through the working Sigenergy endpoint found a small responding charger-like block:

- Unit/device ID: `2`
- Register kind: `input` and `holding` both respond similarly
- Range: `32000-32500`
- Responding values:
  - `32000 = 5`
  - `32009 = 2300` probably voltage scaled as `230.0 V`
  - `32014/32015 = 65535` sentinel/invalid

CASE Core `0.1.20` adds a raw register-window endpoint because filtered scans hide zeros and sentinel values:

```bash
curl "https://case.home.arpa/api/energy/sigenergy/register-window?device_id=2&start=32000&end=32025&register_kind=input"
curl "https://case.home.arpa/api/energy/sigenergy/register-window?device_id=2&start=32000&end=32025&register_kind=holding"
```

## Add-on Settings

The gateway endpoint is configurable in CASE Core:

- `sigenergy_host`: default `192.168.0.2`
- `sigenergy_port`: default `502`
