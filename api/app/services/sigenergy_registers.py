SIGENERGY_REGISTERS = [
    {"label": "grid_power_a_w", "device_id": 247, "address": 30052, "count": 2, "decoder": "s32", "gain": 1, "unit": "W"},
    {"label": "grid_power_b_w", "device_id": 247, "address": 30054, "count": 2, "decoder": "s32", "gain": 1, "unit": "W"},
    {"label": "grid_power_c_w", "device_id": 247, "address": 30056, "count": 2, "decoder": "s32", "gain": 1, "unit": "W"},

    {"label": "battery_soc_pct", "device_id": 1, "address": 30601, "count": 1, "decoder": "u16", "gain": 10, "unit": "%"},
    {"label": "battery_power_kw", "device_id": 1, "address": 30599, "count": 2, "decoder": "s32", "gain": 1000, "unit": "kW"},
    {"label": "battery_energy_kwh_candidate", "device_id": 1, "address": 30595, "count": 2, "decoder": "u32", "gain": 1000, "unit": "kWh"},
    {"label": "battery_capacity_pack_1_kwh_candidate", "device_id": 1, "address": 30591, "count": 2, "decoder": "u32", "gain": 1000, "unit": "kWh"},
    {"label": "battery_capacity_pack_2_kwh_candidate", "device_id": 1, "address": 30593, "count": 2, "decoder": "u32", "gain": 1000, "unit": "kWh"},

    {"label": "pv_power_kw", "device_id": 1, "address": 31035, "count": 2, "decoder": "s32", "gain": 1000, "unit": "kW"},
    {"label": "inverter_temp_c_candidate", "device_id": 1, "address": 31003, "count": 1, "decoder": "u16", "gain": 10, "unit": "°C"},

    {"label": "pv_string_1_voltage_v_candidate", "device_id": 1, "address": 31005, "count": 2, "decoder": "u32", "gain": 100, "unit": "V"},
    {"label": "pv_string_2_voltage_v_candidate", "device_id": 1, "address": 31007, "count": 2, "decoder": "u32", "gain": 100, "unit": "V"},
    {"label": "pv_string_3_voltage_v_candidate", "device_id": 1, "address": 31009, "count": 2, "decoder": "u32", "gain": 100, "unit": "V"},

    {"label": "pv_string_1_current_a_candidate", "device_id": 1, "address": 31017, "count": 2, "decoder": "u32", "gain": 100, "unit": "A"},
    {"label": "pv_string_2_current_a_candidate", "device_id": 1, "address": 31019, "count": 2, "decoder": "u32", "gain": 100, "unit": "A"},
    {"label": "pv_string_3_current_a_candidate", "device_id": 1, "address": 31021, "count": 2, "decoder": "u32", "gain": 100, "unit": "A"},

    {"label": "plant_state", "device_id": 247, "address": 30004, "count": 1, "decoder": "u16", "gain": 1, "unit": "state"},
]