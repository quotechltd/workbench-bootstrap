#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory (workbench root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

# Repository URLs (hardcoded)
BACKEND_REPO_URL="git@github.com:quotechltd/workbench.git"
FRONTEND_REPO_URL="git@github.com:quotechltd/frontend.git"

# Default config file location
CONFIG_FILE="${SCRIPT_DIR}/setup.env"

# Function to print colored messages
info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        info "Please copy setup.env.example to setup.env and fill in your details"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    # Validate required variables
    local required_vars=(
        "GIT_USER_NAME"
        "GIT_USER_EMAIL"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set in $CONFIG_FILE"
            exit 1
        fi
    done
}

# Function to check macOS version
check_macos_version() {
    info "Checking macOS version..."

    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script is designed for macOS only"
        exit 1
    fi

    local macos_version
    macos_version=$(sw_vers -productVersion)
    success "Running macOS $macos_version"
}

# Function to check available disk space
check_disk_space() {
    info "Checking available disk space..."

    local available_gb
    available_gb=$(df -g / | awk 'NR==2 {print $4}')

    if [[ $available_gb -lt 20 ]]; then
        warn "Low disk space: ${available_gb}GB available. Recommended: 20GB+"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        success "${available_gb}GB available disk space"
    fi
}

# Function to install Homebrew
install_homebrew() {
    if command_exists brew; then
        success "Homebrew already installed"
        return 0
    fi

    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi

    success "Homebrew installed"
}

# Function to install core development tools
install_dev_tools() {
    info "Installing development tools via Homebrew..."

    local tools=(
        "git"
        "go"
        "node"
        "gh"           # GitHub CLI
        "go-task"      # Task runner
        "postgresql"   # For psql client
        "jq"           # JSON processor for Docker config
    )

    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            success "$tool already installed"
        else
            info "Installing $tool..."
            brew install "$tool"
            success "$tool installed"
        fi
    done
}

# Function to install Docker Desktop
install_docker_desktop() {
    if command_exists docker; then
        success "Docker already installed"
        return 0
    fi

    info "Installing Docker Desktop..."

    if brew list --cask docker &>/dev/null; then
        success "Docker Desktop already installed via Homebrew"
    else
        brew install --cask docker
        success "Docker Desktop installed"
    fi

    # Start Docker Desktop if not running
    if ! docker info >/dev/null 2>&1; then
        info "Starting Docker Desktop for the first time..."
        open -a Docker

        echo ""
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "  Docker Desktop First-Time Setup"
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        warn "Docker Desktop may show some prompts. Please complete them:"
        echo ""
        echo "  1. ${YELLOW}Service Agreement${NC} - Click 'Accept'"
        echo "  2. ${YELLOW}Privileged Helper Installation${NC} - Enter your Mac password"
        echo "  3. ${YELLOW}Welcome Screen${NC} - Click 'Skip' or 'Continue' (no account needed)"
        echo ""
        warn "The script will wait up to 2 minutes for Docker to be ready..."
        echo ""

        sleep 5
    fi
}

# Function to enable Docker host networking
enable_docker_host_networking() {
    local settings_file="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

    if [[ ! -f "$settings_file" ]]; then
        warn "Docker settings file not found. Please enable host networking manually in Docker Desktop."
        return 0
    fi

    info "Configuring Docker host networking..."

    # Check if host networking is already enabled
    if grep -q '"HostNetworkingEnabled": true' "$settings_file"; then
        success "Host networking already enabled"
        return 0
    fi

    # Docker needs to be stopped to modify settings
    if docker info >/dev/null 2>&1; then
        info "Stopping Docker to update settings..."
        osascript -e 'quit app "Docker"' 2>/dev/null || true
        sleep 3
    fi

    # Backup the settings file
    cp "$settings_file" "$settings_file.backup"

    # Enable host networking using jq if available, otherwise use sed
    if command_exists jq; then
        jq '.HostNetworkingEnabled = true' "$settings_file.backup" > "$settings_file"
        success "Host networking enabled via jq"
    else
        # Use sed as fallback (less reliable but works)
        if grep -q '"HostNetworkingEnabled"' "$settings_file"; then
            sed -i '' 's/"HostNetworkingEnabled": false/"HostNetworkingEnabled": true/' "$settings_file"
        else
            # Add the setting if it doesn't exist (insert before the last closing brace)
            sed -i '' '$d' "$settings_file"
            echo '  "HostNetworkingEnabled": true' >> "$settings_file"
            echo '}' >> "$settings_file"
        fi
        success "Host networking enabled"
    fi

    # Restart Docker
    info "Starting Docker Desktop..."
    open -a Docker
    sleep 5
}

# Function to verify Docker is running
verify_docker_running() {
    info "Verifying Docker is running..."

    local max_attempts=60  # 2 minutes (60 * 2 seconds)
    local attempt=0

    while ! docker info >/dev/null 2>&1; do
        attempt=$((attempt + 1))

        # Print progress every 10 seconds
        if [[ $((attempt % 5)) -eq 0 ]]; then
            info "Still waiting for Docker... ($((attempt * 2)) seconds elapsed)"
        fi

        if [[ $attempt -ge $max_attempts ]]; then
            echo ""
            error "Docker failed to start after 2 minutes."
            echo ""
            warn "Please check:"
            warn "  1. Did you accept the Docker service agreement?"
            warn "  2. Did you enter your password for the privileged helper?"
            warn "  3. Is Docker Desktop showing any error messages?"
            echo ""
            warn "Try opening Docker Desktop manually and resolving any issues,"
            warn "then run this script again."
            echo ""
            exit 1
        fi
        sleep 2
    done

    success "Docker is running and ready!"
}

# Function to configure Git
configure_git() {
    info "Configuring Git..."

    local current_name
    local current_email
    current_name=$(git config --global user.name || echo "")
    current_email=$(git config --global user.email || echo "")

    if [[ -n "$current_name" ]] && [[ -n "$current_email" ]]; then
        success "Git already configured: $current_name <$current_email>"
    else
        git config --global user.name "$GIT_USER_NAME"
        git config --global user.email "$GIT_USER_EMAIL"
        success "Git configured: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    fi
}

# Function to setup SSH key for commit signing
setup_commit_signing() {
    info "Setting up Git commit signing..."

    # Check if signing is already configured
    local signing_key
    signing_key=$(git config --global user.signingkey || echo "")

    if [[ -n "$signing_key" ]]; then
        success "Commit signing already configured"
        return 0
    fi

    # Generate SSH key if it doesn't exist
    local ssh_key="$HOME/.ssh/id_ed25519"
    if [[ ! -f "$ssh_key" ]]; then
        info "Generating SSH key for commit signing..."
        ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$ssh_key" -N ""

        # Start ssh-agent and add key
        eval "$(ssh-agent -s)" > /dev/null 2>&1
        ssh-add "$ssh_key" 2>/dev/null

        success "SSH key generated"
    else
        success "SSH key already exists"
    fi

    # Configure Git to use SSH signing
    git config --global gpg.format ssh
    git config --global user.signingkey "$ssh_key.pub"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    success "Git commit signing configured with SSH"

    # Add SSH key to ssh-agent config for persistence
    if [[ ! -f "$HOME/.ssh/config" ]] || ! grep -q "AddKeysToAgent yes" "$HOME/.ssh/config"; then
        info "Configuring SSH to persist keys..."
        mkdir -p "$HOME/.ssh"
        cat >> "$HOME/.ssh/config" <<EOF

# Auto-add SSH keys to agent
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
        success "SSH config updated"
    fi
}

# Function to authenticate with GitHub
authenticate_github() {
    if gh auth status &>/dev/null; then
        success "Already authenticated with GitHub"
    else
        info "Authenticating with GitHub..."

        # Use token if provided, otherwise interactive login
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            info "Using GitHub Personal Access Token from setup.env"
            echo "$GITHUB_TOKEN" | gh auth login --with-token
            success "GitHub authentication complete (via token)"
        else
            info "No GITHUB_TOKEN provided, using interactive authentication"
            info "This will open a browser window for GitHub authentication"
            gh auth login
            success "GitHub authentication complete"
        fi
    fi

    # Upload SSH signing key to GitHub
    upload_ssh_signing_key_to_github
}

# Function to upload SSH signing key to GitHub
upload_ssh_signing_key_to_github() {
    local ssh_key="$HOME/.ssh/id_ed25519.pub"

    if [[ ! -f "$ssh_key" ]]; then
        return 0
    fi

    info "Uploading SSH signing key to GitHub..."

    # Check if key already exists on GitHub
    if gh ssh-key list | grep -q "$(cat "$ssh_key" | awk '{print $2}')"; then
        success "SSH signing key already uploaded to GitHub"
        return 0
    fi

    # Upload the key as a signing key
    if gh ssh-key add "$ssh_key" --type signing --title "$(hostname) - Commit Signing Key"; then
        success "SSH signing key uploaded to GitHub"
    else
        warn "Failed to upload SSH signing key automatically"
        warn "Please add it manually at: https://github.com/settings/keys"
        info "Your public key:"
        cat "$ssh_key"
    fi

    # Upload SSH signing key to GitHub
    upload_ssh_signing_key_to_github
}

# Function to upload SSH signing key to GitHub
upload_ssh_signing_key_to_github() {
    local ssh_key="$HOME/.ssh/id_ed25519.pub"

    if [[ ! -f "$ssh_key" ]]; then
        return 0
    fi

    info "Uploading SSH signing key to GitHub..."

    # Check if key already exists on GitHub
    if gh ssh-key list | grep -q "$(cat "$ssh_key" | awk '{print $2}')"; then
        success "SSH signing key already uploaded to GitHub"
        return 0
    fi

    # Upload the key as a signing key
    if gh ssh-key add "$ssh_key" --type signing --title "$(hostname) - Commit Signing Key"; then
        success "SSH signing key uploaded to GitHub"
    else
        warn "Failed to upload SSH signing key automatically"
        warn "Please add it manually at: https://github.com/settings/keys"
        info "Your public key:"
        cat "$ssh_key"
    fi
}

# Function to clone repositories
clone_repositories() {
    info "Setting up project repositories..."

    # Clone backend if it doesn't exist
    if [[ ! -d "$BACKEND_DIR" ]]; then
        info "Cloning backend repository..."
        git clone "$BACKEND_REPO_URL" "$BACKEND_DIR"
        success "Backend repository cloned"
    else
        success "Backend directory already exists"
    fi

    # Clone frontend if it doesn't exist
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        info "Cloning frontend repository..."
        git clone "$FRONTEND_REPO_URL" "$FRONTEND_DIR"
        success "Frontend repository cloned"
    else
        success "Frontend directory already exists"
    fi
}

# Function to clone repositories
clone_repositories() {
    info "Setting up project repositories..."

    # Clone backend if it doesn't exist
    if [[ ! -d "$BACKEND_DIR" ]]; then
        info "Cloning backend repository..."
        git clone "$BACKEND_REPO_URL" "$BACKEND_DIR"
        success "Backend repository cloned"
    else
        success "Backend directory already exists"
    fi

    # Clone frontend if it doesn't exist
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        info "Cloning frontend repository..."
        git clone "$FRONTEND_REPO_URL" "$FRONTEND_DIR"
        success "Frontend repository cloned"
    else
        success "Frontend directory already exists"
    fi
}

# Function to verify repositories
verify_repositories() {
    info "Verifying project structure..."

    # Check if we're in the workbench monorepo
    if [[ ! -d "$BACKEND_DIR" ]] || [[ ! -d "$FRONTEND_DIR" ]]; then
        error "Repository directories not found"
        error "Expected structure:"
        error "  - $BACKEND_DIR"
        error "  - $FRONTEND_DIR"
        exit 1
    fi

    success "Project structure verified"
}

# Function to install frontend dependencies
install_frontend_deps() {
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        error "Frontend directory not found: $FRONTEND_DIR"
        return 1
    fi

    info "Installing frontend dependencies..."
    cd "$FRONTEND_DIR"

    # Check if node_modules exists and is not empty
    if [[ -d "node_modules" ]] && [[ -n "$(ls -A node_modules 2>/dev/null)" ]]; then
        success "Frontend dependencies already installed"
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Use yarn if yarn.lock exists, otherwise npm
    if [[ -f "yarn.lock" ]]; then
        if ! command_exists yarn; then
            info "Installing yarn..."
            npm install -g yarn
        fi
        yarn install
    elif [[ "${USE_PNPM:-false}" == "true" ]]; then
        if ! command_exists pnpm; then
            info "Installing pnpm..."
            npm install -g pnpm
        fi
        pnpm install
    else
        npm install
    fi

    success "Frontend dependencies installed"
    cd "$PROJECT_ROOT"
}

# Function to configure environment variables
configure_environment() {
    info "Configuring environment variables..."

    local shell_rc="$HOME/.zshrc"

    # Add FRONTEND_ENV_PATH to shell config
    local frontend_env_path="$FRONTEND_DIR/.env"
    local env_var_line="export FRONTEND_ENV_PATH=\"$frontend_env_path\""

    if grep -q "FRONTEND_ENV_PATH" "$shell_rc" 2>/dev/null; then
        success "FRONTEND_ENV_PATH already configured in $shell_rc"
    else
        echo "" >> "$shell_rc"
        echo "# Workbench development environment" >> "$shell_rc"
        echo "$env_var_line" >> "$shell_rc"
        success "FRONTEND_ENV_PATH added to $shell_rc"
    fi

    # Export for current session
    export FRONTEND_ENV_PATH="$frontend_env_path"
}

# Function to run bootstrap
run_bootstrap() {
    if [[ ! -d "$BACKEND_DIR" ]]; then
        error "Backend directory not found: $BACKEND_DIR"
        return 1
    fi

    info "Running bootstrap process..."
    warn "This will set up the local development environment with Docker containers"
    warn "It will delete any existing local data and start fresh"

    cd "$BACKEND_DIR"

    # Check if Task is available
    if ! command_exists task; then
        error "Task command not found. Please ensure go-task is installed."
        return 1
    fi

    # Run bootstrap (will prompt for confirmation)
    task bootstrap

    success "Bootstrap complete!"
    cd "$PROJECT_ROOT"
}

# Function to print next steps
print_next_steps() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  🎉 Development environment setup complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. Start the backend:"
    echo -e "   ${YELLOW}cd backend${NC}"
    echo -e "   ${YELLOW}task watch${NC}    # or: task gow"
    echo ""
    echo "2. Start the frontend (in a new terminal):"
    echo -e "   ${YELLOW}cd frontend${NC}"
    echo -e "   ${YELLOW}yarn dev${NC}      # or: npm run dev"
    echo ""
    echo "3. Access the applications:"
    echo -e "   • Frontend:  ${BLUE}http://localhost:5174${NC}"
    echo -e "   • Backend:   ${BLUE}http://localhost:8080${NC}"
    echo -e "   • Zitadel:   ${BLUE}http://localhost:9010${NC}"
    echo ""
    echo "4. Login credentials (printed by bootstrap above)"
    echo ""
    echo -e "${YELLOW}Important:${NC} Open a new terminal or run ${YELLOW}source ~/.zshrc${NC} to load environment variables"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Workbench Development Environment Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"

    # Load configuration
    load_config

    # System checks
    check_macos_version
    check_disk_space

    # Install prerequisites
    install_homebrew
    install_dev_tools
    install_docker_desktop
    enable_docker_host_networking
    verify_docker_running

    # Configure tools
    configure_git
    setup_commit_signing
    authenticate_github

    # Setup projects
    clone_repositories
    verify_repositories
    install_frontend_deps
    configure_environment

    # Bootstrap the environment
    run_bootstrap

    # Print next steps
    print_next_steps
}

# Run main function
main "$@"
