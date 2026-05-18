import { useEffect, useState } from "react";

const API_BASE = "http://localhost:8000";

const PERSON_THEMES = {
  James: {
    primary: "#dc2626",
    soft: "#fee2e2",
    border: "#fecaca",
    text: "#991b1b",
    emoji: "👨",
  },
  Chris: {
    primary: "#a855f7",
    soft: "#f3e8ff",
    border: "#d8b4fe",
    text: "#7e22ce",
    emoji: "👩",
  },
  Leo: {
    primary: "#2563eb",
    soft: "#dbeafe",
    border: "#93c5fd",
    text: "#1d4ed8",
    emoji: "🐢",
  },
  Benny: {
    primary: "#16a34a",
    soft: "#dcfce7",
    border: "#86efac",
    text: "#15803d",
    emoji: "🌿",
  },
  Event: {
    primary: "#f59e0b",
    soft: "#fef3c7",
    border: "#fde68a",
    text: "#92400e",
    emoji: "🗓",
  },
  Unassigned: {
    primary: "#64748b",
    soft: "#f8fafc",
    border: "#e2e8f0",
    text: "#475569",
    emoji: "○",
  },
};


function getPersonTheme(name) {
  return PERSON_THEMES[name] || PERSON_THEMES.Unassigned;
}

function TaskMetaBadges({ task }) {
  return (
    <div style={{ display: "flex", gap: "6px", flexWrap: "wrap", marginTop: "6px" }}>
      {task.source === "recurring" && (
        <span className="taskBadge">↻ Recurring</span>
      )}

      {task.expires_at && (
        <span className="taskBadge">Expires {new Date(task.expires_at).toLocaleDateString([], { weekday: "short" })}</span>
      )}
    </div>
  );
}

function createBlankTask() {
  return {
    id: null,
    title: "",
    description: "",
    assigned_to: "",
    due_date: "",
    priority: "normal",
    status: "pending",
  };
}


function formatKw(value) {
  if (value === null || value === undefined) return "--";
  return Number(value).toFixed(2);
}

function formatTime(value) {
  if (!value) return "--";
  return new Date(value).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function greeting() {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

function weatherIcon(day) {
  if ((day.rain_probability || 0) >= 40) return "🌧️";
  if ((day.rain_probability || 0) >= 15) return "🌦️";
  return "☀️";
}

function weatherAccent(day) {
  if ((day.rain_probability || 0) >= 40) return "#60a5fa";
  if ((day.rain_probability || 0) >= 15) return "#38bdf8";
  return "#fbbf24";
}

function qualityColor(quality) {
  if (quality === "excellent") return "#16a34a";
  if (quality === "strong") return "#22c55e";
  if (quality === "moderate") return "#f59e0b";
  if (quality === "low") return "#dc2626";
  return "#6b7280";
}

function App() {
  const [activePage, setActivePage] = useState("Home");

  const [data, setData] = useState(null);
  const [recentEnergy, setRecentEnergy] = useState([]);
  const [weather, setWeather] = useState(null);
  const [error, setError] = useState(null);
  const [todaySummary, setTodaySummary] = useState(null);
  const [calendarEvents, setCalendarEvents] = useState([]);

  const [tasks, setTasks] = useState([]);
  const [newTaskTitle, setNewTaskTitle] = useState("");

  const [lists, setLists] = useState([]);
  const [newListItemText, setNewListItemText] = useState({});
  const [newListName, setNewListName] = useState("");

  const [plannerView, setPlannerView] = useState("month");

  const [selectedTask, setSelectedTask] = useState(null);
  const [taskModalOpen, setTaskModalOpen] = useState(false);

  const [assistantOpen, setAssistantOpen] = useState(false);
  const [assistantInput, setAssistantInput] = useState("");
  const [assistantMessages, setAssistantMessages] = useState([
    {
      role: "assistant",
      text: "Hi — I'm CASE. Ask me about solar, battery usage, appliances or energy timing.",
    },
  ]);
  const [assistantLoading, setAssistantLoading] = useState(false);
  const [isListening, setIsListening] = useState(false);

  async function loadTasks() {
    try {
      const res = await fetch(`${API_BASE}/tasks`);
  
      if (!res.ok) {
        throw new Error(`Tasks API returned ${res.status}`);
      }
  
      const json = await res.json();
  
      setTasks(json.tasks || []);
    } catch (err) {
      console.error(err);
    }
  }

  async function createTask() {
    if (!newTaskTitle.trim()) return;
  
    try {
      const res = await fetch(`${API_BASE}/tasks`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          title: newTaskTitle,
        }),
      });
  
      if (!res.ok) {
        throw new Error("Failed to create task");
      }
  
      setNewTaskTitle("");
  
      await loadTasks();
    } catch (err) {
      console.error(err);
    }
  }

  async function completeTask(taskId) {
    try {
      const res = await fetch(`${API_BASE}/tasks/${taskId}/complete`, {
        method: "POST",
      });
  
      if (!res.ok) {
        throw new Error("Failed to complete task");
      }
  
      await loadTasks();
    } catch (err) {
      console.error(err);
    }
  }

  async function saveTask(task) {
    const isNew = !task.id;

    const url = isNew
      ? `${API_BASE}/tasks`
      : `${API_BASE}/tasks/${task.id}`;

    const method = isNew ? "POST" : "PUT";

    const payload = {
      title: task.title,
      description: task.description || null,
      assigned_to: task.assigned_to || null,
      due_date: task.due_date || null,
      priority: task.priority || "normal",
      status: task.status || "pending",
    };

    const res = await fetch(url, {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!res.ok) throw new Error("Failed to save task");

    await loadTasks();
    setTaskModalOpen(false);
    setSelectedTask(null);
  }

  async function loadLists() {
    try {
      const res = await fetch(`${API_BASE}/lists`);
      if (!res.ok) throw new Error(`Lists API returned ${res.status}`);

      const json = await res.json();
      setLists(json.lists || []);
    } catch (err) {
      console.error(err);
    }
  }

  async function addListItem(listId) {
    const text = newListItemText[listId];

    if (!text || !text.trim()) return;

    try {
      const res = await fetch(`${API_BASE}/lists/${listId}/items`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          text: text.trim(),
        }),
      });

      if (!res.ok) throw new Error("Failed to add list item");

      setNewListItemText((prev) => ({
        ...prev,
        [listId]: "",
      }));

      await loadLists();
    } catch (err) {
      console.error(err);
    }
  }

  async function completeListItem(itemId) {
    try {
      const res = await fetch(`${API_BASE}/lists/items/${itemId}/complete`, {
        method: "POST",
      });

      if (!res.ok) throw new Error("Failed to complete list item");

      await loadLists();
    } catch (err) {
      console.error(err);
    }
  }

  async function createList() {
    if (!newListName.trim()) return;

    try {
      const res = await fetch(`${API_BASE}/lists`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: newListName.trim(),
        }),
      });

      if (!res.ok) throw new Error("Failed to create list");

      setNewListName("");
      await loadLists();
    } catch (err) {
      console.error(err);
    }
  }

  async function loadCalendarEvents() {
    try {
      const res = await fetch(`${API_BASE}/calendar/upcoming`);
      if (!res.ok) throw new Error(`Calendar API returned ${res.status}`);

      const json = await res.json();
      setCalendarEvents(json.events || []);
    } catch (err) {
      console.error(err);
    }
  }

  async function sendAssistantMessage(messageOverride = null) {
    const userMessage = messageOverride || assistantInput;

    if (!userMessage.trim()) return;

    setAssistantMessages((prev) => [
      ...prev,
      { role: "user", text: userMessage },
    ]);

    setAssistantInput("");
    setAssistantLoading(true);

    try {
      const res = await fetch(`${API_BASE}/case/ask`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: userMessage,
        }),
      });

      const json = await res.json();

      speakCase(json.reply);

        if (
          json.intent === "list_command" ||
          json.intent === "task_command"
        ) {
          await loadTasks();
          await loadLists();
        }
        
        setAssistantMessages((prev) => [
          ...prev,
          {
            role: "assistant",
            text: json.reply,
          },
        ]);

    } catch (err) {
      setAssistantMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: "Something went wrong talking to the assistant.",
        },
      ]);
    }

    setAssistantLoading(false);
  }

  function speakCase(text) {
    if (!window.speechSynthesis || !text) return;
  
    window.speechSynthesis.cancel();
  
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "en-AU";
    utterance.rate = 0.95;
    utterance.pitch = 0.85;
  
    window.speechSynthesis.speak(utterance);
  }

  function startVoiceRecognition() {
    const SpeechRecognition =
      window.SpeechRecognition ||
      window.webkitSpeechRecognition;

    if (!SpeechRecognition) {
      alert("Speech recognition is not supported in this browser.");
      return;
    }

    const recognition = new SpeechRecognition();

    recognition.lang = "en-AU";
    recognition.interimResults = false;
    recognition.continuous = false;

    recognition.onstart = () => {
      setIsListening(true);
    };

    recognition.onend = () => {
      setIsListening(false);
    };

    recognition.onerror = (event) => {
      console.error(event);
      setIsListening(false);
    };

    recognition.onresult = async (event) => {
      const transcript = event.results[0][0].transcript;

      setAssistantInput(transcript);

      await sendAssistantMessage(transcript);
    };

    recognition.start();
  }


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

  async function loadTodaySummary() {
    try {
      const res = await fetch(`${API_BASE}/energy/today-summary`);
      if (!res.ok) throw new Error(`Today summary API returned ${res.status}`);
      const json = await res.json();
      setTodaySummary(json);
    } catch (err) {
      console.error(err);
    }
  }

  async function loadWeather() {
    try {
      const res = await fetch(`${API_BASE}/weather/summary`);
      if (!res.ok) throw new Error(`Weather API returned ${res.status}`);
      const json = await res.json();
      setWeather(json);
    } catch (err) {
      console.error(err);
    }
  }

  useEffect(() => {
    loadData();
    loadRecentEnergy();
    loadWeather();
    loadTodaySummary();
    loadCalendarEvents();
    loadTasks();
    loadLists();

    const interval = // Energy
    setInterval(() => {
      loadData();
      loadRecentEnergy();
    }, 5000);
    
    // Weather
    setInterval(() => {
      loadWeather();
    }, 300000);
    
    // Calendar
    setInterval(() => {
      loadCalendarEvents();
    }, 900000);

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
  const topMessages = messages.slice(0, 2);

  const gridValue = state.grid_kw;
  const gridIsExporting = gridValue < 0;

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f4f6f8",
        fontFamily: "Inter, system-ui, sans-serif",
        color: "#111827",
      }}
    >
      <div style={{ display: "flex" }}>
        <aside
          style={{
            width: "120px",
            minHeight: "100vh",
            background: "#0f172a",
            color: "white",
            padding: "28px 14px",
            boxSizing: "border-box",
          }}
        >
          <div style={{ fontWeight: "900", fontSize: "22px", marginBottom: "34px" }}>
            CASE
          </div>

          {[
            ["⌂", "Home"],
            ["🗓", "Planner"],
            ["🧒", "Kids"],
            ["📝", "Lists"],
            ["⚡", "Energy"],
            ["☁", "Weather"],
            ["🛡", "Security"],
          ].map(([icon, item]) => (
            <div
              onClick={() => setActivePage(item)}
              style={{
                cursor: "pointer",
                display: "flex",
                gap: "10px",
                alignItems: "center",
                fontSize: "14px",
                fontWeight: activePage === item ? 800 : 500,
                opacity: activePage === item ? 1 : 0.68,
                marginBottom: "22px",
                padding: activePage === item ? "12px 10px" : "8px 10px",
                borderRadius: "10px",
                background:
                  activePage === item
                    ? "rgba(255,255,255,0.12)"
                    : "transparent",
              }}
            >
              <span>{icon}</span>
              <span>{item}</span>
            </div>
          ))}
        </aside>

        <main style={{ flex: 1, padding: "24px 30px", maxWidth: "1900px" }}>
        {activePage === "Home" && (
          <>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 380px",
              gap: "20px",
              alignItems: "start",
            }}
          >
            <div>
              <section style={{ marginBottom: "18px" }}>
                <h1 style={{ margin: 0, fontSize: "32px", lineHeight: 1.1 }}>
                  {greeting()}
                </h1>
                <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
                  {new Date().toLocaleDateString([], {
                    weekday: "long",
                    day: "numeric",
                    month: "long",
                  })}
                </div>
              </section>

              <section
                style={{
                  display: "grid",
                  gridTemplateColumns: "1.7fr 0.9fr",
                  gap: "18px",
                  marginBottom: "18px",
                }}
              >
                {weather && (
                  <div className="card">
                    <div style={{ display: "grid", gridTemplateColumns: "1fr 1.2fr", gap: "20px" }}>
                      <div>
                        <div className="muted">Perth forecast</div>
                        <div style={{ display: "flex", alignItems: "center", gap: "14px" }}>
                          <div style={{ fontSize: "48px" }}>☀️</div>
                          <div>
                            <div style={{ fontSize: "40px", fontWeight: 900, lineHeight: 1 }}>
                              {Math.round(weather.current.temperature_2m)}°
                            </div>
                            <div className="muted">
                              Feels like {Math.round(weather.current.apparent_temperature)}° · Cloud{" "}
                              {weather.current.cloud_cover}%
                            </div>
                          </div>
                        </div>
                      </div>

                      <div
                        style={{
                          display: "grid",
                          gridTemplateColumns: "repeat(3, 1fr)",
                          alignItems: "center",
                          borderLeft: "1px solid #e5e7eb",
                          paddingLeft: "18px",
                        }}
                      >
                        <InfoMini icon="↗" label="Sunrise" value={formatTime(weather.sunrise)} />
                        <InfoMini icon="↘" label="Sunset" value={formatTime(weather.sunset)} />
                        <InfoMini
                          icon="💨"
                          label="Wind"
                          value={`${Math.round(weather.current.wind_speed_10m)} km/h`}
                        />
                      </div>
                    </div>

                    <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0 12px" }} />

                    <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: "0" }}>
                      {weather.daily.slice(0, 5).map((day, i) => (
                        <div
                          key={day.date}
                          style={{
                            padding: "7px 12px",
                            borderLeft: i === 0 ? "none" : "1px solid #e5e7eb",
                            textAlign: "center",
                          }}
                        >
                          <div style={{ fontWeight: 800, marginBottom: "6px" }}>
                            {new Date(day.date).toLocaleDateString([], { weekday: "short" })}
                          </div>
                          <div style={{ fontSize: "26px", marginBottom: "2px" }}>{weatherIcon(day)}</div>
                          <div style={{ fontWeight: 900, fontSize: "20px" }}>
                            {Math.round(day.temp_max)}°
                          </div>
                          <div style={{ color: "#2563eb", fontWeight: 700 }}>
                            {Math.round(day.temp_min)}°
                          </div>

                          <TinyTempLine points={day.temp_profile || []} color={weatherAccent(day)} />

                          <div className="tiny">
                            💧 {day.rain_probability}% · 💨 {Math.round(weather.current.wind_speed_10m)} km/h
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                <div className="card">
                  <div className="muted" style={{ marginBottom: "16px" }}>
                    Recommendations
                  </div>

                  {topMessages.length === 0 ? (
                    <div style={{ fontSize: "20px", fontWeight: "800" }}>
                      All good. No actions needed.
                    </div>
                  ) : (
                    topMessages.map((m, i) => (
                      <div
                        key={i}
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: "12px",
                          padding: "14px",
                          borderRadius: "16px",
                          background:
                            m.level === "warning"
                              ? "rgba(251,191,36,0.16)"
                              : "rgba(34,197,94,0.12)",
                          marginBottom: "12px",
                        }}
                      >
                        <div
                          style={{
                            width: "30px",
                            height: "30px",
                            borderRadius: "50%",
                            display: "grid",
                            placeItems: "center",
                            background: m.level === "warning" ? "#f59e0b" : "#22c55e",
                            color: "white",
                            fontWeight: 900,
                          }}
                        >
                          {m.level === "warning" ? "!" : "✓"}
                        </div>
                        <div style={{ fontWeight: 800, lineHeight: 1.25 }}>{m.text}</div>
                      </div>
                    ))
                  )}
                </div>
              </section>

              <section
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(6, minmax(0, 1fr))",
                  gap: "14px",
                  marginBottom: "18px",
                }}
              >
                <EnergyCard icon="☀️" label="Production" value={formatKw(state.solar_kw)} unit="kW" />
                <EnergyCard icon="🏠" label="Consumption" value={formatKw(state.house_load_kw)} unit="kW" />
                <EnergyCard
                  icon="⚡"
                  label="Grid"
                  value={`${gridIsExporting ? "+" : "-"}${Math.abs(gridValue).toFixed(2)}`}
                  unit="kW"
                  color={gridIsExporting ? "#16a34a" : "#dc2626"}
                />
                <EnergyCard
                  icon="🔌"
                  label="Battery flow"
                  value={`${state.battery_kw >= 0 ? "+" : "-"}${Math.abs(state.battery_kw).toFixed(2)}`}
                  unit="kW"
                  color={state.battery_kw >= 0 ? "#16a34a" : "#dc2626"}
                />
                <EnergyCard
                  icon="🔋"
                  label="Battery"
                  value={state.battery_usable_kwh.toFixed(1)}
                  unit="kWh"
                  inlineSubtext={`${Math.round(state.battery_soc)}%`}
                  color={state.battery_usable_kwh <= 0.2 ? "#dc2626" : "#16a34a"}
                />
                <EnergyCard
                  icon="🔻"
                  label="Grid today"
                  value={(todaySummary?.grid_import_kwh ?? 0).toFixed(2)}
                  unit="kWh"
                />
              </section>

              <section
                style={{
                  display: "grid",
                  gridTemplateColumns: "300px 1fr",
                  gap: "18px",
                  marginBottom: "18px",
                }}
              >
                {weather && (
                  <div className="card compactSolar">
                    <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                      <div>
                        <div className="muted">Solar window</div>
                        <h2 style={{ margin: "6px 0 0", fontSize: "20px", lineHeight: 1.2 }}>
                          {formatTime(weather.sunrise)} → {formatTime(weather.sunset)}
                        </h2>
                      </div>
                    </div>

                    <div style={{ marginTop: "18px" }}>
                      <div className="muted" style={{ marginBottom: "8px" }}>
                        Today
                      </div>

                      <div style={{ display: "grid", gap: "8px" }}>
                        {weather.solar_bands.map((band) => (
                          <div key={band.name} className="solarRow">
                            <span style={{ textTransform: "capitalize" }}>{band.name}</span>
                            <strong style={{ color: qualityColor(band.quality), textTransform: "capitalize" }}>
                              {band.quality}
                            </strong>
                          </div>
                        ))}
                      </div>
                    </div>

                    <div style={{ marginTop: "16px" }}>
                      <div className="muted" style={{ marginBottom: "8px" }}>
                        Coming days
                      </div>

                      <div style={{ display: "grid", gap: "8px" }}>
                        {(weather.daily_solar_outlook || []).slice(1, 4).map((day) => (
                          <div key={day.date} className="solarRow">
                            <span>
                              {new Date(day.date).toLocaleDateString([], { weekday: "short" })}
                            </span>
                            <strong style={{ color: qualityColor(day.quality), textTransform: "capitalize" }}>
                              {day.quality}
                            </strong>
                          </div>
                        ))}
                      </div>
                    </div>

                    <button className="button" style={{ marginTop: "18px", width: "100%" }}>
                      Energy details →
                    </button>
                  </div>
                )}

                <div className="card">
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "4px" }}>
                    <div>
                      <div className="muted">Energy trend</div>
                      <h2 style={{ margin: "2px 0 0", fontSize: "24px" }}>Today</h2>
                    </div>
                    <div className="muted">15-minute view</div>
                  </div>

                  <div style={{ height: "430px" }}>
                    <EnergyDayChart data={recentEnergy} />
                  </div>
                </div>
              </section>
            </div>

            <aside
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "18px",
                position: "sticky",
                top: "20px",
              }}
            >
              <button
                onClick={() => setAssistantOpen(!assistantOpen)}
                style={{
                  border: "none",
                  borderRadius: "22px",
                  background: "#111827",
                  color: "white",
                  padding: "18px 22px",
                  fontWeight: 900,
                  fontSize: "16px",
                  cursor: "pointer",
                  boxShadow: "0 14px 40px rgba(15, 23, 42, 0.16)",
                  textAlign: "left",
                }}
              >
                🎙 Ask CASE
                <div style={{ fontSize: "12px", opacity: 0.72, marginTop: "4px" }}>
                  Energy, tasks, events and household planning
                </div>
              </button>

              <section className="card">
              <div style={{ marginBottom: "18px" }}>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    marginBottom: "12px",
                  }}
                >
                  <div className="muted">Tasks</div>
                  
                  <button
                    onClick={startVoiceRecognition}
                    style={{
                      width: "42px",
                      height: "42px",
                      borderRadius: "999px",
                      border: "none",
                      cursor: "pointer",
                      background: isListening
                        ? "#ef4444"
                        : "#e2e8f0",
                      color: isListening
                        ? "white"
                        : "#0f172a",
                      fontSize: "18px",
                    }}
                  >
                    🎤
                  </button>

                  <button
                    onClick={() => {
                      setSelectedTask(createBlankTask());
                      setTaskModalOpen(true);
                    }}
                    style={{
                      border: "none",
                      background: "#111827",
                      color: "white",
                      borderRadius: "999px",
                      width: "28px",
                      height: "28px",
                      cursor: "pointer",
                      fontWeight: 900,
                    }}
                  >
                    +
                  </button>
                </div>

                <input
                  value={newTaskTitle}
                  onChange={(e) => setNewTaskTitle(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      createTask();
                    }
                  }}
                  placeholder="Quick add task..."
                  style={{
                    width: "100%",
                    boxSizing: "border-box",
                    border: "1px solid #d1d5db",
                    borderRadius: "12px",
                    padding: "10px 12px",
                    marginBottom: "14px",
                    fontSize: "14px",
                  }}
                />

                {tasks.length === 0 ? (
                  <div className="tiny">No household tasks yet.</div>
                ) : (
                  <div>
                    {tasks.slice(0, 6).map((task) => {
                      const theme = getPersonTheme(task.assigned_to);

                      return (
                      <div
                        key={task.id}
                        style={{
                          display: "flex",
                          alignItems: "flex-start",
                          gap: "10px",
                          padding: "10px 12px",
                          borderRadius: "14px",
                          background:
                            task.source === "recurring"
                              ? "#f8fafc"
                              : theme.soft,

                          border:
                            task.source === "recurring"
                              ? "1px solid #cbd5e1"
                              : `1px solid ${theme.border}`,
                          marginBottom: "8px",
                        }}
                      >
                        <button
                          onClick={() => completeTask(task.id)}
                          style={{
                            width: "20px",
                            height: "20px",
                            borderRadius: "999px",
                            border: "2px solid #cbd5e1",
                            background: "white",
                            cursor: "pointer",
                            marginTop: "2px",
                            flex: "0 0 auto",
                          }}
                        />

                        <div style={{ minWidth: 0 }}>
                          <div
                            style={{
                              fontSize: "14px",
                              fontWeight: 700,
                              lineHeight: 1.3,
                            }}
                          >
                            {task.title}
                          </div>

                          {(task.assigned_to || task.due_date) && (
                            <div className="tiny">
                              {task.assigned_to && `${task.assigned_to}`}
                              {task.assigned_to && task.due_date && " · "}
                              {task.due_date &&
                                new Date(task.due_date).toLocaleDateString([], {
                                  weekday: "short",
                                  day: "numeric",
                                  month: "short",
                                })}
                            </div>
                          )}
                        </div>
                      </div>
                      );
                    })}
                  </div>
                )}
              </div>

                <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

                <div>
                  <div className="muted" style={{ marginBottom: "12px" }}>
                    Upcoming events
                  </div>

                  {calendarEvents.length === 0 ? (
                    <div style={{ color: "#667085" }}>No upcoming events found.</div>
                  ) : (
                    <EventList events={calendarEvents.slice(0, 8)} />
                  )}
                </div>
              </section>
            </aside>
          </div>
          </>
)}
          {activePage === "Kids" && <KidsPage tasks={tasks} />}
          {activePage === "Lists" && (
            <ListsPage
              lists={lists}
              newListItemText={newListItemText}
              setNewListItemText={setNewListItemText}
              addListItem={addListItem}
              completeListItem={completeListItem}
              newListName={newListName}
              setNewListName={setNewListName}
              createList={createList}
            />
          )}
          {activePage === "Planner" && (
            <PlannerPage
              tasks={tasks}
              calendarEvents={calendarEvents}
              completeTask={completeTask}
              createTask={createTask}
              newTaskTitle={newTaskTitle}
              setNewTaskTitle={setNewTaskTitle}
              plannerView={plannerView}
              setPlannerView={setPlannerView}
              setSelectedTask={setSelectedTask}
              setTaskModalOpen={setTaskModalOpen}
            />
          )}
        </main>
      </div>

      {taskModalOpen && selectedTask && (
        <TaskModal
          task={selectedTask}
          onClose={() => {
            setTaskModalOpen(false);
            setSelectedTask(null);
          }}
          onSave={saveTask}
        />
      )}

      {assistantOpen && (
        <div
          style={{
            position: "fixed",
            top: "100px",
            right: "34px",
            width: "420px",
            height: "560px",
            background: "white",
            borderRadius: "24px",
            boxShadow: "0 20px 50px rgba(0,0,0,0.18)",
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
            zIndex: 1000,
          }}
        >
          <div
            style={{
              padding: "18px 20px",
              borderBottom: "1px solid #e5e7eb",
              fontWeight: 900,
              fontSize: "18px",
            }}
          >
            CASE Assistant
          </div>

          <div
            style={{
              flex: 1,
              overflowY: "auto",
              padding: "18px",
              background: "#f8fafc",
            }}
          >
            {assistantMessages.map((m, i) => (
              <div
                key={i}
                style={{
                  marginBottom: "14px",
                  display: "flex",
                  justifyContent: m.role === "user" ? "flex-end" : "flex-start",
                }}
              >
                <div
                  style={{
                    maxWidth: "78%",
                    padding: "12px 14px",
                    borderRadius: "18px",
                    background: m.role === "user" ? "#111827" : "white",
                    color: m.role === "user" ? "white" : "#111827",
                    lineHeight: 1.5,
                    boxShadow:
                      m.role === "assistant"
                        ? "0 2px 10px rgba(0,0,0,0.06)"
                        : "none",
                  }}
                >
                  {m.text}
                </div>
              </div>
            ))}

            {assistantLoading && <div style={{ color: "#667085" }}>CASE is thinking...</div>}
          </div>

          <div
            style={{
              padding: "16px",
              borderTop: "1px solid #e5e7eb",
              display: "flex",
              gap: "10px",
            }}
          >
            <input
              value={assistantInput}
              onChange={(e) => setAssistantInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  sendAssistantMessage();
                }
              }}
              placeholder="Ask CASE something..."
              style={{
                flex: 1,
                border: "1px solid #d1d5db",
                borderRadius: "14px",
                padding: "12px 14px",
                fontSize: "14px",
              }}
            />

            <button
              onClick={startVoiceRecognition}
              style={{
                width: "42px",
                height: "42px",
                borderRadius: "999px",
                border: "none",
                cursor: "pointer",
                background: isListening ? "#ef4444" : "#e2e8f0",
                color: isListening ? "white" : "#0f172a",
                fontSize: "18px",
              }}
              title={isListening ? "Listening..." : "Speak to CASE"}
            >
              🎤
            </button>

            <button
              onClick={sendAssistantMessage}
              style={{
                border: "none",
                borderRadius: "14px",
                padding: "12px 16px",
                background: "#111827",
                color: "white",
                fontWeight: 800,
                cursor: "pointer",
              }}
            >
              Send
            </button>
          </div>
        </div>
      )}

      <style>{`
        .card {
          background: white;
          border-radius: 22px;
          padding: 22px;
          box-shadow: 0 14px 40px rgba(15, 23, 42, 0.07);
          border: 1px solid rgba(15, 23, 42, 0.06);
        }

        .listBadge {
          font-size: 11px;
          font-weight: 900;
          color: #111827;
          background: #e5e7eb;
          border-radius: 999px;
          padding: 6px 10px;
          white-space: nowrap;
        }

        .taskBadge {
          font-size: 11px;
          font-weight: 800;
          color: #475569;
          background: #f1f5f9;
          border-radius: 999px;
          padding: 4px 8px;
        }

        .innerCard {
          background: #f9fafb;
          border-radius: 16px;
          padding: 16px;
          text-align: center;
        }

        .muted {
          color: #667085;
          font-size: 14px;
        }

        .tiny {
          color: #667085;
          font-size: 12px;
          margin-top: 8px;
        }

        .button {
          border: none;
          background: #111827;
          color: white;
          border-radius: 999px;
          padding: 11px 18px;
          font-weight: 800;
          cursor: pointer;
        }

        .compactSolar {
          padding: 20px;
        }

        .solarRow {
          display: flex;
          justify-content: space-between;
          align-items: center;
          background: #f9fafb;
          border-radius: 14px;
          padding: 10px 12px;
          font-size: 14px;
        }
        .calendarPill {
          font-size: 11px;
          font-weight: 700;
          border-radius: 8px;
          padding: 4px 6px;
          margin-bottom: 5px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .eventPill {
          background: #fef3c7;
          color: #92400e;
          border: 1px solid #fde68a;
        }

        .taskPill {
          background: #f8fafc;
          color: #475569;
          border: 1px solid #e2e8f0;
        }

      `}</style>
    </div>
  );
}

function InfoMini({ icon, label, value }) {
  return (
    <div>
      <div style={{ fontSize: "17px", marginBottom: "5px", color: "#f59e0b" }}>{icon}</div>
      <div className="muted">{label}</div>
      <div style={{ fontWeight: 800 }}>{value}</div>
    </div>
  );
}

function EnergyCard({ icon, label, value, unit, subtext, inlineSubtext, color = "#111827" }) {
  return (
    <div className="card energyCard">
      <div style={{ display: "flex", alignItems: "center", gap: "8px", minWidth: 0 }}>
        <div style={{ fontSize: "22px", flex: "0 0 auto" }}>{icon}</div>
        <div style={{ minWidth: 0 }}>
          <div className="muted" style={{ fontSize: "12px", whiteSpace: "nowrap" }}>{label}</div>
          <div
            style={{
              color,
              fontSize: "20px",
              fontWeight: 900,
              lineHeight: 1.05,
              whiteSpace: "nowrap",
            }}
          >
            {value} <span style={{ fontSize: "12px", fontWeight: 800 }}>{unit}</span>
            {inlineSubtext && (
              <span style={{ fontSize: "12px", fontWeight: 900, marginLeft: "7px" }}>
                {inlineSubtext}
              </span>
            )}
          </div>
          {subtext && (
            <div style={{ color, fontSize: "12px", fontWeight: 800, marginTop: "3px" }}>
              {subtext}
            </div>
          )}
        </div>
      </div>

      <style>{`
        .energyCard {
          padding: 14px 16px;
          min-height: 76px;
          display: flex;
          align-items: center;
        }
      `}</style>
    </div>
  );
}

function TinyTempLine({ points, color }) {
  if (!points || points.length < 2) {
    return null;
  }

  const temps = points.map((p) => p.temperature);
  const min = Math.min(...temps);
  const max = Math.max(...temps);
  const range = Math.max(1, max - min);

  const coords = points.map((p, i) => {
    const x = 5 + (i * 90) / (points.length - 1);
    const y = 26 - ((p.temperature - min) / range) * 18;
    return { x, y };
  });

  const path = coords
    .map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`)
    .join(" ");

  return (
    <svg viewBox="0 0 100 32" style={{ width: "100%", marginTop: "8px" }}>
      <path
        d={path}
        fill="none"
        stroke={color}
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {coords.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r="3" fill={color} />
      ))}
    </svg>
  );
}

function EnergyDayChart({ data }) {
  const width = 1100;
  const height = 360;

  const margin = {
    top: 8,
    right: 54,
    bottom: 28,
    left: 50,
  };

  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;

  const zeroY = margin.top + plotHeight / 2;
  const maxKw = 20;

  const now = new Date();

  function minutesSinceMidnight(date) {
    return date.getHours() * 60 + date.getMinutes();
  }

  function xFromDate(date) {
    return margin.left + (minutesSinceMidnight(date) / 1440) * plotWidth;
  }

  function yFromKw(kw) {
    return zeroY - (kw / maxKw) * (plotHeight / 2);
  }

  function barHeight(kw) {
    return Math.abs(yFromKw(kw) - zeroY);
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  const rawRows = (data || []).map((row) => ({
    ...row,
    date: new Date(row.time),
  }));

  const grouped = new Map();

  rawRows.forEach((row) => {
    const d = new Date(row.date);

    d.setMinutes(Math.floor(d.getMinutes() / 15) * 15);
    d.setSeconds(0);
    d.setMilliseconds(0);

    const key = d.toISOString();

    if (!grouped.has(key)) {
      grouped.set(key, {
        count: 0,
        solar_kw: 0,
        house_load_kw: 0,
        grid_kw: 0,
        battery_soc: 0,
        time: key,
        date: d,
      });
    }

    const g = grouped.get(key);

    g.count += 1;
    g.solar_kw += row.solar_kw || 0;
    g.house_load_kw += row.house_load_kw || 0;
    g.grid_kw += row.grid_kw || 0;
    g.battery_soc += row.battery_soc || 0;
  });

  const actualRows = Array.from(grouped.values()).map((g) => ({
    ...g,
    solar_kw: g.solar_kw / g.count,
    house_load_kw: g.house_load_kw / g.count,
    grid_kw: g.grid_kw / g.count,
    battery_soc: g.battery_soc / g.count,
  }));

  const tickHours = Array.from({ length: 13 }, (_, i) => i * 2);
  const nowX = xFromDate(now);

  return (
    <div style={{ width: "100%", overflow: "hidden" }}>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        style={{ width: "100%", height: "360px", display: "block" }}
      >
        {[-20, -10, 0, 10, 20].map((kw) => {
          const y = yFromKw(kw);

          return (
            <g key={kw}>
              <line
                x1={margin.left}
                x2={margin.left + plotWidth}
                y1={y}
                y2={y}
                stroke={kw === 0 ? "#111827" : "#e5e7eb"}
                strokeWidth={kw === 0 ? 1.1 : 1}
                strokeDasharray={kw === 0 ? "0" : "4 4"}
              />
              <text
                x={margin.left - 12}
                y={y + 4}
                textAnchor="end"
                fontSize="11"
                fill="#6b7280"
              >
                {kw}
              </text>
            </g>
          );
        })}

        {tickHours.map((hour) => {
          const x = margin.left + (hour / 24) * plotWidth;
          const label =
            hour === 0
              ? "12am"
              : hour < 12
              ? `${hour}am`
              : hour === 12
              ? "12pm"
              : `${hour - 12}pm`;

          return (
            <g key={hour}>
              <line
                x1={x}
                x2={x}
                y1={margin.top}
                y2={margin.top + plotHeight}
                stroke="#eef2f7"
              />
              <text
                x={x}
                y={height - 10}
                textAnchor="middle"
                fontSize="11"
                fill="#6b7280"
              >
                {label}
              </text>
            </g>
          );
        })}

        <text x={margin.left} y={12} fontSize="12" fill="#667085">
          Power (kW)
        </text>

        <text
          x={width - margin.right}
          y={12}
          textAnchor="end"
          fontSize="12"
          fill="#667085"
        >
          Battery SoC (%)
        </text>

        {actualRows.map((row) => {
          const x = xFromDate(row.date);
          const solar = Math.max(0, row.solar_kw || 0);
          const exportKw = Math.max(0, -(row.grid_kw || 0));
          const solarUsed = clamp(solar - exportKw, 0, solar);

          const y = yFromKw(solar);
          const h = barHeight(solar);

          const innerH = barHeight(solarUsed);
          const innerY = zeroY - innerH;

          return (
            <g key={`solar-${row.time}`}>
              <RoundedBar x={x} y={y} width={8} height={h} fill="#fbbf24" opacity={0.95} />

              {solarUsed > 0 && (
                <rect
                  x={x - 0.75}
                  y={innerY + 1}
                  width={1.5}
                  height={Math.max(0, innerH - 2)}
                  rx={1}
                  fill="#92400e"
                  opacity={0.72}
                />
              )}
            </g>
          );
        })}

        {actualRows.map((row) => {
          const x = xFromDate(row.date);
          const consumption = Math.max(0, row.house_load_kw || 0);
          const importKw = Math.max(0, row.grid_kw || 0);

          const suppliedBySolarOrBattery = clamp(consumption - importKw, 0, consumption);

          const h = barHeight(consumption);
          const y = zeroY;

          const innerH = barHeight(suppliedBySolarOrBattery);
          const innerY = zeroY;

          return (
            <g key={`consumption-${row.time}`}>
              <RoundedBar x={x} y={y} width={8} height={h} fill="#93c5fd" opacity={0.5} />

              {suppliedBySolarOrBattery > 0 && (
                <rect
                  x={x - 0.75}
                  y={innerY + 1}
                  width={1.5}
                  height={Math.max(0, innerH - 2)}
                  rx={1}
                  fill="#2563eb"
                  opacity={0.38}
                />
              )}
            </g>
          );
        })}

        {actualRows.length > 1 && (
          <path
            d={batterySocPath(actualRows, margin, plotWidth, plotHeight)}
            fill="none"
            stroke="#64748b"
            strokeWidth="1"
            opacity="0.14"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        )}

        {nowX >= margin.left && nowX <= margin.left + plotWidth && (
          <g>
            <line
              x1={nowX}
              x2={nowX}
              y1={margin.top}
              y2={margin.top + plotHeight}
              stroke="#111827"
              strokeDasharray="4 4"
              opacity="0.55"
            />
            <rect x={nowX - 16} y={margin.top - 18} width="32" height="18" rx="5" fill="#111827" />
            <text
              x={nowX}
              y={margin.top - 5}
              textAnchor="middle"
              fontSize="11"
              fill="white"
              fontWeight="800"
            >
              Now
            </text>
          </g>
        )}
      </svg>

      <div
        style={{
          display: "flex",
          gap: "16px",
          flexWrap: "wrap",
          alignItems: "center",
          fontSize: "12px",
          color: "#667085",
          marginTop: "-4px",
          paddingLeft: `${margin.left}px`,
        }}
      >
        <LegendBar color="#fbbf24" label="Solar production" />
        <LegendThinLine color="#92400e" label="Into house/battery" />
        <LegendBar color="#93c5fd" label="Consumption" />
        <LegendThinLine color="#2563eb" label="Covered by PV/battery" />
        <LegendLine color="rgba(100,116,139,0.35)" label="Battery SoC" />
      </div>
    </div>
  );
}

function RoundedBar({ x, y, width, height, fill, opacity = 1 }) {
  if (!height || height <= 0) return null;

  return (
    <rect
      x={x - width / 2}
      y={y}
      width={width}
      height={height}
      rx={width / 2}
      ry={width / 2}
      fill={fill}
      opacity={opacity}
    />
  );
}

function batterySocPath(rows, margin, plotWidth, plotHeight) {
  const points = rows
    .filter((row) => row.battery_soc !== null && row.battery_soc !== undefined)
    .map((row) => {
      const date = new Date(row.time);
      const minutes = date.getHours() * 60 + date.getMinutes();
      const x = margin.left + (minutes / 1440) * plotWidth;

      const soc = Math.max(0, Math.min(100, row.battery_soc));
      const y = margin.top + plotHeight - (soc / 100) * plotHeight;

      return { x, y };
    });

  return points.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`).join(" ");
}

function LegendBar({ color, label }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
      <span
        style={{
          width: "18px",
          height: "10px",
          borderRadius: "999px",
          background: color,
          display: "inline-block",
          opacity: 0.85,
        }}
      />
      {label}
    </span>
  );
}

function LegendThinLine({ color, label }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
      <span
        style={{
          width: "3px",
          height: "16px",
          borderRadius: "999px",
          background: color,
          display: "inline-block",
          opacity: 0.75,
        }}
      />
      {label}
    </span>
  );
}

function LegendLine({ color, label }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
      <span
        style={{
          width: "22px",
          height: "2px",
          background: color,
          display: "inline-block",
        }}
      />
      {label}
    </span>
  );
}

function EventList({ events }) {
  let lastDay = null;

  return (
    <div>
      {events.map((event) => {
        const start = new Date(event.start);
        const dayLabel = start.toLocaleDateString([], {
          weekday: "long",
          day: "numeric",
          month: "short",
        });

        const showDay = dayLabel !== lastDay;
        lastDay = dayLabel;

        return (
          <div key={event.id}>
            {showDay && (
              <div
                style={{
                  marginTop: "14px",
                  marginBottom: "8px",
                  fontSize: "13px",
                  fontWeight: 900,
                  color: "#111827",
                }}
              >
                {dayLabel}
              </div>
            )}

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "64px 1fr",
                gap: "10px",
                padding: "10px 0",
                borderBottom: "1px solid #f1f5f9",
              }}
            >
              <div
                style={{
                  fontSize: "12px",
                  color: "#667085",
                  fontWeight: 800,
                }}
              >
                {event.is_all_day
                  ? "All day"
                  : start.toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
              </div>

              <div>
                <div style={{ fontSize: "14px", fontWeight: 800 }}>
                  {event.title}
                </div>

                {event.location && (
                  <a
                    href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(event.location)}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: "6px",
                      marginTop: "4px",
                      fontSize: "12px",
                      color: "#667085",
                      textDecoration: "none",
                    }}
                  >
                    <span>📍</span>
                    <span>{event.location}</span>
                  </a>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function PlannerPage({
  tasks,
  calendarEvents,
  completeTask,
  createTask,
  newTaskTitle,
  setNewTaskTitle,
  plannerView,
  setPlannerView,
  setSelectedTask,
  setTaskModalOpen,
}) {
  const [currentMonth, setCurrentMonth] = useState(new Date());

  const today = new Date();

  function sameDay(a, b) {
    return (
      a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate()
    );
  }

  const upcomingDays = Array.from({ length: 10 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() + i);
    return d;
  });

  const year = currentMonth.getFullYear();
  const month = currentMonth.getMonth();

  const firstDay = new Date(year, month, 1);

  const startDay = new Date(firstDay);

  startDay.setDate(firstDay.getDate() - firstDay.getDay());

  const days = Array.from({ length: 42 }, (_, i) => {
    const d = new Date(startDay);
    d.setDate(startDay.getDate() + i);
    return d;
  });

  function eventsForDay(day) {
    return calendarEvents.filter((event) =>
      sameDay(new Date(event.start), day)
    );
  }

  function tasksForDay(day) {
    return tasks.filter(
      (task) =>
        task.due_date && sameDay(new Date(task.due_date), day)
    );
  }

  return (
    <div>
      <section style={{ marginBottom: "18px" }}>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "flex-start",
          }}
        >
          <div>
            <h1 style={{ margin: 0, fontSize: "32px" }}>
              Planner
            </h1>

            <div
              style={{
                marginTop: "8px",
                fontSize: "15px",
                color: "#6b7280",
              }}
            >
              Household planning and coordination
            </div>
          </div>

          <div
            style={{
              display: "flex",
              gap: "8px",
              background: "#e5e7eb",
              padding: "5px",
              borderRadius: "999px",
            }}
          >
            {[
              ["month", "Month"],
              ["upcoming", "Upcoming"],
            ].map(([value, label]) => (
              <button
                key={value}
                onClick={() => setPlannerView(value)}
                style={{
                  border: "none",
                  background:
                    plannerView === value ? "#111827" : "transparent",
                  color:
                    plannerView === value ? "white" : "#111827",
                  borderRadius: "999px",
                  padding: "10px 16px",
                  fontWeight: 800,
                  cursor: "pointer",
                }}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "65% 35%",
          gap: "20px",
          alignItems: "start",
        }}
      >
        <section className="card">
          {plannerView === "month" ? (
            <>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  marginBottom: "18px",
                }}
              >
                <button
                  className="button"
                  onClick={() => {
                    const d = new Date(currentMonth);
                    d.setMonth(d.getMonth() - 1);
                    setCurrentMonth(d);
                  }}
                >
                  ←
                </button>

                <h2 style={{ margin: 0 }}>
                  {currentMonth.toLocaleDateString([], {
                    month: "long",
                    year: "numeric",
                  })}
                </h2>

                <button
                  className="button"
                  onClick={() => {
                    const d = new Date(currentMonth);
                    d.setMonth(d.getMonth() + 1);
                    setCurrentMonth(d);
                  }}
                >
                  →
                </button>
              </div>

              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(7, 1fr)",
                  gap: "8px",
                }}
              >
                {days.map((day) => {
                  const isThisMonth =
                    day.getMonth() === currentMonth.getMonth();

                  const isToday = sameDay(day, today);

                  const dayEvents = eventsForDay(day);

                  const dayTasks = tasksForDay(day);

                  return (
                    <div
                      key={day.toISOString()}
                      style={{
                        minHeight: "118px",
                        borderRadius: "16px",
                        padding: "10px",
                        background: isToday ? "#eef2ff" : "#f9fafb",
                        border: isToday
                          ? "1px solid #6366f1"
                          : "1px solid #eef2f7",
                        opacity: isThisMonth ? 1 : 0.42,
                        overflow: "hidden",
                      }}
                    >
                      <div
                        style={{
                          fontWeight: 900,
                          marginBottom: "8px",
                        }}
                      >
                        {day.getDate()}
                      </div>

                      {dayEvents.slice(0, 2).map((event) => (
                        <div
                          key={event.id}
                          className="calendarPill eventPill"
                        >
                          {event.title}
                        </div>
                      ))}

                      {dayTasks.slice(0, 2).map((task) => (
                        <div
                          key={task.id}
                          className="calendarPill taskPill"
                        >
                          ○ {task.title}
                        </div>
                      ))}
                    </div>
                  );
                })}
              </div>
            </>
          ) : (
            <>
              <h2 style={{ marginTop: 0 }}>
                Upcoming 10 days
              </h2>

              {upcomingDays.map((day) => {
                const dayEvents = eventsForDay(day);

                const dayTasks = tasksForDay(day);

                return (
                  <div
                    key={day.toISOString()}
                    style={{
                      padding: "18px 0",
                      borderBottom: "1px solid #eef2f7",
                    }}
                  >
                    <div
                      style={{
                        fontWeight: 900,
                        marginBottom: "10px",
                        fontSize: "18px",
                      }}
                    >
                      {day.toLocaleDateString([], {
                        weekday: "long",
                        day: "numeric",
                        month: "short",
                      })}
                    </div>

                    {dayEvents.map((event) => (
                      <div
                        key={event.id}
                        style={{
                          background: PERSON_THEMES.Event.soft,
                          border: `1px solid ${PERSON_THEMES.Event.border}`,
                          color: PERSON_THEMES.Event.text,
                          padding: "10px 12px",
                          borderRadius: "12px",
                          marginBottom: "8px",
                        }}
                      >
                        <div style={{ fontWeight: 800 }}>
                          {event.title}
                        </div>

                        {event.location && (
                          <div className="tiny">
                            📍 {event.location}
                          </div>
                        )}
                      </div>
                    ))}

                    {dayTasks.map((task) => {
                      const theme = getPersonTheme(task.assigned_to);

                      return (
                      <div
                        key={task.id}
                        style={{
                          background:
                            task.source === "recurring"
                              ? "#f8fafc"
                              : theme.soft,

                          border:
                            task.source === "recurring"
                              ? "1px solid #cbd5e1"
                              : `1px solid ${theme.border}`,
                          color: theme.text,
                          padding: "10px 12px",
                          borderRadius: "12px",
                          marginBottom: "8px",
                          cursor: "pointer",
                        }}
                        onClick={() => {
                          setSelectedTask(task);
                          setTaskModalOpen(true);
                        }}
                      >
                        <div style={{ fontWeight: 800 }}>
                          ○ {task.title}
                        </div>
                      </div>
                      );
                    })}
                  </div>
                );
              })}
            </>
          )}
        </section>

        <section className="card">
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              marginBottom: "14px",
            }}
          >
            <div>
              <div className="muted">Tasks</div>
              <h2
                style={{
                  margin: "4px 0 0",
                  fontSize: "28px",
                }}
              >
                Household
              </h2>
            </div>

            <button
              className="button"
              onClick={() => {
                setSelectedTask(createBlankTask());
                setTaskModalOpen(true);
              }}
            >
              +
            </button>
          </div>

          <input
            value={newTaskTitle}
            onChange={(e) => setNewTaskTitle(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") createTask();
            }}
            placeholder="Quick add task..."
            style={{
              width: "100%",
              boxSizing: "border-box",
              border: "1px solid #d1d5db",
              borderRadius: "12px",
              padding: "11px 12px",
              marginBottom: "14px",
              fontSize: "14px",
            }}
          />

          {tasks.map((task) => {
            const theme = getPersonTheme(task.assigned_to);

            return (
            <div
              key={task.id}
              style={{
                display: "flex",
                gap: "10px",
                padding: "12px",
                borderRadius: "14px",
                background:
                  task.source === "recurring"
                    ? "#f8fafc"
                    : theme.soft,

                border:
                  task.source === "recurring"
                    ? "1px solid #cbd5e1"
                    : `1px solid ${theme.border}`,
                marginBottom: "8px",
              }}
            >
              <button
                onClick={() => completeTask(task.id)}
                style={{
                  width: "20px",
                  height: "20px",
                  borderRadius: "999px",
                  border: "2px solid #cbd5e1",
                  background: "white",
                  cursor: "pointer",
                  marginTop: "2px",
                }}
              />

              <div
                style={{ cursor: "pointer", flex: 1 }}
                onClick={() => {
                  setSelectedTask(task);
                  setTaskModalOpen(true);
                }}
              >
                <div
                  style={{
                    fontWeight: 800,
                    fontSize: "14px",
                  }}
                >
                  {task.title}
                </div>

                <TaskMetaBadges task={task} />

                {(task.assigned_to ||
                  task.due_date ||
                  task.description) && (
                  <div className="tiny">
                    {task.assigned_to}

                    {task.assigned_to &&
                      task.due_date &&
                      " · "}

                    {task.due_date &&
                      new Date(
                        task.due_date
                      ).toLocaleDateString([], {
                        day: "numeric",
                        month: "short",
                      })}

                    {task.description && (
                      <>
                        <br />
                        {task.description}
                      </>
                    )}
                  </div>
                )}
              </div>
            </div>
            );
          })}
        </section>
      </div>
    </div>
  );
}

function TaskModal({ task, onClose, onSave }) {
  const [editedTask, setEditedTask] = useState(task);

  const inputStyle = {
    width: "100%",
    boxSizing: "border-box",
    border: "1px solid #d1d5db",
    borderRadius: "12px",
    padding: "11px 12px",
    fontSize: "14px",
  };

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(15,23,42,0.45)",
        display: "grid",
        placeItems: "center",
        zIndex: 2000,
      }}
    >
      <div
        className="card"
        style={{
          width: "560px",
          maxWidth: "92vw",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginBottom: "18px",
          }}
        >
          <h2 style={{ margin: 0 }}>Edit task</h2>

          <button
            onClick={onClose}
            style={{
              border: "none",
              background: "transparent",
              fontSize: "20px",
              cursor: "pointer",
            }}
          >
            ✕
          </button>
        </div>

        <div style={{ display: "grid", gap: "14px" }}>
          <input
            value={editedTask.title || ""}
            onChange={(e) =>
              setEditedTask({
                ...editedTask,
                title: e.target.value,
              })
            }
            style={inputStyle}
          />

          <textarea
            value={editedTask.description || ""}
            onChange={(e) =>
              setEditedTask({
                ...editedTask,
                description: e.target.value,
              })
            }
            rows={4}
            style={{
              ...inputStyle,
              resize: "vertical",
            }}
          />

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: "12px",
            }}
          >
            <select
              value={editedTask.assigned_to || ""}
              onChange={(e) =>
                setEditedTask({
                  ...editedTask,
                  assigned_to: e.target.value,
                })
              }
              style={inputStyle}
            >
              <option value="">Unassigned</option>
              <option value="James">James</option>
              <option value="Chris">Chris</option>
              <option value="Leo">Leo</option>
              <option value="Benny">Benny</option>
            </select>

            <input
              type="date"
              value={
                editedTask.due_date
                ? editedTask.due_date.slice(0, 10)
                : ""
              }
              onChange={(e) =>
                setEditedTask({
                  ...editedTask,
                  due_date: e.target.value,
                })
              }
              style={inputStyle}
            />
          </div>

          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: "10px",
              marginTop: "10px",
            }}
          >
            <button
              onClick={onClose}
              style={{
                border: "1px solid #d1d5db",
                background: "white",
                borderRadius: "12px",
                padding: "10px 14px",
                cursor: "pointer",
                fontWeight: 700,
              }}
            >
              Cancel
            </button>

            <button
              className="button"
              onClick={() =>
                onSave({
                  ...editedTask,
                  due_date: editedTask.due_date || null,
                  assigned_to: editedTask.assigned_to || null,
                  description: editedTask.description || null,
                })
              }
            >
              Save task
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

const KID_THEMES = {
  Leo: PERSON_THEMES.Leo,
  Benny: PERSON_THEMES.Benny,
};

function KidsPage({ tasks }) {
  const [selectedKid, setSelectedKid] = useState("Leo");

  const theme = KID_THEMES[selectedKid];

  const kids = ["Leo", "Benny"];
  const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  const responsibilities = [
    "Get dressed",
    "Dishes on sink",
    "Help pack away",
    "Feed / walk Monty",
    "Get ready by yourself",
  ];

  const [done, setDone] = useState({});

  function keyFor(task, day) {
    return `${selectedKid}-${task}-${day}`;
  }

  const kidTasksThisWeek = tasks.filter((task) => {
    if (task.assigned_to !== selectedKid || !task.due_date) return false;

    const due = new Date(task.due_date);
    const now = new Date();

    const start = new Date(now);
    start.setDate(now.getDate() - now.getDay() + 1);
    start.setHours(0, 0, 0, 0);

    const end = new Date(start);
    end.setDate(start.getDate() + 7);

    return due >= start && due < end;
  });

  return (
    <div
      style={{
        position: "relative",
        overflow: "hidden",
      }}
    >
      <section style={{ marginBottom: "18px" }}>
      <h1
        style={{
          margin: 0,
          fontSize: "32px",
          color: theme.text,
          display: "flex",
          alignItems: "center",
          gap: "10px",
        }}
      >
        <span style={{ fontSize: "38px" }}>{theme.emoji}</span>
        Kids
      </h1>
        <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
          Weekly responsibilities and kid-specific tasks
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 360px",
          gap: "20px",
          alignItems: "start",
        }}
      >
        <section className="card">
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: "20px",
            }}
          >
            <div>
              <div className="muted">Responsibility board</div>
              <h2 style={{ margin: "4px 0 0" }}>{selectedKid}'s week</h2>
            </div>

            <div
              style={{
                display: "flex",
                gap: "8px",
                background: "#e5e7eb",
                padding: "5px",
                borderRadius: "999px",
              }}
            >
              {kids.map((kid) => (
                <button
                  key={kid}
                  onClick={() => setSelectedKid(kid)}
                  style={{
                    border: "none",
                    background:
                      selectedKid === kid
                        ? KID_THEMES[kid].primary
                        : "transparent",
                    color:
                      selectedKid === kid
                        ? "white"
                        : KID_THEMES[kid].text,
                    borderRadius: "999px",
                    padding: "12px 20px",
                    fontWeight: 900,
                    cursor: "pointer",
                    transition: "all 0.2s ease",
                  }}
                >
                  {kid}
                </button>
              ))}
            </div>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "230px repeat(7, 1fr)",
              gap: "8px",
              alignItems: "stretch",
            }}
          >
            <div />

            {days.map((day) => (
              <div
                key={day}
                style={{
                  textAlign: "center",
                  fontWeight: 900,
                  color: "#667085",
                  padding: "8px 0",
                }}
              >
                {day}
              </div>
            ))}

            {responsibilities.map((responsibility) => (
              <>
                <div
                  key={`${responsibility}-label`}
                  style={{
                    background: theme.soft,
                    borderRadius: "14px",
                    padding: "14px",
                    fontWeight: 800,
                    display: "flex",
                    alignItems: "center",
                    border: `1px solid ${theme.border}`,
                    color: theme.text,
                  }}
                >
                  {responsibility}
                </div>

                {days.map((day) => {
                  const key = keyFor(responsibility, day);
                  const checked = !!done[key];

                  return (
                    <button
                      key={key}
                      onClick={() =>
                        setDone((prev) => ({
                          ...prev,
                          [key]: !prev[key],
                        }))
                      }
                      style={{
                        minHeight: "68px",
                        borderRadius: "18px",
                        border: checked
                          ? `3px solid ${theme.primary}`
                          : `2px solid ${theme.border}`,
                        background: checked ? theme.soft : "#ffffff",
                        cursor: "pointer",
                        fontSize: "30px",
                        fontWeight: 900,
                        color: checked ? theme.primary : "#cbd5e1",
                        transition: "all 0.15s ease",
                        boxShadow: checked
                          ? `0 8px 20px ${theme.soft}`
                          : "none",
                      }}
                    >
                      {checked ? "✓" : "○"}
                    </button>
                  );
                })}
              </>
            ))}
          </div>
        </section>

        <aside className="card">
          <div className="muted">This week</div>
          <h2 style={{ margin: "4px 0 16px" }}>{selectedKid}'s tasks</h2>

          {kidTasksThisWeek.length === 0 ? (
            <div className="tiny">No tasks due this week.</div>
          ) : (
            kidTasksThisWeek.map((task) => (
              <div
                key={task.id}
                style={{
                  padding: "12px",
                  borderRadius: "14px",
                  background:
                    task.source === "recurring"
                      ? "#f8fafc"
                      : theme.soft,

                  border:
                    task.source === "recurring"
                      ? "1px solid #cbd5e1"
                      : `1px solid ${theme.border}`,
                  marginBottom: "8px",
                }}
              >
                <div style={{ fontWeight: 800 }}>{task.title}</div>
                <div className="tiny">
                  Due{" "}
                  {new Date(task.due_date).toLocaleDateString([], {
                    weekday: "short",
                    day: "numeric",
                    month: "short",
                  })}
                </div>
              </div>
            ))
          )}

          <div style={{ height: "1px", background: "#e5e7eb", margin: "22px 0" }} />

          <div className="muted">Later</div>
          <div style={{ marginTop: "8px", lineHeight: 1.5 }}>
            Rewards, goals and weekly reset will go here.
          </div>
        </aside>
      </div>
    </div>
  );
}

function ListsPage({
  lists,
  newListItemText,
  setNewListItemText,
  addListItem,
  completeListItem,
  newListName,
  setNewListName,
  createList,
}) {
  const primaryList =
    lists.find((list) => list.is_primary) ||
    lists.find((list) => list.list_type === "grocery") ||
    lists[0];

  const otherLists = lists.filter((list) => list.id !== primaryList?.id);

  return (
    <div>
      <section style={{ marginBottom: "18px" }}>
        <h1 style={{ margin: 0, fontSize: "32px" }}>Lists</h1>
        <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
          Groceries, Bunnings runs, packing lists and household checklists
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: primaryList ? "minmax(360px, 32%) 1fr" : "1fr",
          gap: "20px",
          alignItems: "start",
        }}
      >
        {primaryList && (
          <ListCard
            list={primaryList}
            featured
            newListItemText={newListItemText}
            setNewListItemText={setNewListItemText}
            addListItem={addListItem}
            completeListItem={completeListItem}
          />
        )}

        <section>
          <div
            style={{
              display: "grid",
              gridTemplateColumns:
                otherLists.length <= 1
                  ? "1fr"
                  : "repeat(auto-fit, minmax(300px, 1fr))",
              gap: "20px",
            }}
          >
            {otherLists.map((list) => (
              <ListCard
                key={list.id}
                list={list}
                newListItemText={newListItemText}
                setNewListItemText={setNewListItemText}
                addListItem={addListItem}
                completeListItem={completeListItem}
              />
            ))}

            <div className="card">
              <div className="muted">New list</div>
              <h2 style={{ margin: "4px 0 14px" }}>Create a list</h2>

              <input
                value={newListName}
                onChange={(e) => setNewListName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    createList();
                  }
                }}
                placeholder="e.g. Camping, Costco, Birthday party..."
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  border: "1px solid #d1d5db",
                  borderRadius: "12px",
                  padding: "11px 12px",
                  marginBottom: "12px",
                  fontSize: "14px",
                }}
              />

              <button className="button" onClick={createList}>
                Add list
              </button>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

function ListCard({
  list,
  featured = false,
  newListItemText,
  setNewListItemText,
  addListItem,
  completeListItem,
}) {
  const isGrocery = list.list_type === "grocery" || list.is_primary;

  return (
    <section
      className="card"
      style={{
        border: featured ? "2px solid #111827" : undefined,
        position: featured ? "sticky" : "relative",
        top: featured ? "20px" : undefined,
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          gap: "12px",
          alignItems: "flex-start",
          marginBottom: "14px",
        }}
      >
        <div>
          <div className="muted">
            {isGrocery ? "Primary list" : list.list_type || "List"}
          </div>
          <h2 style={{ margin: "4px 0 0", fontSize: featured ? "28px" : "24px" }}>
            {isGrocery ? "🛒 " : "📝 "}
            {list.name}
          </h2>
        </div>

        {isGrocery && <span className="listBadge">Pinned</span>}
      </div>

      <div style={{ display: "flex", gap: "8px", marginBottom: "16px" }}>
        <input
          value={newListItemText[list.id] || ""}
          onChange={(e) =>
            setNewListItemText((prev) => ({
              ...prev,
              [list.id]: e.target.value,
            }))
          }
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              addListItem(list.id);
            }
          }}
          placeholder={`Add to ${list.name}...`}
          style={{
            flex: 1,
            minWidth: 0,
            border: "1px solid #d1d5db",
            borderRadius: "12px",
            padding: "11px 12px",
            fontSize: "14px",
          }}
        />

        <button className="button" onClick={() => addListItem(list.id)}>
          +
        </button>
      </div>

      {list.items?.length === 0 ? (
        <div className="tiny">Nothing on this list yet.</div>
      ) : (
        <div style={{ display: "grid", gap: "8px" }}>
          {list.items.map((item) => (
            <div
              key={item.id}
              style={{
                display: "flex",
                gap: "10px",
                alignItems: "flex-start",
                padding: "10px 12px",
                borderRadius: "14px",
                background: "#f8fafc",
                border: "1px solid #e2e8f0",
              }}
            >
              <button
                onClick={() => completeListItem(item.id)}
                style={{
                  width: "20px",
                  height: "20px",
                  borderRadius: "999px",
                  border: "2px solid #cbd5e1",
                  background: "white",
                  cursor: "pointer",
                  marginTop: "1px",
                  flex: "0 0 auto",
                }}
              />

              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 800, fontSize: "14px", lineHeight: 1.25 }}>
                  {item.text}
                </div>

                {(item.quantity || item.notes) && (
                  <div className="tiny">
                    {item.quantity}
                    {item.quantity && item.notes && " · "}
                    {item.notes}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {isGrocery && (
        <div
          style={{
            marginTop: "18px",
            padding: "12px",
            borderRadius: "14px",
            background: "#fef3c7",
            border: "1px solid #fde68a",
            color: "#92400e",
            fontSize: "13px",
            fontWeight: 700,
            lineHeight: 1.35,
          }}
        >
          Later: CASE can bulk-add recipe ingredients here and eventually help build a Woolworths order.
        </div>
      )}
    </section>
  );
}


export default App;
