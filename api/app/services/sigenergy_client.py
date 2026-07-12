import os

from pymodbus.client import ModbusTcpClient
from pymodbus.exceptions import ModbusIOException

from app.services.home_assistant_client import HomeAssistantUnavailable, get_entity_state
from app.services.sigenergy_registers import SIGENERGY_REGISTERS

HOST = os.getenv("SIGENERGY_HOST", "192.168.0.2")
PORT = int(os.getenv("SIGENERGY_PORT", "502"))
EV_POWER_ENTITY_ID = os.getenv(
    "EV_POWER_ENTITY_ID",
    "sensor.sigen_plant_smart_load_1_power",
).strip()
EV_TOTAL_CONSUMPTION_ENTITY_ID = os.getenv(
    "EV_TOTAL_CONSUMPTION_ENTITY_ID",
    "sensor.sigen_plant_smart_load_1_total_consumption",
).strip()
EV_CHARGING_THRESHOLD_KW = float(os.getenv("EV_CHARGING_THRESHOLD_KW", "0.3"))

PLANT_ID = 247
INVERTER_ID = 1

# EV telemetry/control is parked for now.
# We have not yet confirmed a reliable local EV charger register/API.
EV_INTEGRATED = False


def u16(regs):
    return regs[0]


def s16(regs):
    value = regs[0]
    return value - 65536 if value >= 32768 else value


def u32(regs):
    return (regs[0] << 16) + regs[1]


def s32(regs):
    value = u32(regs)
    return value - 4294967296 if value >= 2147483648 else value


def read_input(client, device_id, address, count, decoder, gain=1):
    result = client.read_input_registers(
        address=address,
        count=count,
        device_id=device_id,
    )

    if result.isError():
        raise RuntimeError(result)

    return decoder(result.registers) / gain


DECODERS = {
    "u16": u16,
    "s16": s16,
    "u32": u32,
    "s32": s32,
}


def read_modbus_registers(client, register_kind, device_id, address, count):
    if register_kind == "holding":
        return client.read_holding_registers(
            address=address,
            count=count,
            device_id=device_id,
        )

    return client.read_input_registers(
        address=address,
        count=count,
        device_id=device_id,
    )


def read_register_spec(client, spec):
    decoder = DECODERS[spec["decoder"]]
    register_kind = spec.get("register_kind", "input")
    raw = read_modbus_registers(
        client=client,
        register_kind=register_kind,
        address=spec["address"],
        count=spec["count"],
        device_id=spec["device_id"],
    )

    if raw.isError():
        raise RuntimeError(raw)

    decoded = decoder(raw.registers) / spec.get("gain", 1)

    return {
        "device_id": spec["device_id"],
        "register_address": spec["address"],
        "register_count": spec["count"],
        "register_type": f"{register_kind}:{spec['decoder']}",
        "raw_registers": raw.registers,
        "decoded_value": decoded,
        "unit": spec.get("unit"),
        "label": spec.get("label"),
    }


def read_sigenergy_registers(registers=None):
    client = ModbusTcpClient(HOST, port=PORT, timeout=2, retries=0)

    if not client.connect():
        raise RuntimeError("Could not connect to Sigenergy")

    try:
        readings = []

        for spec in registers or SIGENERGY_REGISTERS:
            try:
                readings.append(read_register_spec(client, spec))
            except (ModbusIOException, RuntimeError):
                continue

        return readings
    finally:
        client.close()


def looks_interesting_register_value(value):
    if value is None:
        return False

    absolute = abs(value)

    return 0 < absolute <= 30000


def scan_sigenergy_register_range(
    device_id,
    start,
    end,
    max_results=200,
    register_kind="input",
    host=None,
    port=None,
):
    target_host = host or HOST
    target_port = port or PORT
    client = ModbusTcpClient(target_host, port=target_port, timeout=1, retries=0)

    if not client.connect():
        raise RuntimeError(f"Could not connect to Sigenergy at {target_host}:{target_port}")

    try:
        results = []

        for address in range(start, end + 1):
            if len(results) >= max_results:
                break

            try:
                raw = read_modbus_registers(
                    client=client,
                    register_kind=register_kind,
                    address=address,
                    count=1,
                    device_id=device_id,
                )
            except ModbusIOException:
                continue

            if raw.isError():
                continue

            for register_type, decoder in [("u16", u16), ("s16", s16)]:
                decoded = decoder(raw.registers)

                if looks_interesting_register_value(decoded):
                    results.append({
                        "device_id": device_id,
                        "register_address": address,
                        "register_count": 1,
                        "register_type": f"{register_kind}:{register_type}",
                        "raw_registers": raw.registers,
                        "decoded_value": decoded,
                        "unit": None,
                        "label": f"scan_{device_id}_{address}_{register_type}",
                    })

            if len(results) >= max_results:
                break

            try:
                raw_pair = read_modbus_registers(
                    client=client,
                    register_kind=register_kind,
                    address=address,
                    count=2,
                    device_id=device_id,
                )
            except ModbusIOException:
                continue

            if raw_pair.isError():
                continue

            for register_type, decoder, gain in [
                ("u32", u32, 1),
                ("s32", s32, 1),
                ("u32_kw_candidate", u32, 1000),
                ("s32_kw_candidate", s32, 1000),
            ]:
                decoded = decoder(raw_pair.registers) / gain

                if looks_interesting_register_value(decoded):
                    results.append({
                        "device_id": device_id,
                        "register_address": address,
                        "register_count": 2,
                        "register_type": f"{register_kind}:{register_type}",
                        "raw_registers": raw_pair.registers,
                        "decoded_value": decoded,
                        "unit": "kW" if "kw" in register_type else None,
                        "label": f"scan_{device_id}_{address}_{register_type}",
                    })

        return results
    finally:
        client.close()


def read_sigenergy_register_window(
    device_id,
    start,
    end,
    register_kind="input",
    host=None,
    port=None,
):
    target_host = host or HOST
    target_port = port or PORT
    client = ModbusTcpClient(target_host, port=target_port, timeout=1, retries=0)

    if not client.connect():
        raise RuntimeError(f"Could not connect to Sigenergy at {target_host}:{target_port}")

    try:
        rows = []

        for address in range(start, end + 1):
            try:
                raw = read_modbus_registers(
                    client=client,
                    register_kind=register_kind,
                    address=address,
                    count=1,
                    device_id=device_id,
                )
            except ModbusIOException as exc:
                rows.append({
                    "address": address,
                    "error": str(exc),
                })
                continue

            if raw.isError():
                rows.append({
                    "address": address,
                    "error": str(raw),
                })
                continue

            row = {
                "address": address,
                "raw": raw.registers,
                "u16": u16(raw.registers),
                "s16": s16(raw.registers),
            }

            try:
                raw_pair = read_modbus_registers(
                    client=client,
                    register_kind=register_kind,
                    address=address,
                    count=2,
                    device_id=device_id,
                )

                if not raw_pair.isError():
                    row.update({
                        "u32": u32(raw_pair.registers),
                        "s32": s32(raw_pair.registers),
                        "u32_div_10": u32(raw_pair.registers) / 10,
                        "s32_div_10": s32(raw_pair.registers) / 10,
                        "u32_div_100": u32(raw_pair.registers) / 100,
                        "s32_div_100": s32(raw_pair.registers) / 100,
                        "u32_div_1000": u32(raw_pair.registers) / 1000,
                        "s32_div_1000": s32(raw_pair.registers) / 1000,
                    })
            except ModbusIOException:
                pass

            rows.append(row)

        return rows
    finally:
        client.close()


def parse_home_assistant_float(entity):
    state = entity.get("state")

    if state in [None, "", "unknown", "unavailable"]:
        return None

    try:
        return float(state)
    except (TypeError, ValueError):
        return None


def read_ev_smart_port_snapshot():
    if not EV_POWER_ENTITY_ID:
        return {
            "ev_kw": None,
            "ev_charging": None,
            "ev_total_kwh": None,
            "ev_status": "not_configured",
            "ev_source": None,
            "ev_total_source": None,
        }

    try:
        power_entity = get_entity_state(EV_POWER_ENTITY_ID)
        power_kw = parse_home_assistant_float(power_entity)

        total_kwh = None
        if EV_TOTAL_CONSUMPTION_ENTITY_ID:
            total_entity = get_entity_state(EV_TOTAL_CONSUMPTION_ENTITY_ID)
            total_kwh = parse_home_assistant_float(total_entity)

        if power_kw is None:
            return {
                "ev_kw": None,
                "ev_charging": None,
                "ev_total_kwh": total_kwh,
                "ev_status": "entity_unavailable",
                "ev_source": EV_POWER_ENTITY_ID,
                "ev_total_source": EV_TOTAL_CONSUMPTION_ENTITY_ID or None,
            }

        return {
            "ev_kw": round(max(power_kw, 0), 2),
            "ev_charging": power_kw >= EV_CHARGING_THRESHOLD_KW,
            "ev_total_kwh": round(total_kwh, 2) if total_kwh is not None else None,
            "ev_status": "smart_port",
            "ev_source": EV_POWER_ENTITY_ID,
            "ev_total_source": EV_TOTAL_CONSUMPTION_ENTITY_ID or None,
        }
    except HomeAssistantUnavailable as exc:
        return {
            "ev_kw": None,
            "ev_charging": None,
            "ev_total_kwh": None,
            "ev_status": "home_assistant_unavailable",
            "ev_error": str(exc),
            "ev_source": EV_POWER_ENTITY_ID,
            "ev_total_source": EV_TOTAL_CONSUMPTION_ENTITY_ID or None,
        }


def get_energy_snapshot():
    client = ModbusTcpClient(HOST, port=PORT, timeout=2, retries=0)

    if not client.connect():
        raise RuntimeError("Could not connect to Sigenergy")

    try:
        # Plant / EMS level
        ems_work_mode = read_input(client, PLANT_ID, 30003, 1, u16)
        grid_sensor_status = read_input(client, PLANT_ID, 30004, 1, u16)
        on_off_grid_status = read_input(client, PLANT_ID, 30009, 1, u16)
        plant_running_state = read_input(client, PLANT_ID, 30051, 1, u16)

        # Plant-level power values
        grid_kw = read_input(client, PLANT_ID, 30005, 2, s32, 1000)
        plant_active_power_kw = read_input(client, PLANT_ID, 30031, 2, s32, 1000)
        plant_pv_kw = read_input(client, PLANT_ID, 30035, 2, s32, 1000)
        plant_battery_kw = read_input(client, PLANT_ID, 30037, 2, s32, 1000)

        # Grid phase import/export
        grid_a_kw = read_input(client, PLANT_ID, 30052, 2, s32, 1000)
        grid_b_kw = read_input(client, PLANT_ID, 30054, 2, s32, 1000)
        grid_c_kw = read_input(client, PLANT_ID, 30056, 2, s32, 1000)

        # Inverter / device level
        inverter_temp_c = read_input(client, INVERTER_ID, 31003, 1, s16, 10)
        inverter_pv_kw = read_input(client, INVERTER_ID, 31035, 2, s32, 1000)

        # Battery / ESS
        battery_soc = read_input(client, INVERTER_ID, 30601, 1, u16, 10)
        battery_soh = read_input(client, INVERTER_ID, 30602, 1, u16, 10)
        battery_kw = read_input(client, INVERTER_ID, 30599, 2, s32, 1000)

        # Repo definitions:
        # 30595 = available battery charge energy, scale 0.01 kWh
        # 30597 = available battery discharge energy, scale 0.01 kWh
        # 30548 = rated battery capacity, scale 0.01 kWh
        battery_available_charge_kwh = read_input(client, INVERTER_ID, 30595, 2, u32, 100)
        battery_available_discharge_kwh = read_input(client, INVERTER_ID, 30597, 2, u32, 100)
        battery_capacity_kwh = read_input(client, INVERTER_ID, 30548, 2, u32, 100)

        # Use discharge energy as the user-available battery energy figure.
        battery_usable_kwh = battery_available_discharge_kwh

        # House load estimate:
        # Plant PV + grid import/export - battery charge/discharge.
        # Positive battery_kw = charging, negative battery_kw = discharging.
        house_load_kw = max(0, plant_pv_kw + grid_kw - battery_kw)

        grid_supplying_house = grid_kw > 0.2
        grid_exporting = grid_kw < -0.2
        grid_connected = on_off_grid_status == 0

        ev_snapshot = read_ev_smart_port_snapshot()

        return {
            # Solar / inverter
            "solar_kw": round(plant_pv_kw, 2),
            "inverter_pv_kw": round(inverter_pv_kw, 2),
            "inverter_temp_c": round(inverter_temp_c, 1),

            # Battery
            "battery_soc": round(battery_soc, 1),
            "battery_soh": round(battery_soh, 1),
            "battery_kw": round(battery_kw, 2),
            "battery_available_charge_kwh": round(battery_available_charge_kwh, 2),
            "battery_available_discharge_kwh": round(battery_available_discharge_kwh, 2),
            "battery_usable_kwh": round(battery_usable_kwh, 2),
            "battery_capacity_kwh": round(battery_capacity_kwh, 2),

            # Grid / plant
            "grid_kw": round(grid_kw, 2),
            "grid_a_kw": round(grid_a_kw, 2),
            "grid_b_kw": round(grid_b_kw, 2),
            "grid_c_kw": round(grid_c_kw, 2),
            "grid_supplying_house": grid_supplying_house,
            "grid_exporting": grid_exporting,
            "grid_connected": grid_connected,

            "plant_active_power_kw": round(plant_active_power_kw, 2),
            "plant_battery_kw": round(plant_battery_kw, 2),
            "house_load_kw": round(house_load_kw, 2),

            # Status codes
            "ems_work_mode": int(ems_work_mode),
            "grid_sensor_status": int(grid_sensor_status),
            "on_off_grid_status": int(on_off_grid_status),
            "plant_running_state": int(plant_running_state),

            # EV placeholder
            **ev_snapshot,
        }

    finally:
        client.close()
