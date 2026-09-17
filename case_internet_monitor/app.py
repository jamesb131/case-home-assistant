import asyncio
import json
import os
import sqlite3
import subprocess
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

from aiohttp import ClientSession, ClientTimeout, web

DB_PATH = "/data/internet_monitor.sqlite3"
try:
    with open("/data/options.json", encoding="utf-8") as options_file:
        ADDON_OPTIONS = json.load(options_file)
except (OSError, json.JSONDecodeError):
    ADDON_OPTIONS = {}

INTERVAL = float(os.getenv("INTERVAL_SECONDS", ADDON_OPTIONS.get("interval_seconds", 5)))
try:
    TARGETS = json.loads(os.getenv("TARGETS_JSON", ADDON_OPTIONS.get("targets_json", "[]")))
except json.JSONDecodeError:
    TARGETS = []


def db():
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with db() as connection:
        connection.executescript("""
        CREATE TABLE IF NOT EXISTS measurements (
            id INTEGER PRIMARY KEY,
            timestamp TEXT NOT NULL,
            target TEXT NOT NULL,
            host TEXT NOT NULL,
            test_type TEXT NOT NULL,
            success INTEGER NOT NULL,
            latency_ms REAL,
            dns_ms REAL,
            connect_ms REAL,
            ttfb_ms REAL,
            total_ms REAL,
            http_code INTEGER,
            error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_measurements_timestamp ON measurements(timestamp);
        CREATE TABLE IF NOT EXISTS trace_runs (
            id INTEGER PRIMARY KEY,
            timestamp TEXT NOT NULL,
            destination TEXT NOT NULL,
            raw_output TEXT
        );
        """)


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def insert_measurement(row):
    with db() as connection:
        connection.execute("""INSERT INTO measurements
            (timestamp,target,host,test_type,success,latency_ms,dns_ms,connect_ms,ttfb_ms,total_ms,http_code,error)
            VALUES (:timestamp,:target,:host,:test_type,:success,:latency_ms,:dns_ms,:connect_ms,:ttfb_ms,:total_ms,:http_code,:error)""", row)


async def ping(host):
    started = time.perf_counter()
    process = await asyncio.create_subprocess_exec("ping", "-c", "1", "-W", "2", host, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = await process.communicate()
    return process.returncode == 0, (time.perf_counter() - started) * 1000, (stderr or stdout).decode(errors="replace")[-300:]


async def tcp_connect(host, port=443):
    started = time.perf_counter()
    reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=5)
    writer.close()
    await writer.wait_closed()
    return True, (time.perf_counter() - started) * 1000, None


async def probe(session, target):
    host = target.get("host", "")
    name, test_type = target.get("name", host), target.get("test_type", "ping")
    row = {"timestamp": timestamp(), "target": name, "host": host, "test_type": test_type, "success": 0, "latency_ms": None, "dns_ms": None, "connect_ms": None, "ttfb_ms": None, "total_ms": None, "http_code": None, "error": None}
    try:
        if test_type == "ping":
            row["success"], row["latency_ms"], row["error"] = await ping(host)
        elif test_type == "tcp":
            row["success"], row["connect_ms"], row["error"] = await tcp_connect(host)
        else:
            url = host if host.startswith("http") else f"https://{host}"
            started = time.perf_counter()
            async with session.get(url, allow_redirects=True) as response:
                await response.read(4096)
                row["http_code"] = response.status
                row["total_ms"] = (time.perf_counter() - started) * 1000
                row["success"] = int(200 <= response.status < 500)
    except Exception as exc:
        row["error"] = str(exc)[:300]
    insert_measurement(row)


async def monitor():
    timeout = ClientTimeout(total=5)
    async with ClientSession(timeout=timeout) as session:
        while True:
            started = time.perf_counter()
            await asyncio.gather(*(probe(session, target) for target in TARGETS))
            await asyncio.sleep(max(0, INTERVAL - (time.perf_counter() - started)))


async def health(request):
    return web.json_response({"ok": True, "interval_seconds": INTERVAL, "targets": TARGETS})


async def measurements(request):
    limit = min(int(request.query.get("limit", "500")), 5000)
    with db() as connection:
        rows = [dict(row) for row in connection.execute("SELECT * FROM measurements ORDER BY id DESC LIMIT ?", (limit,))]
    return web.json_response({"measurements": rows})


async def main():
    init_db()
    app = web.Application()
    app.router.add_get("/health", health)
    app.router.add_get("/api/measurements", measurements)
    app.router.add_get("/", health)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "0.0.0.0", 8090).start()
    await monitor()


asyncio.run(main())
