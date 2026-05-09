import { useEffect, useState } from "react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
  Legend,
} from "recharts";

const API_BASE = "http://localhost:8000";

function formatKw(value) {
  if (value === null || value === undefined) return "--";
  return `${Number(value).toFixed(2)} kW`;
}

function App() {
  const [data, setData] = useState(null);
  const [recentEnergy, setRecentEnergy] = useState([]);
  const [error, setError] = useState(null);

  async function loadData() {
    try {
      const res = await fetch(`${API_BASE}/decisions/summary`);
      if (!res.ok) throw new Error(`API returned ${res.status}`);

      const json = await res.json();
      setData(json);
      setError(null);
    } catch (err) {
      setError(err.message);
    }
  }

  async function loadRecentEnergy() {
    try {
      const res = await fetch(`${API_BASE}/energy/recent`);
      if (!res.ok) throw new Error(`Recent energy API returned ${res.status}`);

      const json = await res.json();

      setRecentEnergy(
        json.map((row) => ({
          ...row,
          timeLabel: new Date(row.time).toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          }),
        }))
      );
    } catch (err) {
      console.error(err);
    }
  }

  useEffect(() => {
    loadData();
    loadRecentEnergy();

    const interval = setInterval(() => {
      loadData();
      loadRecentEnergy();
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  if (error) {
    return (
      <div style={{ padding: 40, fontFamily: "sans-serif" }}>
        <h1>CASE</h1>
        <h2>API Error</h2>
        <pre>{error}</pre>
      </div>
    );
  }

  if (!data) return <div style={{ padding: 40 }}>Loading...</div>;

  const state = data.state;
  const messages = data.messages || [];
  const warnings = messages.filter((m) => m.level === "warning");
  const info = messages.filter((m) => m.level === "info");

  const energyCards = [
    ["☀️ Solar", formatKw(state.solar_kw)],
    [
      "🔋 Battery",
      `${state.battery_usable_kwh.toFixed(1)} usable / ${state.battery_capacity_kwh.toFixed(1)} kWh`,
    ],
    [
      "⚡ Grid",
      `${Math.abs(state.grid_kw).toFixed(2)} kW ${
        state.grid_kw > 0 ? "supplying house" : "exporting"
      }`,
    ],
    ["🏠 House", formatKw(Math.max(0, state.house_load_kw))],
    ["🚗 EV", "Not integrated yet"],
    ["🔌 Battery Flow", formatKw(state.battery_kw)],
  ];

  const renderDecisionCard = (m, i) => (
    <div
      key={`${m.text}-${i}`}
      style={{
        padding: "14px 18px",
        marginBottom: "12px",
        borderRadius: "12px",
        background:
          m.level === "warning"
            ? "rgba(255,165,0,0.2)"
            : "rgba(0,200,0,0.15)",
        border:
          m.level === "warning"
            ? "1px solid rgba(255,165,0,0.5)"
            : "1px solid rgba(0,200,0,0.4)",
        fontWeight: "600",
        fontSize: "18px",
      }}
    >
      {m.level === "warning" ? "⚠" : "✓"} {m.text}
    </div>
  );

  return (
    <div style={{ padding: 40, fontFamily: "sans-serif" }}>
      <h1>CASE</h1>

      <h2>Decisions</h2>

      {messages.length === 0 ? (
        <div>All good. No actions needed.</div>
      ) : (
        <>
          {warnings.map(renderDecisionCard)}
          {info.map(renderDecisionCard)}
        </>
      )}

      <h2>Energy</h2>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gap: "16px",
          maxWidth: "900px",
          margin: "0 auto",
        }}
      >
        {energyCards.map(([label, value]) => (
          <div
            key={label}
            style={{
              padding: "18px",
              borderRadius: "16px",
              background: "#f6f7f9",
              border: "1px solid #e3e5e8",
              textAlign: "left",
            }}
          >
            <div style={{ fontSize: "14px", color: "#666", marginBottom: "8px" }}>
              {label}
            </div>
            <div style={{ fontSize: "26px", fontWeight: "700" }}>{value}</div>
          </div>
        ))}
      </div>

      <h2 style={{ marginTop: "32px" }}>Last 24 hours</h2>

      <div
        style={{
          height: "320px",
          padding: "20px",
          borderRadius: "16px",
          background: "#f6f7f9",
          border: "1px solid #e3e5e8",
        }}
      >
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={recentEnergy}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="timeLabel" />
            <YAxis />
            <Tooltip />
            <Legend />

            <Line type="monotone" dataKey="solar_kw" name="Solar kW" dot={false} strokeWidth={2} />
            <Line type="monotone" dataKey="house_load_kw" name="House kW" dot={false} strokeWidth={2} />
            <Line type="monotone" dataKey="grid_kw" name="Grid kW" dot={false} strokeWidth={2} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

export default App;