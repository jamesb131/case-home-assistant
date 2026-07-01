export const API_BASE =
  import.meta.env.VITE_API_BASE_URL ||
  `${window.location.protocol}//${window.location.hostname}:8000`;

export const API_TOKEN = import.meta.env.VITE_CASE_API_TOKEN || "";

export function apiFetch(url, options = {}) {
  const headers = {
    ...(options.headers || {}),
  };

  if (API_TOKEN) {
    headers.Authorization = `Bearer ${API_TOKEN}`;
  }

  return fetch(url, {
    ...options,
    headers,
  });
}
