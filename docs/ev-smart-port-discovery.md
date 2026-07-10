# EV Smart Port Discovery

CASE does not yet know which Sigenergy register represents the smart port that feeds the EV charger.

The Core add-on now records known Sigenergy raw registers during the regular energy poll. It also exposes a manual scan endpoint for the suspected smart-port/device range.

## Test Loop

1. Make sure the EV charger is idle.
2. Run a scan:

   ```bash
   curl -X POST "https://case.home.arpa/api/energy/sigenergy/scan?device_id=247&start=32000&end=32150"
   ```

3. Turn on the charger or start a charging session.
4. Run the scan again.
5. Compare recent register movement:

   ```bash
   curl "https://case.home.arpa/api/energy/sigenergy/register-changes?minutes=10&limit=80"
   ```

The likely EV/smart-port candidates are registers whose decoded values jump when the charger starts and drop when it stops.

If the smart port is not in `32000-32150`, repeat the scan with another range. Keep ranges small so the inverter is not hit with a broad scan.
