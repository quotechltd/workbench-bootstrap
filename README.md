# Workbench Bootstrap Scripts

Internal development environment setup and startup scripts to easily run the Workbench backend and frontend projects together.

## Overview

This repository contains scripts and configuration files to streamline the setup and operation of the Workbench development environment. It brings together two separate repositories (Go backend and React/TypeScript frontend) into a single working directory for easy local development.

## Contents

- `setup-dev-environment.sh` - Complete macOS development environment setup
- `start.sh` - Unified startup script for both backend and frontend services
- `setup.env.example` - Template for environment configuration
- `CLAUDE.md` - Project documentation and guidelines
- `BOOTSTRAP_API_MIGRATION.md` - Bootstrap process documentation

## Prerequisites

- macOS (setup script is macOS-specific)
- Administrator access (for installing tools)

## Quick Start

### First-Time Setup

1. **Clone this bootstrap repository:**
   ```bash
   git clone <this-repo-url> workbench
   cd workbench
   ```

2. **Configure your environment:**
   ```bash
   cp setup.env.example setup.env
   # Edit setup.env with your details:
   # - GIT_USER_NAME (your name)
   # - GIT_USER_EMAIL (your email)
   ```

3. **Run the setup script:**
   ```bash
   ./setup-dev-environment.sh
   ```

   The setup script will automatically:
   - Clone the backend and frontend repositories
   - Install all required tools (Homebrew, Go, Node.js, Docker, etc.)
   - Configure Docker Desktop with host networking
   - Set up Git with commit signing
   - Authenticate with GitHub
   - Install frontend dependencies
   - Run the bootstrap process to initialize databases and seed data

   Final structure:
   ```
   workbench/
     ├── .git/              # This bootstrap repo
     ├── backend/           # Backend repository (auto-cloned)
     │   └── .git/
     ├── frontend/          # Frontend repository (auto-cloned)
     │   └── .git/
     ├── setup-dev-environment.sh
     ├── start.sh
     └── setup.env
   ```

   This will:
   - Install Homebrew (if needed)
   - Install development tools (Git, Go, Node.js, Docker, etc.)
   - Configure Docker Desktop with host networking
   - Set up Git with commit signing
   - Authenticate with GitHub
   - Install frontend dependencies
   - Run the bootstrap process to initialize databases and seed data

### Daily Development

**Start both services at once:**
```bash
./start.sh
```

This will:
- Check all prerequisites (Go, Node.js, Docker, etc.)
- Verify environment files exist
- Start PostgreSQL (via Docker Compose)
- Start backend server on `http://localhost:8000`
- Start frontend dev server on `http://localhost:5173`
- Tail logs from both services

Press `Ctrl+C` to stop all services gracefully.

**View logs separately:**
```bash
tail -f logs/backend.log
tail -f logs/frontend.log
```

### Manual Startup

If you prefer to start services individually:

**Backend:**
```bash
cd backend
task watch    # or: task run
```

**Frontend:**
```bash
cd frontend
yarn dev      # or: npm run dev
```

## Configuration

### setup.env

Personal configuration file for the setup script. Copy from `setup.env.example` and configure:

**Required:**
- `GIT_USER_NAME` - Your full name for Git commits
- `GIT_USER_EMAIL` - Your email for Git commits (should match GitHub)

**Optional:**
- `GITHUB_TOKEN` - Personal access token for automated GitHub auth
- `USE_PNPM` - Set to "true" to use pnpm instead of npm/yarn
- `BOOTSTRAP_MODE` - Set to "local" (default) or "uat"
- `UAT_DB_*` - UAT database connection details (only if BOOTSTRAP_MODE="uat")
- `UAT_ZITADEL_*` - UAT Zitadel connection details (only if BOOTSTRAP_MODE="uat")

Note: Repository URLs are hardcoded in the setup script.

### Backend Environment

Located at `backend/.env.local` or `backend/.env` (created from `backend/.env.example` during setup)

### Frontend Environment

Located at `frontend/.env` (created from `frontend/.env.example` during setup)

## What Gets Installed

The setup script installs these tools via Homebrew:

- **Git** - Version control
- **Go** - Backend runtime
- **Node.js** - Frontend runtime
- **go-task** - Task automation
- **gh** - GitHub CLI
- **PostgreSQL** - Database client tools
- **jq** - JSON processor
- **Docker Desktop** - Container platform

## Bootstrap Process

The bootstrap process (run automatically during setup) has two modes:

### Local Bootstrap (Default)

Creates fresh local data using the bootstrap script:
1. Initialize PostgreSQL database via Docker Compose
2. Run database migrations
3. Set up Zitadel (authentication provider)
4. Seed development data (organizations, users, roles)

Two seeding methods are available:
- **SQL-based** (default) - Direct database inserts, fast
- **API-based** (experimental) - Uses Workbench APIs for validation

See `BOOTSTRAP_API_MIGRATION.md` for details.

### UAT Clone Mode

Clones data from the UAT environment to your local environment:

1. **Configure UAT access** in `setup.env`:
   ```bash
   BOOTSTRAP_MODE="uat"

   # UAT Database
   UAT_DB_HOST="uat-postgres.example.com"
   UAT_DB_PORT="5432"
   UAT_DB_NAME="workbench"
   UAT_DB_USER="workbench_owner"
   UAT_DB_PASSWORD="your-password"

   # UAT Zitadel
   UAT_ZITADEL_URL="https://uat-zitadel.example.com"
   UAT_ZITADEL_ADMIN_USER="admin@example.com"
   UAT_ZITADEL_ADMIN_PASSWORD="your-password"
   ```

2. **Configure Zitadel service account** (optional but recommended):
   ```bash
   # Service account provides automated data export
   UAT_ZITADEL_SERVICE_USER="service-account@org.zitadel.cloud"
   UAT_ZITADEL_SERVICE_KEY="your-service-account-key"
   ```

3. **Run setup** - The script will:
   - Dump the UAT PostgreSQL database
   - Restore it to your local PostgreSQL container
   - Export Zitadel data using the service account (if configured)
   - Provide the exported data and instructions for import

**Zitadel Data Export:**
- With service account: Automatically exports organizations, users, and projects to JSON files
- Without service account: Provides manual export/import instructions
- Import to local Zitadel is currently manual (automatic import coming soon)

## Ports Used

- `5173` - Frontend development server
- `8000` - Backend API server
- `5432` - PostgreSQL database
- `9010` - Zitadel authentication server (if running)

## Troubleshooting

### Port Already in Use

If ports 8000 or 5173 are in use:
```bash
# Find what's using the port
lsof -i :8000
lsof -i :5173

# Kill the process
kill -9 <PID>
```

### Docker Not Running

```bash
# Start Docker Desktop
open -a Docker

# Wait for it to be ready
docker info
```

### Environment Files Missing

The `start.sh` script will automatically create `.env` files from `.env.example` if they don't exist.

### Frontend Dependencies Missing

```bash
cd frontend
yarn install
```

### Backend Dependencies Missing

```bash
cd backend
go mod download
```

## Repository Structure

This is **not a monorepo**. It's a bootstrap repository that orchestrates two separate git repositories:

- **backend/** - Separate git repository for Go backend
- **frontend/** - Separate git repository for React/TypeScript frontend
- **Root directory** - This bootstrap repository with setup/start scripts

Each repository maintains its own git history and can be developed independently. The bootstrap scripts simply make it easy to run them together.

## Working with Multiple Repositories

**Check status across all repos:**
```bash
# Backend
cd backend && git status && cd ..

# Frontend
cd frontend && git status && cd ..

# Bootstrap
git status
```

**Pull latest changes:**
```bash
cd backend && git pull && cd ..
cd frontend && git pull && cd ..
git pull
```

**Each repository has its own branches, commits, and workflow.**

## Links

- Backend repository: (add your backend repo URL)
- Frontend repository: (add your frontend repo URL)

## Additional Documentation

- `CLAUDE.md` - Comprehensive development guidelines
- `BOOTSTRAP_API_MIGRATION.md` - Bootstrap seeding methods
- `backend/README.md` - Backend-specific documentation
- `backend/CLAUDE.md` - Backend development guidelines
- `frontend/README.md` - Frontend-specific documentation
- `frontend/CLAUDE.md` - Frontend development guidelines

## Notes

- These scripts are designed for local development only
- The setup script is macOS-specific (uses Homebrew, assumes Zsh)
- Docker Desktop's host networking feature is required and configured automatically
- Git commit signing with SSH keys is configured automatically
- Each repository (backend, frontend, bootstrap) maintains its own git history
