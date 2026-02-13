#!/bin/bash

# Workbench Startup Script
# Checks prerequisites and starts both backend and frontend

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

# Log file for background processes
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"

# PIDs
BACKEND_PID=""
FRONTEND_PID=""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Shutting down services...${NC}"

    if [ -n "$BACKEND_PID" ]; then
        echo -e "${BLUE}Stopping backend (PID: $BACKEND_PID)${NC}"
        # Kill the process and all its children
        pkill -P $BACKEND_PID 2>/dev/null || true
        kill $BACKEND_PID 2>/dev/null || true
    fi

    if [ -n "$FRONTEND_PID" ]; then
        echo -e "${BLUE}Stopping frontend (PID: $FRONTEND_PID)${NC}"
        # Kill the process and all its children (yarn dev spawns Vite as child)
        pkill -P $FRONTEND_PID 2>/dev/null || true
        kill $FRONTEND_PID 2>/dev/null || true

        # Also kill any remaining Vite processes on port 5173
        lsof -ti:5173 | xargs kill -9 2>/dev/null || true
    fi

    echo -e "${GREEN}Services stopped${NC}"
    exit 0
}

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM EXIT

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error and exit
print_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a port is in use
port_in_use() {
    lsof -i:$1 >/dev/null 2>&1
}

print_header "Workbench Startup Check"

# ==========================================
# Check System Prerequisites
# ==========================================
print_header "Checking System Prerequisites"

# Check Go
if command_exists go; then
    GO_VERSION=$(go version | awk '{print $3}')
    print_success "Go installed: $GO_VERSION"
else
    print_error "Go is not installed. Please install Go 1.22 or higher."
fi

# Check Node.js
if command_exists node; then
    NODE_VERSION=$(node --version)
    print_success "Node.js installed: $NODE_VERSION"
else
    print_error "Node.js is not installed. Please install Node.js."
fi

# Check Yarn
if command_exists yarn; then
    YARN_VERSION=$(yarn --version)
    print_success "Yarn installed: $YARN_VERSION"
else
    print_error "Yarn is not installed. Please install Yarn."
fi

# Check Docker
if command_exists docker; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    print_success "Docker installed: $DOCKER_VERSION"

    # Check if Docker is running
    if docker info >/dev/null 2>&1; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running. Please start Docker."
    fi
else
    print_warning "Docker not found. Some services may not be available."
fi

# Check Task (optional but recommended)
if command_exists task; then
    print_success "Task (taskfile) is installed"
else
    print_warning "Task is not installed. Using fallback commands. Install from: https://taskfile.dev"
fi

# ==========================================
# Check Backend Prerequisites
# ==========================================
print_header "Checking Backend Prerequisites"

cd "$BACKEND_DIR"

# Check for .env file
if [ -f ".env.local" ]; then
    print_success "Backend .env.local file exists"
elif [ -f ".env" ]; then
    print_success "Backend .env file exists"
else
    print_warning "No .env file found in backend."
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}Creating .env.local from .env.example...${NC}"
        cp .env.example .env.local
        print_success "Created .env.local from .env.example"
        print_warning "Please review and configure .env.local before starting the backend"
    else
        print_error ".env.example not found in backend directory"
        print_error "Cannot create .env.local automatically"
    fi
fi

# Check if Go modules are up to date
if [ -f "go.mod" ]; then
    print_success "go.mod found"
    echo -e "${BLUE}Checking Go dependencies...${NC}"
    go mod download
    print_success "Go dependencies ready"
else
    print_error "go.mod not found in backend directory"
fi

# Check if PostgreSQL is running (via docker-compose)
if docker compose ps postgres 2>/dev/null | grep -q "Up\|running"; then
    print_success "PostgreSQL container is running"
else
    print_warning "PostgreSQL container not running"
    echo -e "${YELLOW}Starting PostgreSQL with docker-compose...${NC}"
    if docker compose up -d postgres; then
        echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"

        # Wait up to 30 seconds for PostgreSQL to be ready
        for i in {1..30}; do
            if docker compose exec -T postgres pg_isready -U workbench_owner >/dev/null 2>&1; then
                print_success "PostgreSQL started and ready"
                break
            fi
            if [ $i -eq 30 ]; then
                print_error "PostgreSQL failed to start within 30 seconds"
            fi
            sleep 1
        done
    else
        print_error "Failed to start PostgreSQL container"
    fi
fi

# ==========================================
# Check Frontend Prerequisites
# ==========================================
print_header "Checking Frontend Prerequisites"

cd "$FRONTEND_DIR"

# Check for .env file
if [ -f ".env" ]; then
    print_success "Frontend .env file exists"
else
    print_warning "No .env file found in frontend."
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}Creating .env from .env.example...${NC}"
        cp .env.example .env
        print_success "Created .env from .env.example"
        print_warning "Please review and configure .env before starting the frontend"
    else
        print_error ".env.example not found in frontend directory"
        print_error "Cannot create .env automatically"
    fi
fi

# Check if node_modules exists
if [ -d "node_modules" ]; then
    print_success "node_modules directory exists"
else
    print_warning "node_modules not found. Installing dependencies..."
    yarn install
    print_success "Frontend dependencies installed"
fi

# ==========================================
# Check Port Availability
# ==========================================
print_header "Checking Port Availability"

# Function to kill process on port
kill_port() {
    local port=$1
    local pid=$(lsof -ti:$port)
    if [ -n "$pid" ]; then
        kill -9 $pid 2>/dev/null || true
        sleep 1
    fi
}

# Backend default port: 8000
if port_in_use 8000; then
    print_warning "Port 8000 is already in use."
    echo -e "${YELLOW}Process using port 8000:${NC}"
    lsof -i:8000 | grep LISTEN || true
    read -p "Kill the process and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill_port 8000
        print_success "Port 8000 freed"
    else
        print_error "Cannot start backend while port 8000 is in use."
    fi
else
    print_success "Port 8000 is available (backend)"
fi

# Frontend default port: 5173
if port_in_use 5173; then
    print_warning "Port 5173 is already in use."
    echo -e "${YELLOW}Process using port 5173:${NC}"
    lsof -i:5173 | grep LISTEN || true
    read -p "Kill the process and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill_port 5173
        print_success "Port 5173 freed"
    else
        print_error "Cannot start frontend while port 5173 is in use."
    fi
else
    print_success "Port 5173 is available (frontend)"
fi

# ==========================================
# Start Services
# ==========================================
print_header "Starting Services"

# Start Backend
cd "$BACKEND_DIR"
echo -e "${BLUE}Starting backend...${NC}"
echo -e "${BLUE}Backend logs: $BACKEND_LOG${NC}"

if command_exists task; then
    task run > "$BACKEND_LOG" 2>&1 &
else
    go run cmd/server > "$BACKEND_LOG" 2>&1 &
fi

BACKEND_PID=$!
echo -e "${GREEN}Backend started (PID: $BACKEND_PID)${NC}"

# Wait a moment for backend to start
sleep 3

# Check if backend is still running
if ! kill -0 $BACKEND_PID 2>/dev/null; then
    print_error "Backend failed to start. Check logs at: $BACKEND_LOG"
fi

# Start Frontend
cd "$FRONTEND_DIR"
echo -e "${BLUE}Starting frontend...${NC}"
echo -e "${BLUE}Frontend logs: $FRONTEND_LOG${NC}"

yarn dev > "$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID)${NC}"

# Wait a moment for frontend to start
sleep 3

# Check if frontend is still running
if ! kill -0 $FRONTEND_PID 2>/dev/null; then
    print_error "Frontend failed to start. Check logs at: $FRONTEND_LOG"
fi

# ==========================================
# Summary
# ==========================================
print_header "Services Running"

echo -e "${GREEN}✓ Backend:  http://localhost:8000 (PID: $BACKEND_PID)${NC}"
echo -e "${GREEN}✓ Frontend: http://localhost:5173 (PID: $FRONTEND_PID)${NC}"
echo -e ""*
echo -e "${BLUE}Logs:${NC}"
echo -e "  Backend:  tail -f $BACKEND_LOG"
echo -e "  Frontend: tail -f $FRONTEND_LOG"
echo -e ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo -e ""

# Keep script running and tail logs
tail -f "$BACKEND_LOG" "$FRONTEND_LOG"
