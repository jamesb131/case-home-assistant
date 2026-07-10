CREATE INDEX IF NOT EXISTS idx_sigenergy_raw_registers_lookup
    ON sigenergy_raw_registers (
        device_id,
        register_address,
        register_type,
        captured_at
    );
