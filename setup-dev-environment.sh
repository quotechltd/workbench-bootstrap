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

# Function to clone UAT database
clone_uat_database() {
    info "Cloning UAT database to local environment..."

    # Validate UAT configuration
    local required_vars=(
        "UAT_DB_HOST"
        "UAT_DB_PORT"
        "UAT_DB_NAME"
        "UAT_DB_USER"
        "UAT_DB_PASSWORD"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required UAT variable $var is not set in $CONFIG_FILE"
            error "Please configure UAT database settings to use BOOTSTRAP_MODE=uat"
            return 1
        fi
    done

    # Ensure PostgreSQL container is running
    cd "$BACKEND_DIR"
    if ! docker compose ps postgres 2>/dev/null | grep -q "Up\|running"; then
        info "Starting PostgreSQL container..."
        docker compose up -d postgres
        sleep 5
    fi

    # Dump UAT database
    info "Dumping UAT database..."
    local dump_file="/tmp/uat_dump_$(date +%s).sql"

    if PGPASSWORD="$UAT_DB_PASSWORD" pg_dump \
        -h "$UAT_DB_HOST" \
        -p "$UAT_DB_PORT" \
        -U "$UAT_DB_USER" \
        -d "$UAT_DB_NAME" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        -f "$dump_file"; then
        success "UAT database dumped to $dump_file"
    else
        error "Failed to dump UAT database"
        return 1
    fi

    # Drop and recreate local database
    info "Recreating local database..."
    docker compose exec -T postgres psql -U workbench_owner -d postgres -c "DROP DATABASE IF EXISTS workbench;" 2>/dev/null || true
    docker compose exec -T postgres psql -U workbench_owner -d postgres -c "CREATE DATABASE workbench;" 2>/dev/null || true

    # Restore to local database
    info "Restoring to local database..."
    if docker compose exec -T postgres psql -U workbench_owner -d workbench < "$dump_file"; then
        success "UAT database restored to local environment"
        rm "$dump_file"
    else
        error "Failed to restore database"
        warn "Dump file saved at: $dump_file"
        return 1
    fi

    cd "$PROJECT_ROOT"
}

# Function to get Zitadel token (supports both PAT and service account)
zitadel_get_token() {
    local zitadel_url=$1
    local service_user=$2
    local service_key=$3

    # If service_key looks like a PAT (long alphanumeric), use it directly
    if [[ ${#service_key} -gt 50 ]]; then
        info "Using Personal Access Token for Zitadel authentication..."
        echo "$service_key"
        return 0
    fi

    # Otherwise, try OAuth client credentials flow
    info "Authenticating with Zitadel service account via OAuth..."

    local token_response=$(curl -s -X POST "${zitadel_url}/oauth/v2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "scope=openid profile email urn:zitadel:iam:org:project:id:zitadel:aud" \
        -u "${service_user}:${service_key}")

    local access_token=$(echo "$token_response" | jq -r '.access_token')

    if [[ "$access_token" == "null" ]] || [[ -z "$access_token" ]]; then
        error "Failed to authenticate with Zitadel"
        error "Response: $token_response"
        return 1
    fi

    echo "$access_token"
}

# Function to export Zitadel data
export_zitadel_data() {
    local zitadel_url=$1
    local access_token=$2
    local output_dir=$3

    info "Exporting Zitadel data from ${zitadel_url}..."

    mkdir -p "$output_dir"

    # Export organization (using /me endpoint)
    info "Exporting organization..."
    curl -s "${zitadel_url}/management/v1/orgs/me" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" > "${output_dir}/organization.json"

    # Export users
    info "Exporting users..."
    curl -s -X POST "${zitadel_url}/management/v1/users/_search" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        -d '{"queries":[]}' > "${output_dir}/users.json"

    # Export projects
    info "Exporting projects..."
    curl -s -X POST "${zitadel_url}/management/v1/projects/_search" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        -d '{"queries":[]}' > "${output_dir}/projects.json"

    success "Zitadel data exported to ${output_dir}"
}

# Function to create test user in local Zitadel
create_local_test_user() {
    local local_zitadel_url="http://localhost:9010"
    local test_email="${1:-test.user@local.dev}"
    local test_password="${2:-TestPassword123!}"
    local test_firstname="${3:-Test}"
    local test_lastname="${4:-User}"

    info "Creating test user in local Zitadel..."

    # Check if local Zitadel is running
    if ! curl -s "${local_zitadel_url}/ui/console" -o /dev/null 2>&1; then
        error "Local Zitadel is not running at ${local_zitadel_url}"
        error "Please start it first: cd backend && docker compose up -d zitadel"
        return 1
    fi

    # Check if we have local admin credentials
    if [[ -z "${LOCAL_ZITADEL_ADMIN_TOKEN:-}" ]]; then
        warn "LOCAL_ZITADEL_ADMIN_TOKEN not set in setup.env"
        echo ""
        info "To automatically create test users, you need:"
        echo "  1. Login to local Zitadel: ${local_zitadel_url}/ui/console"
        echo "  2. Use bootstrap admin credentials"
        echo "  3. Create a service account or generate a PAT"
        echo "  4. Add LOCAL_ZITADEL_ADMIN_TOKEN to setup.env"
        echo ""
        info "Manual user creation:"
        echo "  1. Access: ${local_zitadel_url}/ui/console"
        echo "  2. Go to Users > New"
        echo "  3. Create user with:"
        echo "     Email: ${test_email}"
        echo "     Password: ${test_password}"
        echo "     First Name: ${test_firstname}"
        echo "     Last Name: ${test_lastname}"
        echo "  4. Assign roles/permissions as needed"
        echo ""
        return 1
    fi

    # Create user via API
    info "Creating user: ${test_email}"
    local response=$(curl -s -X POST "${local_zitadel_url}/management/v1/users/human/_import" \
        -H "Authorization: Bearer ${LOCAL_ZITADEL_ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"userName\": \"${test_email}\",
            \"profile\": {
                \"firstName\": \"${test_firstname}\",
                \"lastName\": \"${test_lastname}\"
            },
            \"email\": {
                \"email\": \"${test_email}\",
                \"isEmailVerified\": true
            },
            \"password\": \"${test_password}\",
            \"passwordChangeRequired\": false
        }")

    if echo "$response" | jq -e '.userId' >/dev/null 2>&1; then
        local user_id=$(echo "$response" | jq -r '.userId')
        success "Test user created successfully!"
        echo "  Email: ${test_email}"
        echo "  Password: ${test_password}"
        echo "  User ID: ${user_id}"
        echo ""
        info "User will be auto-provisioned to database on first login"
        return 0
    else
        error "Failed to create test user"
        echo "Response: $response"
        return 1
    fi
}

# Function to provide Zitadel import guidance and create test user
import_zitadel_data() {
    local export_dir=$1

    echo ""
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "  Zitadel User Setup"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local user_count=$(jq -r '.result | length' "${export_dir}/users.json" 2>/dev/null || echo "0")
    local human_count=$(jq -r '[.result[] | select(.human)] | length' "${export_dir}/users.json" 2>/dev/null || echo "0")

    info "Exported ${user_count} total users (${human_count} human users) from UAT"
    echo ""

    info "The workbench application handles user synchronization automatically:"
    echo "  1. ✅ UAT database cloned → Contains all user data and permissions"
    echo "  2. 👤 User logs into local workbench"
    echo "  3. 🔄 Workbench provisions user from Zitadel to database"
    echo "  4. ✅ Existing database permissions are linked to user"
    echo ""

    # Offer to create test user
    echo ""
    info "Creating test user for local development..."
    echo ""
    read -p "Create a test user in local Zitadel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Use configurable values or defaults
        local test_email="${TEST_USER_EMAIL:-test.user@local.dev}"
        local test_password="${TEST_USER_PASSWORD:-TestPassword123!}"
        local test_firstname="${TEST_USER_FIRSTNAME:-Test}"
        local test_lastname="${TEST_USER_LASTNAME:-User}"

        create_local_test_user "$test_email" "$test_password" "$test_firstname" "$test_lastname"
    else
        info "Skipping test user creation"
        echo ""
        warn "You can create users manually in Zitadel:"
        echo "  Access: http://localhost:9010/ui/console"
        echo ""
    fi

    echo ""
    info "User data reference exported to:"
    echo "  • Organization: ${export_dir}/organization.json"
    echo "  • Users: ${export_dir}/users.json (${human_count} human users)"
    echo "  • Projects: ${export_dir}/projects.json"
    echo ""
}

# Function to clone UAT Zitadel
clone_uat_zitadel() {
    info "Cloning UAT Zitadel to local environment..."

    # Check if service account credentials are provided
    if [[ -n "${UAT_ZITADEL_SERVICE_USER:-}" ]] && [[ -n "${UAT_ZITADEL_SERVICE_KEY:-}" ]]; then
        info "Using service account authentication"

        # Validate required variables
        if [[ -z "${UAT_ZITADEL_URL:-}" ]]; then
            error "UAT_ZITADEL_URL is not set in $CONFIG_FILE"
            return 1
        fi

        # Create temporary directory for export
        local export_dir="/tmp/zitadel_export_$(date +%s)"
        mkdir -p "$export_dir"

        # Get access token for UAT
        local uat_token=$(zitadel_get_token "$UAT_ZITADEL_URL" "$UAT_ZITADEL_SERVICE_USER" "$UAT_ZITADEL_SERVICE_KEY")
        if [[ $? -ne 0 ]]; then
            error "Failed to authenticate with UAT Zitadel"
            return 1
        fi

        # Export data from UAT
        export_zitadel_data "$UAT_ZITADEL_URL" "$uat_token" "$export_dir"

        # Show exported data summary
        success "Zitadel data exported successfully!"
        echo ""
        info "Exported data:"
        echo "  Organization: $(jq -r '.org.name' ${export_dir}/organization.json 2>/dev/null || echo 'N/A')"
        echo "  Users: $(jq -r '.result | length' ${export_dir}/users.json 2>/dev/null || echo 'N/A')"
        echo "  Projects: $(jq -r '.result | length' ${export_dir}/projects.json 2>/dev/null || echo 'N/A')"
        echo ""

        # Attempt to import to local Zitadel
        import_zitadel_data "$export_dir"

    else
        # Fallback to manual instructions
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "  Manual Zitadel Cloning"
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        warn "No service account credentials found. Manual export/import required."
        echo ""
        echo "1. Export from UAT Zitadel:"
        echo "   - Access: ${UAT_ZITADEL_URL:-https://uat-zitadel.example.com}"
        echo "   - Login with admin credentials"
        echo "   - Navigate to Organization > Export"
        echo "   - Download the export file"
        echo ""
        echo "2. Import to local Zitadel:"
        echo "   - Access: http://localhost:9010"
        echo "   - Login with local admin credentials"
        echo "   - Navigate to Organization > Import"
        echo "   - Upload the export file"
        echo ""
        warn "Tip: Configure UAT_ZITADEL_SERVICE_USER and UAT_ZITADEL_SERVICE_KEY"
        warn "in setup.env for automated data export."
        echo ""
    fi
}

# Function to run bootstrap
run_bootstrap() {
    if [[ ! -d "$BACKEND_DIR" ]]; then
        error "Backend directory not found: $BACKEND_DIR"
        return 1
    fi

    # Check bootstrap mode
    local bootstrap_mode="${BOOTSTRAP_MODE:-local}"

    if [[ "$bootstrap_mode" == "uat" ]]; then
        info "Bootstrap mode: UAT (cloning from UAT environment)"
        echo ""
        warn "This will replace your local database and Zitadel with UAT data"
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Bootstrap cancelled"
            return 0
        fi

        # Clone UAT database
        clone_uat_database

        # Clone UAT Zitadel (manual process)
        clone_uat_zitadel

        success "UAT data cloning complete!"
        warn "Remember to manually export/import Zitadel data as described above"

    else
        info "Bootstrap mode: Local (creating fresh local data)"
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
    fi

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
