from pymodbus.client import ModbusTcpClient

HOST = "192.168.0.2"
PORT = 502

PLANT_ID = 247
INVERTER_ID = 1

def u16(regs):
    return regs[0]

def u32(regs):
    return (regs[0] << 16) + regs[1]

def s32(regs):
    value = u32(regs)
    return value - 4294967296 if value >= 2147483648 else value

def read_input(client, device_id, address, count, decoder, gain=1):
    result = client.read_input_registers(
        address=address,
        count=count,
        device_id=device_id
    )

    if result.isError():
        raise RuntimeError(result)

    return decoder(result.registers) / gain

def get_energy_snapshot():
    client = ModbusTcpClient(HOST, port=PORT, timeout=2, retries=0)

    if not client.connect():
        raise RuntimeError("Could not connect to Sigenergy")

    pv_kw = read_input(client, INVERTER_ID, 31035, 2, s32, 1000)
    battery_soc = read_input(client, INVERTER_ID, 30601, 1, u16, 10)
    battery_kw = read_input(client, INVERTER_ID, 30599, 2, s32, 1000)

    grid_a_w = read_input(client, PLANT_ID, 30052, 2, s32)
    grid_b_w = read_input(client, PLANT_ID, 30054, 2, s32)
    grid_c_w = read_input(client, PLANT_ID, 30056, 2, s32)

    grid_total_kw = (grid_a_w + grid_b_w + grid_c_w) / 1000

    house_load_kw = pv_kw + grid_total_kw + battery_kw

    BASE_HOUSE_LOAD_KW = 0.35
    ev_kw = max(0, house_load_kw - BASE_HOUSE_LOAD_KW)
    ev_charging = ev_kw > 0.5

    client.close()

    return {
        "solar_kw": round(pv_kw, 2),
        "battery_soc": round(battery_soc, 1),
        "battery_kw": round(battery_kw, 2),
        "grid_kw": round(grid_total_kw, 2),
        "house_load_kw": round(house_load_kw, 2),
        "ev_kw": round(ev_kw, 2),
        "ev_charging": ev_charging,
    }