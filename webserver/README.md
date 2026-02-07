# Temp Webserver

This temporary webserver was a quick creation of claude's:

Prompt:
```bash
"Please create a new simple go webserver with a frontend. The frontend should allow the client to p
ress a button which kicks off the 'launchers/new_game.sh' process. We must be able to launch the webserver in a way where we pass in the necessary environment variables. (TF_VAR_github_org, TF_VAR_github_pat, TF_VAR_source_owner, ARM_SUBSCRIPTION_ID, TF_VAR_subscription_id)"
```

Response:

I've created a Go webserver with a frontend. Here's the structure:

```
webserver/
├── go.mod
├── main.go
└── static/
    └── index.html
```

## Features

1. **Frontend** (`static/index.html`):
   - Displays status of all required environment variables
   - Input field for optional game prefix
   - Launch button (disabled if env vars are missing)
   - Real-time output display with status indicators

2. **Backend** (`main.go`):
   - Serves the frontend at `/`
   - `GET /api/env-status` - Returns status of required environment variables
   - `POST /api/launch` - Executes `launchers/new_game.sh` with optional game prefix
   - Auto-confirms the "Do you want to continue?" prompt
   - Prevents concurrent launches

## Usage

Build and run with the required environment variables:

```bash
# Build
cd webserver
go build -o game-launcher

# Run with environment variables
TF_VAR_github_org="your-org" \
TF_VAR_github_pat="your-pat" \
TF_VAR_source_owner="your-owner" \
ARM_SUBSCRIPTION_ID="your-subscription-id" \
TF_VAR_subscription_id="your-subscription-id" \
./game-launcher
```

Or export them first:
```bash
export TF_VAR_github_org="your-org"
export TF_VAR_github_pat="your-pat"
export TF_VAR_source_owner="your-owner"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export TF_VAR_subscription_id="your-subscription-id"
./game-launcher
```

The server runs on port `8080` by default (configurable via `PORT` env var). Open `http://localhost:8080` in your browser.
