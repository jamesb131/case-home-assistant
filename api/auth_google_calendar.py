import os

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]
DEFAULT_PORT = 8086
PORT = int(os.getenv("CALENDAR_AUTH_PORT", DEFAULT_PORT))
PORT_ATTEMPTS = int(os.getenv("CALENDAR_AUTH_PORT_ATTEMPTS", "5"))

flow = InstalledAppFlow.from_client_secrets_file(
    "app/google/credentials.json",
    SCOPES,
)

creds = None

for port in range(PORT, PORT + PORT_ATTEMPTS):
    try:
        print(f"Starting Google Calendar auth on http://localhost:{port}/")
        creds = flow.run_local_server(
            port=port,
            open_browser=True,
        )
        break
    except OSError as exc:
        if exc.errno != 48:
            raise

        print(f"Port {port} is busy, trying {port + 1}.")

if not creds:
    raise RuntimeError(
        "Could not start local auth server. "
        "Set CALENDAR_AUTH_PORT to a free port and try again."
    )

with open("app/google/token.json", "w") as token:
    token.write(creds.to_json())

print("Created app/google/token.json")
