import argparse
import os
import shutil
from pathlib import Path

try:
    from google_auth_oauthlib.flow import InstalledAppFlow
except ModuleNotFoundError as exc:
    if exc.name != "google_auth_oauthlib":
        raise

    raise SystemExit(
        "Missing Google auth dependency. From the api directory, run:\n"
        "  python3 -m pip install -r requirements.txt\n"
        "Then retry auth_google_calendar.py."
    ) from exc

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]
DEFAULT_PORT = 8086


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Create a Google Calendar OAuth token for CASE and optionally "
            "copy the auth files to the Home Assistant import share."
        )
    )
    parser.add_argument(
        "--credentials",
        default=os.getenv("CALENDAR_AUTH_CREDENTIALS", "app/google/credentials.json"),
        help="Path to Google OAuth credentials.json.",
    )
    parser.add_argument(
        "--token-output",
        default=os.getenv("CALENDAR_AUTH_TOKEN_OUTPUT", "app/google/token.json"),
        help="Where to write the generated token.json.",
    )
    parser.add_argument(
        "--export-dir",
        default=os.getenv("CALENDAR_AUTH_EXPORT_DIR"),
        help=(
            "Optional directory to receive credentials.json and token.json, "
            "for example a mounted Home Assistant share/case/google folder."
        ),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.getenv("CALENDAR_AUTH_PORT", DEFAULT_PORT)),
        help="First localhost port to try for the OAuth callback.",
    )
    parser.add_argument(
        "--port-attempts",
        type=int,
        default=int(os.getenv("CALENDAR_AUTH_PORT_ATTEMPTS", "5")),
        help="Number of sequential localhost ports to try.",
    )
    return parser.parse_args()


def write_auth_file(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(content)
    temp_path.chmod(0o600)
    temp_path.replace(path)


def copy_auth_file(source, target):
    source = Path(source)
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    target.chmod(0o600)


def export_auth_files(credentials_path, token_path, export_dir):
    export_path = Path(export_dir)
    export_path.mkdir(parents=True, exist_ok=True)

    copy_auth_file(credentials_path, export_path / "credentials.json")
    copy_auth_file(token_path, export_path / "token.json")

    print(f"Exported Google auth files to {export_path}")


def main():
    args = parse_args()
    credentials_path = Path(args.credentials)
    token_path = Path(args.token_output)

    flow = InstalledAppFlow.from_client_secrets_file(
        str(credentials_path),
        SCOPES,
    )

    creds = None

    for port in range(args.port, args.port + args.port_attempts):
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

    write_auth_file(token_path, creds.to_json())
    print(f"Created {token_path}")

    if args.export_dir:
        export_auth_files(credentials_path, token_path, args.export_dir)


if __name__ == "__main__":
    main()
