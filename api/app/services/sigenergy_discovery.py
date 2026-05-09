from pymodbus.client import ModbusTcpClient
from pymodbus.exceptions import ModbusIOException

HOST = "192.168.0.2"
PORT = 502

DEVICE_IDS = [247, 1]

RANGES = [
    (30000, 30100, "Plant / grid block"),
    (30580, 30690, "Battery block"),
    (31000, 31200, "PV / inverter block"),
    (32000, 32150, "Possible charger/device block"),
]

client = ModbusTcpClient(HOST, port=PORT, timeout=1, retries=0)


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


def safe_read(device_id, address, count):
    try:
        result = client.read_input_registers(
            address=address,
            count=count,
            device_id=device_id,
        )

        if result.isError():
            return None

        return result.registers

    except ModbusIOException:
        return None
    except Exception:
        return None


def looks_interesting(value):
    if value is None:
        return False

    abs_value = abs(value)

    # Keep zeros out unless you want huge noisy output
    if abs_value == 0:
        return False

    # Broadly plausible values for energy system telemetry
    if 0 < abs_value <= 30000:
        return True

    return False


def print_candidate(device_id, address, label, raw):
    one_u16 = u16(raw[:1])
    one_s16 = s16(raw[:1])

    print(
        f"Device {device_id} | {label} | Address {address} | "
        f"raw={raw} | "
        f"U16={one_u16} /10={one_u16/10:.2f} /100={one_u16/100:.2f} /1000={one_u16/1000:.3f} | "
        f"S16={one_s16} /10={one_s16/10:.2f} /100={one_s16/100:.2f} /1000={one_s16/1000:.3f}"
    )


def print_candidate_32(device_id, address, label, raw):
    value_u32 = u32(raw)
    value_s32 = s32(raw)

    interesting_values = [
        value_u32,
        value_s32,
        value_u32 / 10,
        value_u32 / 100,
        value_u32 / 1000,
        value_s32 / 10,
        value_s32 / 100,
        value_s32 / 1000,
    ]

    if not any(looks_interesting(v) for v in interesting_values):
        return

    print(
        f"Device {device_id} | {label} | Address {address} | "
        f"raw={raw} | "
        f"U32={value_u32} /10={value_u32/10:.2f} /100={value_u32/100:.2f} /1000={value_u32/1000:.3f} | "
        f"S32={value_s32} /10={value_s32/10:.2f} /100={value_s32/100:.2f} /1000={value_s32/1000:.3f}"
    )


if not client.connect():
    print("Could not connect")
    raise SystemExit

print("\n--- SIGENERGY DISCOVERY ---")
print(f"Host: {HOST}:{PORT}")
print(f"Device IDs: {DEVICE_IDS}")

for device_id in DEVICE_IDS:
    print(f"\n==============================")
    print(f"DEVICE ID {device_id}")
    print(f"==============================")

    for start, end, label in RANGES:
        print(f"\n--- {label}: {start}-{end} ---")

        print("\nSingle-register candidates")
        for address in range(start, end):
            raw = safe_read(device_id, address, 1)
            if raw is None:
                continue

            value_u16 = u16(raw)
            value_s16 = s16(raw)

            if looks_interesting(value_u16) or looks_interesting(value_s16):
                print_candidate(device_id, address, label, raw)

        print("\nTwo-register candidates")
        for address in range(start, end - 1):
            raw = safe_read(device_id, address, 2)
            if raw is None:
                continue

            print_candidate_32(device_id, address, label, raw)

client.close()