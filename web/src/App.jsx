import { useEffect, useState } from "react";

import { API_BASE, apiFetch } from "./config";

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

const GAGGIMATE_MODES = [
  { id: "standby", label: "Standby", mode: 0 },
  { id: "brew", label: "Brew", mode: 1 },
  { id: "steam", label: "Steam", mode: 2 },
  { id: "water", label: "Water", mode: 3 },
];


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

function getSpeechRecognition() {
  return window.SpeechRecognition || window.webkitSpeechRecognition;
}

function useIsMobile() {
  const [isMobile, setIsMobile] = useState(() => window.innerWidth <= 820);

  useEffect(() => {
    function updateIsMobile() {
      setIsMobile(window.innerWidth <= 820);
    }

    updateIsMobile();
    window.addEventListener("resize", updateIsMobile);

    return () => window.removeEventListener("resize", updateIsMobile);
  }, []);

  return isMobile;
}

function selectCaseVoice() {
  if (!window.speechSynthesis) return null;

  const voices = window.speechSynthesis.getVoices();
  const preferredNames = [
    "Daniel",
    "Oliver",
    "Arthur",
    "Google UK English Male",
    "Microsoft James",
    "Microsoft William",
  ];

  return (
    voices.find((voice) => preferredNames.some((name) => voice.name.includes(name))) ||
    voices.find((voice) => voice.lang === "en-AU") ||
    voices.find((voice) => voice.lang === "en-GB") ||
    voices.find((voice) => voice.lang.startsWith("en")) ||
    null
  );
}

function App() {
  const [activePage, setActivePage] = useState("Home");
  const isMobile = useIsMobile();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const [data, setData] = useState(null);
  const [recentEnergy, setRecentEnergy] = useState([]);
  const [weather, setWeather] = useState(null);
  const [error, setError] = useState(null);
  const [todaySummary, setTodaySummary] = useState(null);
  const [energyFlowPeriod, setEnergyFlowPeriod] = useState("now");
  const [energyFlowSummary, setEnergyFlowSummary] = useState(null);
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
  const [assistantPhase, setAssistantPhase] = useState("idle");
  const [assistantStatus, setAssistantStatus] = useState(null);
  const [systemStatus, setSystemStatus] = useState(null);
  const [securityStatus, setSecurityStatus] = useState(null);
  const [gaggimateStatus, setGaggimateStatus] = useState(null);
  const [gaggimateProfiles, setGaggimateProfiles] = useState([]);
  const [gaggimateError, setGaggimateError] = useState(null);
  const [roborockStatus, setRoborockStatus] = useState(null);
  const [roborockError, setRoborockError] = useState(null);
  const [newsItems, setNewsItems] = useState([]);
  const [newsSummary, setNewsSummary] = useState(null);
  const [newsError, setNewsError] = useState(null);
  const [newsLoading, setNewsLoading] = useState(false);

  async function loadTasks() {
    try {
      const res = await apiFetch(`${API_BASE}/tasks`);
  
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
      const res = await apiFetch(`${API_BASE}/tasks`, {
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
      const res = await apiFetch(`${API_BASE}/tasks/${taskId}/complete`, {
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

    const res = await apiFetch(url, {
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
      const res = await apiFetch(`${API_BASE}/lists`);
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
      const res = await apiFetch(`${API_BASE}/lists/${listId}/items`, {
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
      const res = await apiFetch(`${API_BASE}/lists/items/${itemId}/complete`, {
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
      const res = await apiFetch(`${API_BASE}/lists`, {
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
      const res = await apiFetch(`${API_BASE}/calendar/upcoming`);
      if (!res.ok) throw new Error(`Calendar API returned ${res.status}`);

      const json = await res.json();
      setCalendarEvents(json.events || []);
    } catch (err) {
      console.error(err);
    }
  }

  async function loadAssistantStatus() {
    try {
      const res = await apiFetch(`${API_BASE}/assistant/status`);
      if (!res.ok) throw new Error(`Assistant status API returned ${res.status}`);

      const json = await res.json();
      setAssistantStatus(json);
      return json;
    } catch (err) {
      console.error(err);
      setAssistantStatus((current) => ({
        ...(current || {}),
        available: current?.available === true ? true : null,
        voice_available: current?.voice_available === true ? true : null,
        status_error: err.message,
        llm: {
          ...(current?.llm || {}),
          message: err.message,
        },
      }));
      return null;
    }
  }

  async function loadSystemStatus() {
    try {
      const res = await apiFetch(`${API_BASE}/system/status`);
      if (!res.ok) throw new Error(`System status API returned ${res.status}`);

      const json = await res.json();
      setSystemStatus(json);
    } catch (err) {
      console.error(err);
      setSystemStatus({
        api: { status: "error", error: err.message },
      });
    }
  }

  async function loadSecurityStatus() {
    try {
      const res = await apiFetch(`${API_BASE}/security/status`);
      if (!res.ok) throw new Error(`Security status API returned ${res.status}`);

      const json = await res.json();
      setSecurityStatus(json);
    } catch (err) {
      console.error(err);
      setSecurityStatus({
        error: err.message,
      });
    }
  }

  async function sendAssistantMessage(messageOverride = null) {
    const userMessage = messageOverride || assistantInput;

    if (!userMessage.trim()) return;

    const latestStatus = await loadAssistantStatus();

    if (latestStatus?.available === false) {
      setAssistantMessages((prev) => [
        ...prev,
        { role: "user", text: userMessage },
        {
          role: "assistant",
          text: "CASE assistant is unavailable because the LLM service is offline.",
        },
      ]);
      setAssistantInput("");
      return;
    }

    setAssistantMessages((prev) => [
      ...prev,
      { role: "user", text: userMessage },
    ]);

    setAssistantInput("");
    setAssistantLoading(true);
    setAssistantPhase("thinking");

    try {
      const res = await apiFetch(`${API_BASE}/case/ask`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: userMessage,
        }),
      });

      const json = await res.json();

      if (!res.ok) {
        throw new Error(json.detail || `Assistant API returned ${res.status}`);
      }

      if (json.assistant_available === false) {
        setAssistantStatus({
          available: false,
          voice_available: false,
          llm: json.llm_status,
        });
      }

      if (json.ui_action?.type === "navigate" && json.ui_action.page) {
        setActivePage(json.ui_action.page);
        setAssistantOpen(false);
        setMobileMenuOpen(false);
      }

      if (json.ui_action?.type === "refresh_data") {
        await refreshVisibleData();
      }

      const isSpeaking = speakCase(json.reply);

        if (
          json.intent === "list_command" ||
          json.intent === "task_command" ||
          json.intent === "feature_suggestion_create"
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

        if (!isSpeaking) {
          setAssistantPhase("idle");
        }
    } catch {
      setAssistantMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: "Something went wrong talking to the assistant.",
        },
      ]);
      setAssistantPhase("idle");
    }

    setAssistantLoading(false);
  }

  function speakCase(text) {
    if (!window.speechSynthesis || !text) return false;
  
    window.speechSynthesis.cancel();
  
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "en-AU";
    utterance.voice = selectCaseVoice();
    utterance.rate = 0.9;
    utterance.pitch = 0.75;
    utterance.volume = 0.95;
    utterance.onstart = () => setAssistantPhase("speaking");
    utterance.onend = () => setAssistantPhase("idle");
    utterance.onerror = () => setAssistantPhase("idle");
  
    window.speechSynthesis.speak(utterance);
    return true;
  }

  async function startVoiceRecognition() {
    const SpeechRecognition = getSpeechRecognition();

    if (!window.isSecureContext) {
      setAssistantOpen(true);
      setAssistantMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: "Voice is blocked by Chrome on this HTTP local-network page. Text chat is still available.",
        },
      ]);
      return;
    }

    const latestStatus = await loadAssistantStatus();

    if (latestStatus?.voice_available === false) {
      setAssistantOpen(true);
      setAssistantMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: "Voice is unavailable because the LLM service is offline.",
        },
      ]);
      return;
    }

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
      setAssistantPhase("listening");
    };

    recognition.onend = () => {
      setIsListening(false);
      setAssistantPhase((current) => current === "listening" ? "idle" : current);
    };

    recognition.onerror = (event) => {
      console.error(event);
      setIsListening(false);
      setAssistantPhase("idle");
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
      const res = await apiFetch(`${API_BASE}/decisions/summary`);
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
      const res = await apiFetch(`${API_BASE}/energy/recent`);
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
      const res = await apiFetch(`${API_BASE}/energy/today-summary`);
      if (!res.ok) throw new Error(`Today summary API returned ${res.status}`);
      const json = await res.json();
      setTodaySummary(json);
    } catch (err) {
      console.error(err);
    }
  }

  async function loadEnergyFlowSummary(period = energyFlowPeriod) {
    try {
      const res = await apiFetch(`${API_BASE}/energy/flow-summary?period=${encodeURIComponent(period)}`);
      if (!res.ok) throw new Error(`Energy flow API returned ${res.status}`);
      const json = await res.json();
      setEnergyFlowSummary(json);
    } catch (err) {
      console.error(err);
    }
  }

  async function loadWeather() {
    try {
      const res = await apiFetch(`${API_BASE}/weather/summary`);
      if (!res.ok) throw new Error(`Weather API returned ${res.status}`);
      const json = await res.json();
      setWeather(json);
    } catch (err) {
      console.error(err);
    }
  }

  async function loadGaggimateStatus() {
    try {
      const res = await apiFetch(`${API_BASE}/iot/gaggimate/status`);
      if (!res.ok) throw new Error(`GaggiMate API returned ${res.status}`);
      const json = await res.json();
      setGaggimateStatus(json);
      setGaggimateError(json.error || null);
    } catch (err) {
      console.error(err);
      setGaggimateError(err.message);
      setGaggimateStatus((current) => ({
        ...(current || {}),
        online: false,
        error: err.message,
      }));
    }
  }

  async function loadGaggimateProfiles() {
    try {
      const res = await apiFetch(`${API_BASE}/iot/gaggimate/profiles`);
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `GaggiMate profiles returned ${res.status}`);

      setGaggimateProfiles(json.profiles || []);
      setGaggimateError(null);
    } catch (err) {
      console.error(err);
      setGaggimateProfiles([]);
      setGaggimateError(err.message);
    }
  }

  async function refreshGaggimate() {
    try {
      const res = await apiFetch(`${API_BASE}/iot/gaggimate/refresh`, {
        method: "POST",
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `GaggiMate refresh returned ${res.status}`);

      setGaggimateStatus(json);
      setGaggimateError(json.error || null);
    } catch (err) {
      console.error(err);
      setGaggimateError(err.message);
    }
  }

  async function selectGaggimateProfile(profileId) {
    try {
      const res = await apiFetch(`${API_BASE}/iot/gaggimate/profiles/select`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ profile_id: profileId }),
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `Profile select returned ${res.status}`);

      await Promise.allSettled([
        loadGaggimateStatus(),
        loadGaggimateProfiles(),
      ]);
    } catch (err) {
      console.error(err);
      setGaggimateError(err.message);
    }
  }

  async function changeGaggimateMode(mode) {
    try {
      const res = await apiFetch(`${API_BASE}/iot/gaggimate/mode`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ mode }),
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `Mode change returned ${res.status}`);

      setGaggimateStatus({
        ...(json.status || {}),
        cached: false,
      });
      setGaggimateError(null);
    } catch (err) {
      console.error(err);
      setGaggimateError(err.message);
    }
  }

  async function loadRoborockStatus() {
    try {
      const res = await apiFetch(`${API_BASE}/iot/roborock/status`);
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || json.message || `Roborock API returned ${res.status}`);

      setRoborockStatus(json);
      setRoborockError(json.snapshot_error || json.message || null);
    } catch (err) {
      console.error(err);
      setRoborockError(err.message);
      setRoborockStatus((current) => ({
        ...(current || {}),
        available: false,
        message: err.message,
      }));
    }
  }

  async function refreshRoborock() {
    try {
      const res = await apiFetch(`${API_BASE}/iot/roborock/refresh`, {
        method: "POST",
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || json.message || `Roborock refresh returned ${res.status}`);

      setRoborockStatus(json);
      setRoborockError(json.snapshot_error || json.message || null);
    } catch (err) {
      console.error(err);
      setRoborockError(err.message);
    }
  }

  async function runRoborockCommand(command, route = null) {
    try {
      const res = await apiFetch(`${API_BASE}/iot/roborock/command`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ command, route }),
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `Roborock command returned ${res.status}`);

      setRoborockStatus(json.status || json);
      setRoborockError(null);
    } catch (err) {
      console.error(err);
      setRoborockError(err.message);
    }
  }

  async function loadNews() {
    try {
      const res = await apiFetch(`${API_BASE}/news/latest`);
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `News API returned ${res.status}`);

      setNewsItems(json.items || []);
      setNewsError(null);
    } catch (err) {
      console.error(err);
      setNewsError(err.message);
    }
  }

  async function loadNewsSummary() {
    try {
      const res = await apiFetch(`${API_BASE}/news/summary`);
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || `News summary returned ${res.status}`);

      setNewsSummary(json);
      setNewsItems(json.items || []);
      setNewsError(null);
    } catch (err) {
      console.error(err);
      setNewsError(err.message);
    }
  }

  async function refreshNews() {
    setNewsLoading(true);

    try {
      const res = await apiFetch(`${API_BASE}/news/refresh`, {
        method: "POST",
      });
      const json = await res.json();

      if (!res.ok) throw new Error(json.error || json.snapshot_error || `News refresh returned ${res.status}`);

      await loadNewsSummary();
    } catch (err) {
      console.error(err);
      setNewsError(err.message);
    } finally {
      setNewsLoading(false);
    }
  }

  async function refreshVisibleData() {
    await Promise.allSettled([
      loadData(),
      loadRecentEnergy(),
      loadTodaySummary(),
      loadEnergyFlowSummary(),
      loadWeather(),
      loadCalendarEvents(),
      loadTasks(),
      loadLists(),
      loadAssistantStatus(),
      loadSystemStatus(),
      loadSecurityStatus(),
      loadGaggimateStatus(),
      loadGaggimateProfiles(),
      loadRoborockStatus(),
      loadNewsSummary(),
    ]);
  }

  useEffect(() => {
    const initialLoad = setTimeout(() => {
      loadData();
      loadRecentEnergy();
      loadEnergyFlowSummary();
      loadWeather();
      loadTodaySummary();
      loadCalendarEvents();
      loadTasks();
      loadLists();
      loadAssistantStatus();
      loadSystemStatus();
      loadSecurityStatus();
      loadGaggimateStatus();
      loadGaggimateProfiles();
      loadRoborockStatus();
      loadNewsSummary();
    }, 0);

    const energyInterval = setInterval(() => {
      loadData();
      loadRecentEnergy();
    }, 5000);

    const weatherInterval = setInterval(() => {
      loadWeather();
    }, 300000);

    const calendarInterval = setInterval(() => {
      loadCalendarEvents();
    }, 900000);

    const assistantStatusInterval = setInterval(() => {
      loadAssistantStatus();
    }, 30000);

    const systemStatusInterval = setInterval(() => {
      loadSystemStatus();
      loadSecurityStatus();
    }, 60000);

    const gaggimateInterval = setInterval(() => {
      loadGaggimateStatus();
    }, 30000);

    const roborockInterval = setInterval(() => {
      loadRoborockStatus();
    }, 60000);

    const newsInterval = setInterval(() => {
      loadNewsSummary();
    }, 300000);

    return () => {
      clearTimeout(initialLoad);
      clearInterval(energyInterval);
      clearInterval(weatherInterval);
      clearInterval(calendarInterval);
      clearInterval(assistantStatusInterval);
      clearInterval(systemStatusInterval);
      clearInterval(gaggimateInterval);
      clearInterval(roborockInterval);
      clearInterval(newsInterval);
    };
  }, []);

  useEffect(() => {
    loadEnergyFlowSummary(energyFlowPeriod);

    const flowInterval = setInterval(() => {
      loadEnergyFlowSummary(energyFlowPeriod);
    }, 5000);

    return () => clearInterval(flowInterval);
  }, [energyFlowPeriod]);

  useEffect(() => {
    if (activePage === "IoT") {
      loadGaggimateProfiles();
      loadGaggimateStatus();
      loadRoborockStatus();
    }

    if (activePage === "News") {
      loadNewsSummary();
    }
  }, [activePage]);

  useEffect(() => {
    if (assistantOpen) {
      loadAssistantStatus();
    }
  }, [assistantOpen]);

  useEffect(() => {
    function refreshAssistantStatus() {
      if (!document.hidden) {
        loadAssistantStatus();
      }
    }

    window.addEventListener("focus", refreshAssistantStatus);
    document.addEventListener("visibilitychange", refreshAssistantStatus);

    return () => {
      window.removeEventListener("focus", refreshAssistantStatus);
      document.removeEventListener("visibilitychange", refreshAssistantStatus);
    };
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
  const assistantAvailability = assistantStatus?.available;
  const assistantAvailable = assistantAvailability !== false;
  const speechRecognitionAvailable = Boolean(getSpeechRecognition());
  const voiceBlockedByAssistant = assistantStatus?.voice_available === false;
  const voiceAvailable = !voiceBlockedByAssistant;
  const voiceUnavailableTitle = !window.isSecureContext
    ? "Voice requires HTTPS or localhost in Chrome"
    : !speechRecognitionAvailable
      ? "Speech recognition is not supported in this browser"
      : "Voice unavailable";
  const assistantStatusText =
    assistantAvailability === true
      ? "Assistant online"
      : assistantAvailability === false
        ? "Assistant unavailable"
        : "Checking assistant";
  const assistantPhaseText = {
    idle: assistantStatusText,
    listening: "Listening",
    thinking: "Thinking",
    speaking: "Speaking",
  }[assistantPhase] || assistantStatusText;
  const navItems = [
    ["⌂", "Home"],
    ["🗓", "Planner"],
    ["🧒", "Kids"],
    ["📝", "Lists"],
    ["⚡", "Energy"],
    ["☕", "IoT"],
    ["☁", "Weather"],
    ["📰", "News"],
    ["🛡", "Security"],
  ];
  const systemStatusItems = buildSystemStatusItems(systemStatus);

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f4f6f8",
        fontFamily: "Inter, system-ui, sans-serif",
        color: "#111827",
      }}
    >
      <div
        style={{
          display: "flex",
          flexDirection: isMobile ? "column" : "row",
        }}
      >
        <aside
          style={{
            width: isMobile ? "100%" : "120px",
            minHeight: isMobile ? "auto" : "100vh",
            background: "#0f172a",
            color: "white",
            padding: isMobile ? "18px 16px" : "28px 14px",
            boxSizing: "border-box",
            position: isMobile ? "sticky" : "static",
            top: 0,
            zIndex: 50,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: "14px",
              marginBottom: isMobile && !mobileMenuOpen ? 0 : isMobile ? "14px" : "34px",
            }}
          >
            <div style={{ fontWeight: "900", fontSize: isMobile ? "26px" : "22px" }}>
              CASE
            </div>

            {isMobile && (
              <button
                onClick={() => setMobileMenuOpen((open) => !open)}
                aria-label="Toggle navigation"
                style={{
                  width: "44px",
                  height: "40px",
                  border: "1px solid rgba(255,255,255,0.16)",
                  borderRadius: "12px",
                  background: "rgba(255,255,255,0.08)",
                  color: "white",
                  cursor: "pointer",
                  fontSize: "22px",
                  fontWeight: 900,
                  lineHeight: 1,
                }}
              >
                ☰
              </button>
            )}
          </div>

          {(!isMobile || mobileMenuOpen) && (
            <nav
              style={{
                display: isMobile ? "grid" : "block",
                gridTemplateColumns: isMobile ? "1fr 1fr" : undefined,
                gap: isMobile ? "8px" : undefined,
              }}
            >
              {navItems.map(([icon, item]) => (
              <div
                key={item}
                onClick={() => {
                  setActivePage(item);
                  setMobileMenuOpen(false);
                }}
                style={{
                  cursor: "pointer",
                  display: "flex",
                  gap: "10px",
                  alignItems: "center",
                  fontSize: "14px",
                  fontWeight: activePage === item ? 800 : 500,
                  opacity: activePage === item ? 1 : 0.68,
                  marginBottom: isMobile ? 0 : "22px",
                  padding: activePage === item ? "12px 10px" : isMobile ? "12px 10px" : "8px 10px",
                  borderRadius: "10px",
                  whiteSpace: "nowrap",
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
            </nav>
          )}
        </aside>

        <main
          style={{
            flex: 1,
            padding: isMobile ? "18px 14px" : "24px 30px",
            maxWidth: "1900px",
            minWidth: 0,
            overflowX: "hidden",
          }}
        >
        {activePage === "Home" && (
          <>
          {isMobile && (
            <section
              style={{
                borderRadius: "22px",
                background: "#111827",
                color: "white",
                padding: "20px",
                marginBottom: "16px",
                width: "100%",
                boxSizing: "border-box",
                boxShadow: "0 14px 40px rgba(15, 23, 42, 0.16)",
              }}
            >
              <div className="muted" style={{ color: "rgba(255,255,255,0.72)" }}>
                Voice control
              </div>
              <h1 style={{ margin: "6px 0 14px", fontSize: "28px", lineHeight: 1.1 }}>
                Ask CASE
              </h1>
              <button
                onClick={startVoiceRecognition}
                className={isListening ? "voiceButton listening" : "voiceButton"}
                style={{
                  width: "100%",
                  border: "none",
                  borderRadius: "18px",
                  padding: "18px",
                  background: isListening ? "#ef4444" : "#f8fafc",
                  color: isListening ? "white" : "#111827",
                  fontSize: "17px",
                  fontWeight: 900,
                  cursor: "pointer",
                }}
              >
                <span
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    justifyContent: "center",
                    width: "30px",
                    height: "30px",
                    borderRadius: "999px",
                    marginRight: "10px",
                    background: isListening ? "rgba(255,255,255,0.2)" : "#111827",
                    color: isListening ? "white" : "white",
                  }}
                >
                  🎤
                </span>
                {isListening ? "Listening..." : "Press to talk to CASE"}
              </button>
              <div style={{ marginTop: "12px", fontSize: "13px", opacity: 0.78 }}>
                {assistantPhaseText}
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginTop: "14px" }}>
                <button
                  onClick={() => setActivePage("Lists")}
                  style={{
                    border: "none",
                    borderRadius: "14px",
                    padding: "12px",
                    background: "rgba(255,255,255,0.12)",
                    color: "white",
                    fontWeight: 800,
                  }}
                >
                  Lists
                </button>
                <button
                  onClick={() => setActivePage("Home")}
                  style={{
                    border: "none",
                    borderRadius: "14px",
                    padding: "12px",
                    background: "rgba(255,255,255,0.12)",
                    color: "white",
                    fontWeight: 800,
                  }}
                >
                  Stats
                </button>
              </div>
            </section>
          )}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: isMobile ? "1fr" : "1fr 380px",
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
                  gridTemplateColumns: isMobile ? "1fr" : "1.7fr 0.9fr",
                  gap: "18px",
                  marginBottom: "18px",
                }}
              >
                {weather && (
                  <div className="card">
                    <div style={{ display: "grid", gridTemplateColumns: isMobile ? "1fr" : "1fr 1.2fr", gap: "20px" }}>
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
                          gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                          alignItems: "center",
                          borderLeft: isMobile ? "none" : "1px solid #e5e7eb",
                          borderTop: isMobile ? "1px solid #e5e7eb" : "none",
                          paddingLeft: isMobile ? 0 : "18px",
                          paddingTop: isMobile ? "14px" : 0,
                          gap: isMobile ? "10px" : 0,
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

                    <div
                      style={{
                        display: "grid",
                        gridTemplateColumns: isMobile ? "repeat(3, minmax(0, 1fr))" : "repeat(5, 1fr)",
                        gap: isMobile ? "8px" : "0",
                      }}
                    >
                      {weather.daily.slice(0, isMobile ? 3 : 5).map((day, i) => (
                        <div
                          key={day.date}
                          style={{
                            padding: isMobile ? "10px 8px" : "7px 12px",
                            borderLeft: !isMobile && i !== 0 ? "1px solid #e5e7eb" : "none",
                            borderRadius: isMobile ? "12px" : undefined,
                            textAlign: "center",
                            minWidth: 0,
                          }}
                        >
                          <div>
                            <div style={{ fontWeight: 800, marginBottom: isMobile ? "2px" : "6px" }}>
                              {new Date(day.date).toLocaleDateString([], { weekday: "short" })}
                            </div>
                            <div style={{ fontSize: isMobile ? "22px" : "26px", marginBottom: "2px" }}>{weatherIcon(day)}</div>
                          </div>
                          <div>
                            <div style={{ fontWeight: 900, fontSize: isMobile ? "19px" : "20px" }}>
                              {Math.round(day.temp_max)}°
                            </div>
                            <div style={{ color: "#2563eb", fontWeight: 700 }}>
                              {Math.round(day.temp_min)}°
                            </div>
                          </div>

                          <div className="tiny" style={{ marginTop: "5px" }}>
                            💧 {day.rain_probability}%
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
                  gridTemplateColumns: isMobile ? "repeat(2, minmax(0, 1fr))" : "repeat(4, minmax(0, 1fr))",
                  gap: "14px",
                  marginBottom: "18px",
                }}
              >
                <EnergyCard icon="☀️" label="Production" value={formatKw(state.solar_kw)} unit="kW" />
                <EnergyCard icon="🏠" label="Consumption" value={formatKw(state.house_load_kw)} unit="kW" />
                <EnergyCard
                  icon="☀️"
                  label="Solar today"
                  value={(todaySummary?.solar_kwh ?? 0).toFixed(1)}
                  unit="kWh"
                />
                <EnergyCard
                  icon="🏡"
                  label="Usage today"
                  value={(todaySummary?.house_load_kwh ?? 0).toFixed(1)}
                  unit="kWh"
                />
                <EnergyCard
                  icon="🚗"
                  label="Car"
                  value={todaySummary?.ev_kw === null || todaySummary?.ev_kw === undefined ? "--" : Number(todaySummary.ev_kw).toFixed(2)}
                  unit="kW"
                  subtext={todaySummary?.ev_status === "smart_port_not_mapped" ? "Not mapped yet" : undefined}
                  color={todaySummary?.ev_charging ? "#16a34a" : "#111827"}
                />
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

              <CoffeeMachineHomeCard
                status={gaggimateStatus}
                profiles={gaggimateProfiles}
                onOpen={() => setActivePage("IoT")}
                onRefresh={refreshGaggimate}
                onModeChange={changeGaggimateMode}
                onProfileSelect={selectGaggimateProfile}
              />

              <section
                style={{
                  display: "grid",
                  gridTemplateColumns: isMobile ? "1fr" : "300px 1fr",
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

                <div className="card energyTrendCard">
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "4px" }}>
                    <div>
                      <div className="muted">{isMobile ? "Energy flow" : "Energy trend"}</div>
                      <h2 style={{ margin: "2px 0 0", fontSize: "24px" }}>
                        {isMobile ? periodLabel(energyFlowPeriod) : "Today"}
                      </h2>
                    </div>
                    <div className="muted">{isMobile ? energyFlowSummary?.unit || "kW" : "15-minute view"}</div>
                  </div>

                  <div style={{ width: "100%", minWidth: 0 }}>
                    {isMobile ? (
                      <EnergyFlowCard
                        summary={energyFlowSummary}
                        activePeriod={energyFlowPeriod}
                        onPeriodChange={(period) => {
                          setEnergyFlowPeriod(period);
                          loadEnergyFlowSummary(period);
                        }}
                      />
                    ) : (
                      <EnergyDayChart data={recentEnergy} isMobile={isMobile} />
                    )}
                  </div>
                </div>
              </section>
            </div>

            <aside
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "18px",
                position: isMobile ? "static" : "sticky",
                top: isMobile ? undefined : "20px",
              }}
            >
              <section
                style={{
                  borderRadius: "22px",
                  background: "#111827",
                  color: "white",
                  padding: "18px",
                  boxShadow: "0 14px 40px rgba(15, 23, 42, 0.16)",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: "14px",
                  }}
                >
                  <button
                    onClick={() => setAssistantOpen(!assistantOpen)}
                    style={{
                      flex: 1,
                      border: "none",
                      background: "transparent",
                      color: "inherit",
                      padding: 0,
                      fontWeight: 900,
                      fontSize: "16px",
                      cursor: "pointer",
                      textAlign: "left",
                    }}
                  >
                    Ask CASE
                    <div style={{ fontSize: "12px", opacity: 0.72, marginTop: "4px" }}>
                      Energy, tasks, events and household planning
                    </div>
                    <div
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: "6px",
                        marginTop: "10px",
                        padding: "5px 8px",
                        borderRadius: "999px",
                        background: assistantAvailable
                          ? "rgba(34, 197, 94, 0.16)"
                          : "rgba(248, 113, 113, 0.18)",
                        color: assistantAvailable ? "#bbf7d0" : "#fecaca",
                        fontSize: "11px",
                        fontWeight: 800,
                      }}
                    >
                      <span
                        style={{
                          width: "7px",
                          height: "7px",
                          borderRadius: "999px",
                          background: assistantAvailable ? "#22c55e" : "#ef4444",
                        }}
                      />
                      {assistantPhaseText}
                    </div>
                  </button>

                  <button
                    onClick={startVoiceRecognition}
                    style={{
                      width: "44px",
                      height: "44px",
                      flex: "0 0 44px",
                      borderRadius: "999px",
                      border: "none",
                      cursor: "pointer",
                      background: !voiceAvailable
                        ? "rgba(255, 255, 255, 0.08)"
                        : isListening
                          ? "#ef4444"
                          : "rgba(255, 255, 255, 0.14)",
                      color: voiceAvailable ? "white" : "rgba(255, 255, 255, 0.45)",
                      fontSize: "18px",
                    }}
                    title={
                      !voiceAvailable
                        ? voiceUnavailableTitle
                        : isListening
                          ? "Listening..."
                          : "Speak to CASE"
                    }
                  >
                    🎤
                  </button>
                </div>
              </section>

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
                    {tasks.slice(0, 6).map((task, index) => {
                      const theme = getPersonTheme(task.assigned_to);

                      return (
                      <div
                        key={task.id || `${task.title}-${index}`}
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

                <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

                <SystemStatusPanel items={systemStatusItems} compact />
              </section>
            </aside>
          </div>
          </>
)}
          {activePage === "IoT" && (
            <IoTPage
              gaggimateStatus={gaggimateStatus}
              gaggimateProfiles={gaggimateProfiles}
              gaggimateError={gaggimateError}
              refreshGaggimate={refreshGaggimate}
              loadGaggimateProfiles={loadGaggimateProfiles}
              selectGaggimateProfile={selectGaggimateProfile}
              changeGaggimateMode={changeGaggimateMode}
              roborockStatus={roborockStatus}
              roborockError={roborockError}
              refreshRoborock={refreshRoborock}
              runRoborockCommand={runRoborockCommand}
            />
          )}
          {activePage === "News" && (
            <NewsPage
              newsItems={newsItems}
              newsSummary={newsSummary}
              newsError={newsError}
              newsLoading={newsLoading}
              refreshNews={refreshNews}
            />
          )}
          {activePage === "Kids" && <KidsPage tasks={tasks} />}
          {activePage === "Lists" && (
            <ListsPage
              lists={lists}
              isMobile={isMobile}
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
          {activePage === "Security" && (
            <SecurityPage
              securityStatus={securityStatus}
              assistantStatus={assistantStatus}
              apiBase={API_BASE}
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
            top: isMobile ? "0" : "100px",
            right: isMobile ? "0" : "34px",
            bottom: isMobile ? "0" : undefined,
            left: isMobile ? "0" : undefined,
            width: isMobile ? "100%" : "420px",
            height: isMobile ? "100dvh" : "560px",
            background: "white",
            borderRadius: isMobile ? "0" : "24px",
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
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: "12px",
              }}
            >
              <div>CASE Assistant</div>
              <button
                onClick={() => setAssistantOpen(false)}
                aria-label="Close CASE Assistant"
                style={{
                  width: "32px",
                  height: "32px",
                  borderRadius: "999px",
                  border: "none",
                  background: "#f3f4f6",
                  color: "#111827",
                  cursor: "pointer",
                  fontSize: "20px",
                  lineHeight: 1,
                }}
              >
                ×
              </button>
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                marginTop: "6px",
                color: assistantAvailable ? "#15803d" : "#b91c1c",
                fontSize: "12px",
                fontWeight: 800,
              }}
            >
              <span
                style={{
                  width: "8px",
                  height: "8px",
                  borderRadius: "999px",
                  background: assistantAvailable ? "#22c55e" : "#ef4444",
                }}
              />
              {assistantPhaseText}
            </div>
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
            {assistantPhase === "speaking" && (
              <div style={{ color: "#667085" }}>CASE is speaking...</div>
            )}
            {!assistantAvailable && (
              <div style={{ color: "#b91c1c", fontSize: "13px", fontWeight: 700 }}>
                The rest of CASE is online. Assistant and voice are waiting for the LLM service.
              </div>
            )}
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
                if (e.key === "Enter" && !assistantLoading) {
                  sendAssistantMessage();
                }
              }}
              placeholder={
                assistantAvailable
                  ? "Ask CASE something..."
                  : "Assistant may be offline - send to recheck"
              }
              disabled={assistantLoading}
              style={{
                flex: 1,
                border: "1px solid #d1d5db",
                borderRadius: "14px",
                padding: "12px 14px",
                fontSize: "14px",
                background: assistantLoading ? "#f3f4f6" : "white",
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
                background: !voiceAvailable
                  ? "#f3f4f6"
                  : isListening
                    ? "#ef4444"
                    : "#e2e8f0",
                color: !voiceAvailable
                  ? "#9ca3af"
                  : isListening
                    ? "white"
                    : "#0f172a",
                fontSize: "18px",
              }}
              title={
                !voiceAvailable
                  ? voiceUnavailableTitle
                  : isListening
                    ? "Listening..."
                    : "Speak to CASE"
              }
            >
              🎤
            </button>

            <button
              onClick={sendAssistantMessage}
              disabled={assistantLoading}
              style={{
                border: "none",
                borderRadius: "14px",
                padding: "12px 16px",
                background: assistantLoading ? "#d1d5db" : "#111827",
                color: "white",
                fontWeight: 800,
                cursor: assistantLoading ? "not-allowed" : "pointer",
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

        .voiceButton {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          position: relative;
        }

        .voiceButton.listening {
          animation: voicePulse 1.25s ease-in-out infinite;
        }

        @keyframes voicePulse {
          0% {
            box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.42);
          }
          70% {
            box-shadow: 0 0 0 14px rgba(239, 68, 68, 0);
          }
          100% {
            box-shadow: 0 0 0 0 rgba(239, 68, 68, 0);
          }
        }

        .compactSolar {
          padding: 20px;
        }

        .coffeeHomeCard {
          display: grid;
          grid-template-columns: 92px minmax(0, 1fr);
          align-items: stretch;
          column-gap: 16px;
          row-gap: 12px;
          margin-bottom: 18px;
          padding: 14px 16px;
        }

        .coffeeHomeArtwork {
          width: 92px;
          height: 118px;
          object-fit: contain;
          align-self: center;
          justify-self: center;
        }

        .coffeeHomeBody {
          min-width: 0;
          display: grid;
          align-content: center;
          gap: 8px;
        }

        .deviceArtwork {
          width: 64px;
          height: 64px;
          border-radius: 16px;
          object-fit: contain;
          background: #f8fafc;
          border: 1px solid #e5e7eb;
          padding: 5px;
        }

        .deviceArtwork.large {
          width: 96px;
          height: 96px;
          border-radius: 18px;
          padding: 7px;
        }

        .coffeeRefreshButton {
          border-radius: 12px;
          padding: 10px 12px;
          white-space: nowrap;
          align-self: center;
          grid-column: 1 / -1;
          width: 100%;
        }

        .coffeeHomeCard .coffeeModeControl.compact {
          grid-column: 1 / -1;
        }

        .coffeeHomeCard .coffeeProfileControl.compact {
          grid-column: 1 / -1;
        }

        .coffeeProfileControl {
          display: grid;
          gap: 7px;
        }

        .caseSelect {
          width: 100%;
          border: 1px solid #dbe3ec;
          border-radius: 12px;
          background: #f8fafc;
          color: #111827;
          font: inherit;
          font-weight: 800;
          padding: 11px 12px;
          min-height: 42px;
        }

        .caseSelect:disabled {
          cursor: not-allowed;
          opacity: 0.58;
        }

        .coffeeModeControl {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 6px;
          padding: 5px;
          border-radius: 14px;
          background: #f1f5f9;
          border: 1px solid #e2e8f0;
        }

        .coffeeModeButton {
          border: none;
          border-radius: 10px;
          background: transparent;
          color: #475569;
          cursor: pointer;
          font-size: 12px;
          font-weight: 900;
          min-height: 34px;
          padding: 0 8px;
          white-space: nowrap;
        }

        .coffeeModeButton.active {
          background: #111827;
          color: white;
          box-shadow: 0 4px 12px rgba(15, 23, 42, 0.16);
        }

        .coffeeModeButton:disabled {
          cursor: not-allowed;
          opacity: 0.48;
        }

        .energyTrendCard {
          padding-bottom: 18px;
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

        @media (max-width: 820px) {
          .card {
            border-radius: 18px;
            padding: 18px;
          }

          .coffeeHomeCard {
            grid-template-columns: 82px minmax(0, 1fr);
            gap: 12px;
            padding: 14px;
            min-height: 0;
          }

          .coffeeHomeArtwork {
            width: 82px;
            height: 112px;
          }

          .deviceArtwork {
            width: 54px;
            height: 54px;
          }

          .coffeeModeControl.compact {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }

          .coffeeRefreshButton {
            width: 100%;
          }

          .energyTrendCard {
            padding: 18px 14px 14px;
          }

          .newsLayout {
            grid-template-columns: 1fr !important;
          }
        }

      `}</style>
    </div>
  );
}

function buildSystemStatusItems(status) {
  if (!status) {
    return [
      { label: "API", status: "checking" },
      { label: "DB", status: "checking" },
      { label: "Worker", status: "checking" },
      { label: "LLM", status: "checking" },
    ];
  }

  return [
    { label: "API", status: status.api?.status || "unknown" },
    { label: "DB", status: status.db?.status || "unknown" },
    { label: "Worker", status: status.worker?.status || "unknown" },
    {
      label: "LLM",
      status: status.llm?.available ? "ok" : "offline",
    },
    {
      label: "Calendar",
      status: status.calendar?.status || "unknown",
    },
    {
      label: "Weather",
      status: status.weather?.status || "unknown",
    },
    {
      label: "Energy",
      status: status.sigenergy?.status || "unknown",
    },
    {
      label: "Recurring",
      status: status.recurring_tasks?.status || "unknown",
    },
    {
      label: "Coffee",
      status: status.gaggimate?.status || "unknown",
    },
    {
      label: "Roborock",
      status: status.roborock?.status || "unknown",
    },
    {
      label: "News",
      status: status.news?.status || "unknown",
    },
  ];
}

function statusTone(status) {
  if (status === "ok") {
    return {
      text: "#15803d",
      background: "#dcfce7",
      dot: "#22c55e",
    };
  }

  if (status === "checking" || status === "unknown" || status === "stale") {
    return {
      text: "#92400e",
      background: "#fef3c7",
      dot: "#f59e0b",
    };
  }

  return {
    text: "#b91c1c",
    background: "#fee2e2",
    dot: "#ef4444",
  };
}

function SystemStatusPanel({ items, compact = false }) {
  const content = (
    <>
      <div className="muted" style={{ marginBottom: "12px" }}>
        System
      </div>

      <div style={{ display: "grid", gap: "8px" }}>
        {items.map((item) => {
          const tone = statusTone(item.status);

          return (
            <div
              key={item.label}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: "10px",
                fontSize: "13px",
              }}
            >
              <span style={{ fontWeight: 800 }}>{item.label}</span>
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "6px",
                  borderRadius: "999px",
                  background: tone.background,
                  color: tone.text,
                  padding: "5px 8px",
                  fontSize: "11px",
                  fontWeight: 900,
                  textTransform: "capitalize",
                }}
              >
                <span
                  style={{
                    width: "7px",
                    height: "7px",
                    borderRadius: "999px",
                    background: tone.dot,
                  }}
                />
                {item.status}
              </span>
            </div>
          );
        })}
      </div>
    </>
  );

  if (compact) {
    return (
      <div style={{ marginTop: "18px" }}>
        {content}
      </div>
    );
  }

  return (
    <section className="card" style={{ padding: "18px" }}>
      {content}
    </section>
  );
}

function CoffeeMachineHomeCard({ status, profiles = [], onOpen, onRefresh, onModeChange, onProfileSelect }) {
  const online = status?.online === true;
  const temp = status?.current_temp_c;
  const target = status?.target_temp_c;
  const activeMode = status?.mode;
  const selectedProfile = getSelectedGaggimateProfile(profiles, status?.profile_label);

  return (
    <section className="card coffeeHomeCard">
      <img
        className="coffeeHomeArtwork"
        src="/devices/gaggia-classic.png"
        alt="Gaggia Classic coffee machine"
      />

      <div className="coffeeHomeBody">
        <button
          onClick={onOpen}
          style={{
            border: "none",
            background: "transparent",
            padding: 0,
            textAlign: "left",
            cursor: "pointer",
            minWidth: 0,
          }}
        >
          <div className="muted">Coffee machine</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: "10px", marginTop: "5px", flexWrap: "wrap" }}>
            <strong style={{ fontSize: "22px" }}>
              {online && temp !== null && temp !== undefined ? `${Math.round(temp)}°C` : "Offline"}
            </strong>
            {online && target !== null && target !== undefined && (
            <span className="tiny" style={{ marginTop: 0 }}>Target {Math.round(target)}°C</span>
            )}
          </div>
        </button>

        <div className="tiny" style={{ marginTop: "5px" }}>
          {status?.profile_label || "No profile"} · {status?.mode_label || "Waiting for GaggiMate"}
        </div>
      </div>

      <GaggimateModeControl
        activeMode={activeMode}
        online={online}
        onModeChange={onModeChange}
        compact
      />

      <GaggimateProfileSelect
        profiles={profiles}
        selectedProfile={selectedProfile}
        online={online}
        onProfileSelect={onProfileSelect}
        compact
      />

      <button className="button coffeeRefreshButton" onClick={onRefresh}>
        Refresh
      </button>
    </section>
  );
}

function GaggimateProfileSelect({ profiles = [], selectedProfile, online, onProfileSelect, compact = false }) {
  const selectedId = selectedProfile?.id || "";

  return (
    <div className={compact ? "coffeeProfileControl compact" : "coffeeProfileControl"}>
      <label className="muted" htmlFor={compact ? "coffee-profile-home" : "coffee-profile-iot"}>
        Profile
      </label>
      <select
        id={compact ? "coffee-profile-home" : "coffee-profile-iot"}
        value={selectedId}
        disabled={!online || profiles.length === 0}
        onChange={(event) => {
          if (event.target.value) {
            onProfileSelect(event.target.value);
          }
        }}
        className="caseSelect"
      >
        {profiles.length === 0 ? (
          <option value="">No profiles loaded</option>
        ) : (
          profiles.map((profile) => (
            <option key={profile.id || profile.label} value={profile.id || ""}>
              {profile.label || profile.id}
            </option>
          ))
        )}
      </select>
      {selectedProfile?.description && (
        <div className="tiny" style={{ marginTop: "6px" }}>
          {selectedProfile.description}
        </div>
      )}
    </div>
  );
}

function GaggimateModeControl({ activeMode, online, onModeChange, compact = false }) {
  return (
    <div
      className={compact ? "coffeeModeControl compact" : "coffeeModeControl"}
      aria-label="Coffee machine mode"
    >
      {GAGGIMATE_MODES.map((mode) => {
        const active = activeMode === mode.mode;

        return (
          <button
            key={mode.id}
            disabled={!online}
            onClick={() => onModeChange(mode.id)}
            className={active ? "coffeeModeButton active" : "coffeeModeButton"}
            title={`Set coffee machine to ${mode.label}`}
          >
            {mode.label}
          </button>
        );
      })}
    </div>
  );
}

function getSelectedGaggimateProfile(profiles, activeProfileLabel) {
  return (
    profiles.find((profile) => profile.selected) ||
    profiles.find((profile) => profile.label === activeProfileLabel) ||
    null
  );
}

function InfoMini({ icon, label, value }) {
  return (
    <div style={{ minWidth: 0, textAlign: "center" }}>
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

function periodLabel(period) {
  return {
    now: "Now",
    today: "Today",
    yesterday: "Yesterday",
    week: "This week",
  }[period] || "Today";
}

function EnergyFlowCard({ summary, activePeriod, onPeriodChange }) {
  const unit = summary?.unit || (activePeriod === "now" ? "kW" : "kWh");
  const values = summary?.values || {};
  const sources = [
    { id: "solar", label: "Solar", value: values.solar || 0, color: "#facc15" },
    { id: "battery", label: "Battery", value: values.battery_discharge || 0, color: "#2dd4bf" },
    { id: "grid", label: "Grid", value: values.grid_import || 0, color: "#60a5fa" },
  ].filter((item) => item.value > 0.01);
  const homeLoad = Math.max(0, (values.home_load || 0) - (values.ev || 0));
  const sinks = [
    {
      id: "battery",
      label: "Battery",
      value: values.battery_charge || 0,
      percent: values.battery_soc ? `${Number(values.battery_soc).toFixed(0)}%` : null,
      color: "#14b8a6",
    },
    { id: "load", label: "Load", value: homeLoad, color: "#a855f7" },
    { id: "ev", label: "EV", value: values.ev || 0, color: "#14b8a6" },
    { id: "grid", label: "Grid", value: values.grid_export || 0, color: "#4f46e5" },
  ].filter((item) => item.value > 0.01);

  const fallbackSource = [{ id: "none-source", label: "No source", value: 0, color: "#e2e8f0" }];
  const fallbackSink = [{ id: "none-sink", label: "No load", value: 0, color: "#e2e8f0" }];
  const visibleSources = sources.length ? sources : fallbackSource;
  const visibleSinks = sinks.length ? sinks : fallbackSink;
  const totalSource = Math.max(visibleSources.reduce((sum, item) => sum + item.value, 0), 1);
  const totalSink = Math.max(visibleSinks.reduce((sum, item) => sum + item.value, 0), 1);

  const sourceBlocks = layoutFlowBlocks(visibleSources, totalSource, 760);
  const sinkBlocks = layoutFlowBlocks(visibleSinks, totalSink, 760);
  const flows = pairFlowBlocks(sourceBlocks, sinkBlocks);

  return (
    <div>
      <svg viewBox="0 0 560 800" style={{ width: "100%", display: "block", marginTop: "10px" }}>
        <defs>
          {flows.map((flow, index) => (
            <linearGradient key={`flow-gradient-${index}`} id={`flow-gradient-${index}`} x1="0" x2="1">
              <stop offset="0%" stopColor={flow.source.color} stopOpacity="0.58" />
              <stop offset="100%" stopColor={flow.sink.color} stopOpacity="0.58" />
            </linearGradient>
          ))}
        </defs>

        {flows.map((flow, index) => (
          <path
            key={`flow-${index}`}
            d={`M 132 ${flow.sourceY} C 250 ${flow.sourceY}, 310 ${flow.sinkY}, 428 ${flow.sinkY}`}
            fill="none"
            stroke={`url(#flow-gradient-${index})`}
            strokeWidth={Math.max(5, flow.width)}
            strokeLinecap="round"
            opacity="0.7"
          />
        ))}

        {sourceBlocks.map((item) => (
          <EnergyFlowNode key={item.id} item={item} x={10} width={128} unit={unit} align="left" />
        ))}

        {sinkBlocks.map((item) => (
          <EnergyFlowNode key={item.id} item={item} x={422} width={128} unit={unit} align="right" />
        ))}
      </svg>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
          gap: "8px",
          marginTop: "8px",
        }}
      >
        {["now", "today", "yesterday", "week"].map((period) => (
          <button
            key={period}
            className="button"
            onClick={() => onPeriodChange(period)}
            style={{
              minHeight: "42px",
              padding: "8px 6px",
              borderRadius: "14px",
              fontSize: "12px",
              background: activePeriod === period ? "#111827" : "#e5e7eb",
              color: activePeriod === period ? "white" : "#111827",
            }}
          >
            {periodLabel(period)}
          </button>
        ))}
      </div>
    </div>
  );
}

function layoutFlowBlocks(items, total, availableHeight) {
  const gap = 10;
  const minHeight = 124;
  const maxHeight = 300;
  let y = 20;

  return items.map((item) => {
    const height = Math.max(minHeight, Math.min(maxHeight, (item.value / total) * (availableHeight - gap * (items.length - 1))));
    const block = { ...item, y, height, midY: y + height / 2 };
    y += height + gap;
    return block;
  });
}

function pairFlowBlocks(sources, sinks) {
  if (!sources.length || !sinks.length) return [];

  const flows = [];
  const sourceState = sources.map((item) => ({ ...item, remaining: item.value, cursor: item.y }));
  const sinkState = sinks.map((item) => ({ ...item, remaining: item.value, cursor: item.y }));
  let sinkIndex = 0;
  const maxTotal = Math.max(
    sourceState.reduce((sum, item) => sum + item.value, 0),
    sinkState.reduce((sum, item) => sum + item.value, 0),
    1
  );

  sourceState.forEach((source) => {
    while (source.remaining > 0.01 && sinkIndex < sinkState.length) {
      const sink = sinkState[sinkIndex];
      const amount = Math.min(source.remaining, sink.remaining);
      const sourceHeight = Math.max(3, (amount / Math.max(source.value, 1)) * source.height);
      const sinkHeight = Math.max(3, (amount / Math.max(sink.value, 1)) * sink.height);

      flows.push({
        source,
        sink,
        sourceY: source.cursor + sourceHeight / 2,
        sinkY: sink.cursor + sinkHeight / 2,
        width: Math.max(6, (amount / maxTotal) * 130),
      });

      source.cursor += sourceHeight;
      sink.cursor += sinkHeight;
      source.remaining -= amount;
      sink.remaining -= amount;

      if (sink.remaining <= 0.01) {
        sinkIndex += 1;
      }
    }
  });

  return flows;
}

function EnergyFlowNode({ item, x, width, unit, align }) {
  const textX = align === "right" ? x + width - 10 : x + 10;
  const textAnchor = align === "right" ? "end" : "start";

  return (
    <g>
      <rect
        x={x}
        y={item.y}
        width={width}
        height={item.height}
        rx="7"
        fill={item.color}
        opacity="0.9"
      />
      <rect
        x={x + 10}
        y={item.y + 10}
        width={width - 20}
        height="34"
        rx="6"
        fill="rgba(255,255,255,0.64)"
      />
      <text x={textX} y={item.y + 33} textAnchor={textAnchor} fontSize="20" fontWeight="900" fill="#111827">
        {item.label}
      </text>
      <text x={textX} y={item.y + 78} textAnchor={textAnchor} fontSize="32" fontWeight="900" fill="#111827">
        {item.value > 0 ? Number(item.value).toFixed(item.value >= 10 ? 1 : 2) : "--"}
      </text>
      <text x={textX} y={item.y + 110} textAnchor={textAnchor} fontSize="20" fill="#111827">
        {item.value > 0 ? unit : ""}
      </text>
      {item.percent && (
        <text x={textX} y={item.y + item.height - 16} textAnchor={textAnchor} fontSize="22" fill="#111827">
          {item.percent}
        </text>
      )}
    </g>
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

function EnergyDayChart({ data, isMobile = false }) {
  const width = 1100;
  const height = isMobile ? 210 : 320;

  const margin = {
    top: isMobile ? 16 : 18,
    right: isMobile ? 22 : 54,
    bottom: isMobile ? 18 : 24,
    left: isMobile ? 30 : 50,
  };

  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;

  const zeroY = margin.top + plotHeight / 2;
  const maxKw = isMobile ? 10 : 20;

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
        ev_kw: 0,
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
    g.ev_kw += row.ev_kw || 0;
    g.grid_kw += row.grid_kw || 0;
    g.battery_soc += row.battery_soc || 0;
  });

  const actualRows = Array.from(grouped.values()).map((g) => ({
    ...g,
    solar_kw: g.solar_kw / g.count,
    house_load_kw: g.house_load_kw / g.count,
    ev_kw: g.ev_kw / g.count,
    grid_kw: g.grid_kw / g.count,
    battery_soc: g.battery_soc / g.count,
  }));

  const tickHours = isMobile
    ? [0, 6, 12, 18, 24]
    : Array.from({ length: 13 }, (_, i) => i * 2);
  const nowX = xFromDate(now);
  const legendItems = [
    { type: "bar", color: "#fbbf24", label: "Solar production", compactLabel: "Solar" },
    { type: "thin", color: "#92400e", label: "Into house/battery", compactLabel: "To home" },
    { type: "bar", color: "#93c5fd", label: "Consumption", compactLabel: "Use" },
    { type: "bar", color: "#14b8a6", label: "EV charging", compactLabel: "EV" },
    { type: "thin", color: "#2563eb", label: "Covered by PV/battery", compactLabel: "Covered" },
    { type: "line", color: "rgba(100,116,139,0.35)", label: "Battery SoC", compactLabel: "Battery" },
  ];

  return (
    <div style={{ width: "100%", overflow: "hidden" }}>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        style={{ width: "100%", height: isMobile ? "210px" : "320px", display: "block" }}
      >
        {(isMobile ? [-10, -5, 0, 5, 10] : [-20, -10, 0, 10, 20]).map((kw) => {
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
              : hour === 24
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
          const evKw = clamp(Math.max(0, row.ev_kw || 0), 0, consumption);
          const importKw = Math.max(0, row.grid_kw || 0);

          const suppliedBySolarOrBattery = clamp(consumption - importKw, 0, consumption);

          const h = barHeight(consumption);
          const y = zeroY;

          const innerH = barHeight(suppliedBySolarOrBattery);
          const innerY = zeroY;
          const evH = barHeight(evKw);
          const evY = zeroY + Math.max(0, h - evH);

          return (
            <g key={`consumption-${row.time}`}>
              <RoundedBar x={x} y={y} width={8} height={h} fill="#93c5fd" opacity={0.5} />

              {evKw > 0 && (
                <rect
                  x={x - 4}
                  y={evY}
                  width={8}
                  height={evH}
                  rx={4}
                  ry={4}
                  fill="#14b8a6"
                  opacity={0.78}
                />
              )}

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
          display: isMobile ? "grid" : "flex",
          gridTemplateColumns: isMobile ? "repeat(3, minmax(0, auto))" : undefined,
          gap: isMobile ? "8px" : "14px",
          rowGap: isMobile ? "6px" : undefined,
          columnGap: isMobile ? "8px" : undefined,
          flexWrap: isMobile ? undefined : "wrap",
          alignItems: "center",
          justifyContent: isMobile ? "space-between" : "center",
          fontSize: isMobile ? "10px" : "12px",
          color: "#667085",
          marginTop: isMobile ? "2px" : "-4px",
          paddingLeft: isMobile ? 0 : `${margin.left}px`,
          paddingRight: isMobile ? 0 : `${margin.right}px`,
        }}
      >
        {legendItems.map((item) => (
          <ChartLegendItem
            key={item.label}
            type={item.type}
            color={item.color}
            label={isMobile ? item.compactLabel : item.label}
            compact={isMobile}
          />
        ))}
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

function LegendBar({ color, label, compact = false }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: compact ? "4px" : "6px", whiteSpace: "nowrap" }}>
      <span
        style={{
          width: compact ? "14px" : "18px",
          height: compact ? "8px" : "10px",
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

function LegendThinLine({ color, label, compact = false }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: compact ? "4px" : "6px", whiteSpace: "nowrap" }}>
      <span
        style={{
          width: "3px",
          height: compact ? "12px" : "16px",
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

function LegendLine({ color, label, compact = false }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: compact ? "4px" : "6px", whiteSpace: "nowrap" }}>
      <span
        style={{
          width: compact ? "16px" : "22px",
          height: "2px",
          background: color,
          display: "inline-block",
        }}
      />
      {label}
    </span>
  );
}

function ChartLegendItem({ type, color, label, compact = false }) {
  if (type === "bar") {
    return <LegendBar color={color} label={label} compact={compact} />;
  }

  if (type === "thin") {
    return <LegendThinLine color={color} label={label} compact={compact} />;
  }

  return <LegendLine color={color} label={label} compact={compact} />;
}

function EventList({ events }) {
  return (
    <div>
      {events.map((event, index) => {
        const start = new Date(event.start);
        const dayLabel = start.toLocaleDateString([], {
          weekday: "long",
          day: "numeric",
          month: "short",
        });
        const previousEvent = events[index - 1];
        const previousDayLabel = previousEvent
          ? new Date(previousEvent.start).toLocaleDateString([], {
              weekday: "long",
              day: "numeric",
              month: "short",
            })
          : null;

        const showDay = dayLabel !== previousDayLabel;

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
  isMobile = false,
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
  const secondaryCardCount = otherLists.length + 1;

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
          gridTemplateColumns: isMobile
            ? "1fr"
            : primaryList
            ? "minmax(360px, 420px) minmax(640px, 1fr)"
            : "1fr",
          gap: "20px",
          alignItems: "start",
          overflowX: isMobile ? "hidden" : "auto",
          paddingBottom: "8px",
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

        <section style={{ minWidth: 0, overflowX: isMobile ? "hidden" : "auto", paddingBottom: "8px" }}>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: isMobile
                ? "1fr"
                : `repeat(${secondaryCardCount}, minmax(300px, 1fr))`,
              gap: "20px",
              minWidth: isMobile
                ? 0
                : `${secondaryCardCount * 300 + (secondaryCardCount - 1) * 20}px`,
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

function IoTPage({
  gaggimateStatus,
  gaggimateProfiles,
  gaggimateError,
  refreshGaggimate,
  loadGaggimateProfiles,
  selectGaggimateProfile,
  changeGaggimateMode,
  roborockStatus,
  roborockError,
  refreshRoborock,
  runRoborockCommand,
}) {
  const online = gaggimateStatus?.online === true;
  const currentTemp = gaggimateStatus?.current_temp_c;
  const targetTemp = gaggimateStatus?.target_temp_c;
  const activeProfile = gaggimateStatus?.profile_label;
  const selectedProfile = getSelectedGaggimateProfile(gaggimateProfiles, activeProfile);
  const roborockRoutes = roborockStatus?.routes || [];
  const [selectedRoborockRoute, setSelectedRoborockRoute] = useState(roborockRoutes[0] || "");
  const activeRoborockRoute = selectedRoborockRoute || roborockRoutes[0] || "";
  const roborockState = compactRoborockState(roborockStatus);

  return (
    <div>
      <section style={{ marginBottom: "18px" }}>
        <h1 style={{ margin: 0, fontSize: "32px" }}>IoT</h1>
        <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
          Local devices, controls and telemetry
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
          gap: "16px",
          alignItems: "start",
        }}
      >
        <section className="card">
          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px", alignItems: "flex-start" }}>
            <div style={{ display: "flex", gap: "12px", alignItems: "center", minWidth: 0 }}>
              <img
                className="deviceArtwork large"
                src="/devices/gaggia-classic.png"
                alt="Gaggia Classic coffee machine"
              />
              <div style={{ minWidth: 0 }}>
                <div className="muted">GaggiMate</div>
                <h2 style={{ margin: "6px 0 0", fontSize: "26px" }}>Gaggia Classic</h2>
              </div>
            </div>
            <span
              style={{
                borderRadius: "999px",
                padding: "7px 10px",
                fontSize: "12px",
                fontWeight: 900,
                background: online ? "#dcfce7" : "#fee2e2",
                color: online ? "#15803d" : "#b91c1c",
              }}
            >
              {online ? "Online" : "Offline"}
            </span>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
              gap: "10px",
              marginTop: "18px",
            }}
          >
            <MetricBox label="Temp" value={formatMetric(currentTemp, "°C")} />
            <MetricBox label="Target" value={formatMetric(targetTemp, "°C")} />
            <MetricBox label="Pressure" value={formatMetric(gaggimateStatus?.pressure_bar, " bar", 1)} />
            <MetricBox label="Flow" value={formatMetric(gaggimateStatus?.flow_ml_s, " ml/s", 1)} />
          </div>

          <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

          <div className="muted" style={{ marginBottom: "10px" }}>Mode</div>
          <GaggimateModeControl
            activeMode={gaggimateStatus?.mode}
            online={online}
            onModeChange={changeGaggimateMode}
          />

          <div style={{ marginTop: "16px" }}>
            <GaggimateProfileSelect
              profiles={gaggimateProfiles}
              selectedProfile={selectedProfile}
              online={online}
              onProfileSelect={selectGaggimateProfile}
            />
            <button
              className="button"
              onClick={loadGaggimateProfiles}
              style={{ marginTop: "10px", width: "100%", background: "#334155" }}
            >
              Load profiles
            </button>
          </div>

          <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

          <div style={{ display: "grid", gap: "10px" }}>
            <DeviceDetail label="Mode" value={gaggimateStatus?.mode_label || "--"} />
            <DeviceDetail label="Profile" value={activeProfile || "--"} />
            <DeviceDetail label="Host" value={gaggimateStatus?.host || "--"} />
            <DeviceDetail
              label="Last seen"
              value={
                gaggimateStatus?.captured_at
                  ? new Date(gaggimateStatus.captured_at).toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                    })
                  : "--"
              }
            />
          </div>

          {(gaggimateError || gaggimateStatus?.error) && (
            <div
              style={{
                marginTop: "16px",
                borderRadius: "14px",
                padding: "12px",
                background: "#fef2f2",
                color: "#991b1b",
                fontSize: "13px",
                fontWeight: 700,
                lineHeight: 1.4,
              }}
            >
              {gaggimateError || gaggimateStatus?.error}
            </div>
          )}

          <button className="button" onClick={refreshGaggimate} style={{ marginTop: "16px", width: "100%" }}>
            Refresh machine
          </button>
        </section>

        <section className="card">
          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px", alignItems: "flex-start" }}>
            <div style={{ display: "flex", gap: "12px", alignItems: "center", minWidth: 0 }}>
              <img
                className="deviceArtwork large"
                src="/devices/roborock-qrevo-maxq.png"
                alt="Roborock Qrevo MaxQ vacuum"
              />
              <div style={{ minWidth: 0 }}>
                <div className="muted">Roborock</div>
                <h2 style={{ margin: "6px 0 0", fontSize: "26px" }}>Qrevo MaxQ</h2>
              </div>
            </div>
            <span
              style={{
                borderRadius: "999px",
                padding: "7px 10px",
                fontSize: "12px",
                fontWeight: 900,
                background: roborockStatus?.available ? "#dcfce7" : "#fee2e2",
                color: roborockStatus?.available ? "#15803d" : "#b91c1c",
              }}
            >
              {roborockStatus?.available ? "Online" : roborockStatus?.configured === false ? "Setup needed" : "Offline"}
            </span>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
              gap: "10px",
              marginTop: "18px",
            }}
          >
            <MetricBox label="Status" value={roborockState || "--"} />
            <MetricBox
              label="Battery"
              value={roborockStatus?.battery_level === null || roborockStatus?.battery_level === undefined
                ? "--"
                : formatMetric(roborockStatus?.battery_level, "%")}
            />
          </div>

          <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

          <div className="muted" style={{ marginBottom: "10px" }}>Controls</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "8px" }}>
            <button className="button" onClick={() => runRoborockCommand("start")}>Start</button>
            <button className="button" onClick={() => runRoborockCommand("pause")} style={{ background: "#334155" }}>Pause</button>
            <button className="button" onClick={() => runRoborockCommand("dock")} style={{ background: "#475569" }}>Dock</button>
          </div>

          {roborockRoutes.length > 0 ? (
            <>
              <div className="muted" style={{ margin: "16px 0 10px" }}>Routine</div>
              <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", gap: "8px" }}>
                <select
                  className="caseSelect"
                  value={activeRoborockRoute}
                  onChange={(event) => setSelectedRoborockRoute(event.target.value)}
                >
                  {roborockRoutes.map((route) => (
                    <option key={route} value={route}>
                      {route}
                    </option>
                  ))}
                </select>
                <button
                  className="button"
                  onClick={() => runRoborockCommand("run_route", activeRoborockRoute)}
                  disabled={!activeRoborockRoute}
                  style={{ background: "#0f172a" }}
                >
                  Run
                </button>
              </div>
            </>
          ) : (
            <div className="tiny" style={{ marginTop: "14px", lineHeight: 1.5 }}>
              Add named routines in CASE Core with roborock_route_entities, for example {"{\"kitchen\":\"script.roborock_clean_kitchen\"}"}.
            </div>
          )}

          {(roborockError || roborockStatus?.error || roborockStatus?.available === false) && (
            <div
              style={{
                marginTop: "16px",
                borderRadius: "14px",
                padding: "12px",
                background: roborockStatus?.available ? "#f8fafc" : "#fef2f2",
                color: roborockStatus?.available ? "#475569" : "#991b1b",
                fontSize: "13px",
                fontWeight: 700,
                lineHeight: 1.4,
              }}
            >
              {roborockError || roborockStatus?.error || roborockStatus?.message || "Roborock is unavailable."}
            </div>
          )}

          <button className="button" onClick={refreshRoborock} style={{ marginTop: "16px", width: "100%" }}>
            Refresh vacuum
          </button>
        </section>
        <section className="card">
          <div className="muted">IoT notes</div>
          <h2 style={{ margin: "6px 0 14px", fontSize: "22px" }}>Guardrails</h2>
          <div className="tiny" style={{ lineHeight: 1.5 }}>
            Coffee machine power switching is intentionally not enabled here yet. GaggiMate documents status
            and profile control over WebSocket; machine power should go through a documented relay path or
            smart plug. Roborock routines run only through named Home Assistant scripts, buttons or scenes.
          </div>
        </section>
      </div>
    </div>
  );
}

function NewsPage({ newsItems, newsSummary, newsError, newsLoading, refreshNews }) {
  const items = newsItems || [];

  return (
    <div>
      <section style={{ marginBottom: "18px" }}>
        <h1 style={{ margin: 0, fontSize: "32px" }}>News</h1>
        <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
          ABC headlines and local CASE summaries
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "minmax(0, 1.5fr) minmax(280px, 0.7fr)",
          gap: "16px",
          alignItems: "start",
        }}
        className="newsLayout"
      >
        <section className="card">
          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px", alignItems: "center" }}>
            <div>
              <div className="muted">Latest</div>
              <h2 style={{ margin: "6px 0 0", fontSize: "26px" }}>ABC News</h2>
            </div>
            <button className="button" onClick={refreshNews} disabled={newsLoading}>
              {newsLoading ? "Refreshing..." : "Refresh"}
            </button>
          </div>

          {newsError && (
            <div
              style={{
                marginTop: "16px",
                borderRadius: "14px",
                padding: "12px",
                background: "#fef2f2",
                color: "#991b1b",
                fontSize: "13px",
                fontWeight: 700,
              }}
            >
              {newsError}
            </div>
          )}

          <div style={{ display: "grid", gap: "12px", marginTop: "18px" }}>
            {items.length === 0 ? (
              <div className="tiny">No news loaded yet.</div>
            ) : (
              items.map((item) => (
                <article key={item.url} className="innerCard" style={{ padding: "14px" }}>
                  <div className="tiny" style={{ marginBottom: "6px" }}>
                    {item.feed_name} · {formatNewsTime(item.published_at)}
                  </div>
                  <a
                    href={item.url}
                    target="_blank"
                    rel="noreferrer"
                    style={{
                      color: "#111827",
                      textDecoration: "none",
                      fontWeight: 900,
                      fontSize: "18px",
                      lineHeight: 1.25,
                    }}
                  >
                    {item.title}
                  </a>
                  <p style={{ color: "#475569", lineHeight: 1.45, margin: "8px 0 0" }}>
                    {item.summary || item.description || "Summary unavailable until the local LLM is online."}
                  </p>
                  {item.summary_status !== "ok" && (
                    <div className="tiny" style={{ marginTop: "8px" }}>
                      Summary {item.summary_status || "pending"}
                    </div>
                  )}
                </article>
              ))
            )}
          </div>
        </section>

        <section className="card">
          <div className="muted">Summary status</div>
          <h2 style={{ margin: "6px 0 14px", fontSize: "22px" }}>
            {newsSummary?.summaries_available ? "Summaries ready" : "Feed text only"}
          </h2>
          <div style={{ display: "grid", gap: "10px" }}>
            <DeviceDetail label="Items" value={newsSummary?.item_count ?? items.length} />
            <DeviceDetail label="Summarised" value={newsSummary?.summary_count ?? 0} />
            <DeviceDetail label="LLM unavailable" value={newsSummary?.unavailable_count ?? 0} />
            <DeviceDetail label="Last refresh" value={formatNewsTime(newsSummary?.refreshed_at)} />
          </div>

          <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

          <div className="tiny" style={{ lineHeight: 1.5 }}>
            CASE only summarises RSS title and description text using the local desktop LLM. When that LLM is
            offline, headlines still load and summaries are marked unavailable.
          </div>
        </section>
      </div>
    </div>
  );
}

function MetricBox({ label, value }) {
  return (
    <div className="innerCard" style={{ textAlign: "left" }}>
      <div className="muted">{label}</div>
      <div style={{ fontSize: "22px", fontWeight: 900, marginTop: "4px" }}>{value}</div>
    </div>
  );
}

function DeviceDetail({ label, value }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", gap: "12px", fontSize: "14px" }}>
      <span className="muted">{label}</span>
      <strong style={{ textAlign: "right", minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" }}>
        {value}
      </strong>
    </div>
  );
}

function formatMetric(value, unit, decimals = 0) {
  if (value === null || value === undefined) return "--";
  return `${Number(value).toFixed(decimals)}${unit}`;
}

function compactRoborockState(status) {
  if (!status) return "--";

  const state = (status.state || "").replaceAll("_", " ");
  const activity = (status.activity || "").replaceAll("_", " ");
  const dock = (status.dock_state || "").replaceAll("_", " ");

  if (dock && ["docked", "charging", "returning", "probably docked"].includes(dock.toLowerCase())) {
    return dock;
  }

  if (activity && activity.toLowerCase() !== state.toLowerCase()) {
    return activity;
  }

  return state || "--";
}

function formatNewsTime(value) {
  if (!value) return "--";

  return new Date(value).toLocaleString([], {
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function SecurityPage({ securityStatus, assistantStatus, apiBase }) {
  const apiTokenOn = securityStatus?.api_token_configured === true;
  const corsRestricted = securityStatus && securityStatus.cors_all_origins === false;
  const llmOnline = assistantStatus?.available === true;
  const bridgeWarm = assistantStatus?.llm?.warmup?.ok === true;

  return (
    <div>
      <section style={{ marginBottom: "18px" }}>
        <h1 style={{ margin: 0, fontSize: "32px" }}>Security</h1>
        <div style={{ marginTop: "8px", fontSize: "15px", color: "#6b7280" }}>
          Local access, API protection and bridge exposure
        </div>
      </section>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
          gap: "16px",
        }}
      >
        <SecurityStatusCard
          title="API token"
          ok={apiTokenOn}
          good="Configured"
          bad="Not configured"
        />
        <SecurityStatusCard
          title="CORS"
          ok={corsRestricted}
          good="Restricted origins"
          bad="Allows all origins"
        />
        <SecurityStatusCard
          title="LLM bridge"
          ok={llmOnline}
          good="Reachable"
          bad="Unavailable"
        />
        <SecurityStatusCard
          title="LLM warmup"
          ok={bridgeWarm}
          good="Warm"
          bad={assistantStatus?.llm?.warmup?.message || "Not reported"}
        />
      </div>

      <section className="card" style={{ marginTop: "18px" }}>
        <div className="muted">API endpoint</div>
        <h2 style={{ margin: "6px 0 0", fontSize: "20px" }}>{apiBase}</h2>

        <div style={{ height: "1px", background: "#e5e7eb", margin: "18px 0" }} />

        <div className="muted" style={{ marginBottom: "10px" }}>
          Allowed web origins
        </div>
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
          {(securityStatus?.cors_origins || []).map((origin) => (
            <span key={origin} className="taskBadge">
              {origin}
            </span>
          ))}
        </div>
      </section>
    </div>
  );
}

function SecurityStatusCard({ title, ok, good, bad }) {
  return (
    <section className="card">
      <div className="muted">{title}</div>
      <h2
        style={{
          margin: "8px 0 0",
          fontSize: "22px",
          color: ok ? "#15803d" : "#b91c1c",
        }}
      >
        {ok ? good : bad}
      </h2>
    </section>
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
