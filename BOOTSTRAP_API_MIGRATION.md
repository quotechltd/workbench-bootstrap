# Bootstrap Data: SQL to API Migration

## Summary

The bootstrap process now supports **two methods** for seeding development data:

1. **Direct SQL** (default) - Fast, no dependencies, original implementation
2. **API-based** (experimental) - Uses Workbench APIs, validates production code paths

## Quick Start

### Current Default (SQL-based)

```bash
./bootstrap.sh
```

### New API-based Method (Experimental)

```bash
# The bootstrap script now automatically starts and stops the server!
./bootstrap.sh --use-api
```

**What happens:**
1. Script builds and starts the workbench API server
2. Waits for server to be ready (checks `/health` endpoint)
3. Runs bootstrap with API-based seeding
4. Automatically stops the server when done

No need to manually start/stop the server!

## What Changed?

### New Files

- `backend/cmd/bootstrap/seed_api.go` - HTTP client for Workbench APIs
- `backend/cmd/bootstrap/seed_data_api.go` - API-based seeding implementation
- `backend/cmd/bootstrap/README_API_SEEDING.md` - Detailed documentation

### Modified Files

- `backend/cmd/bootstrap/bootstrap.go` - Added `-use-api` flag and routing logic
- `bootstrap.sh` - Added `--use-api` flag and automatic server management

### Unchanged

- `backend/cmd/bootstrap/migration.go` - Original SQL seeding still works as default

## Current API Coverage

### ✅ Using APIs (when `-use-api` flag is set)

- **Organizations**: `POST /api/v0/administration/orgs`
- **Users**: `POST /api/v0/administration/orgs/{orgId}/users`
- **Organization Modules**: `POST /api/v1/authz/organizations/{orgId}/modules`
- **User Modules**: `POST /api/v1/authz/users/{userId}/modules`
- **Organization Settings**: `PUT /api/v0/settings/org/me`

### ❌ Still Using SQL (no API available)

- **User Roles** - Managed in Zitadel, synced to database
- **Insurance Products** - No API endpoint exists
- **Feature Flags** - No API endpoint exists
- **Parent Config** - Partially covered by org settings API

## Benefits of API-Based Seeding

1. **Validation**: Uses the same validation as production
2. **Authorization**: Tests permission system during bootstrap
3. **Maintainability**: Single source of truth for data operations
4. **Testing**: Validates API endpoints work correctly

## Known Limitations

1. **Requires running server**: API-based seeding needs the workbench server to be running
2. **Slower**: HTTP overhead vs direct SQL
3. **Incomplete**: Some data still requires SQL (see above)
4. **Authentication**: Currently uses placeholder token (needs implementation)

## Migration Path

### Phase 1: Hybrid Approach (Current)

- ✅ Use APIs where available
- ✅ Fall back to SQL where needed
- ✅ Both methods produce identical results

### Phase 2: Add Missing APIs

Need to create:
- `POST /api/v0/settings/insurance-products`
- `POST /api/v0/settings/feature-flags`
- `POST /api/v1/authz/users/{userId}/roles` (or keep in Zitadel)

### Phase 3: Full API Coverage

- 100% API-based seeding
- Remove SQL fallbacks
- Better error handling and retries

## How Organizations, Users, and Roles Work

### Organizations

**Created in Zitadel first, then synced to DB:**

```
InitZitadel() → Zitadel API → Creates org in IDP
                            ↓
            AdministrationService.CreateOrganization()
                            ↓
            INSERT INTO organizations (SQL)
```

**Available API:** ✅ `POST /api/v0/administration/orgs`

### Users

**Created in Zitadel, provisioned in DB:**

```
CreateUser() → Zitadel API → Creates user, returns provider_user_id
                          ↓
        ProvisionUserFromZitadel() (SQL query)
                          ↓
        INSERT INTO organizations_users
```

**Available API:** ✅ `POST /api/v0/administration/orgs/{orgId}/users`

### Roles

**Managed in Zitadel, synced to DB automatically:**

```
Zitadel Project Roles (superadmin, admin, user)
                ↓
    SyncUserRole() - runs on every auth request
                ↓
    INSERT/UPDATE user_roles (SQL)
```

**Available API:** ❌ Roles are synced from Zitadel, no direct assignment API

**Why?** Zitadel is the source of truth for roles. The database `user_roles` table is a read-only mirror for performance.

### Modules

**Stored in database, managed via APIs:**

```
Settings Service → organizations_modules (org-level)
                → organizations_users_modules (user-level)
```

**Available APIs:**
- ✅ `POST /api/v1/authz/organizations/{orgId}/modules`
- ✅ `POST /api/v1/authz/users/{userId}/modules`
- ✅ `DELETE` endpoints to remove modules

## Testing

### Test SQL-based Seeding (Default)

```bash
# From repository root
./bootstrap.sh

# Verify data
cd backend
psql -h localhost -U workbench_owner workbench -c "SELECT * FROM organizations;"
psql -h localhost -U workbench_owner workbench -c "SELECT email, name FROM organizations_users;"
```

### Test API-based Seeding (Experimental)

```bash
# From repository root
./bootstrap.sh --use-api

# The script automatically:
# - Builds the API server
# - Starts it in the background
# - Waits for it to be ready
# - Runs API-based seeding
# - Stops the server when done

# Verify data
cd backend
psql -h localhost -U workbench_owner workbench -c "SELECT * FROM organizations;"
psql -h localhost -U workbench_owner workbench -c "SELECT email, name FROM organizations_users;"
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Bootstrap Process                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
                     ┌────────────────┐
                     │  bootstrap.go  │
                     │   (main func)  │
                     └────────┬───────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ↓                           ↓
    ┌──────────────────┐      ┌──────────────────────┐
    │  RunSeedData()   │      │  RunSeedDataAPI()    │
    │  (SQL-based)     │      │  (API-based)         │
    └────────┬─────────┘      └──────────┬───────────┘
             │                            │
             ↓                            ↓
    ┌─────────────────┐      ┌──────────────────────┐
    │  Direct SQL     │      │   APIClient          │
    │  INSERT INTO... │      │   HTTP requests      │
    └────────┬────────┘      └──────────┬───────────┘
             │                           │
             │                           ↓
             │              ┌──────────────────────┐
             │              │  Workbench APIs      │
             │              │  /administration     │
             │              │  /authz              │
             │              │  /settings           │
             │              └──────────┬───────────┘
             │                         │
             │                         ↓
             │              ┌──────────────────────┐
             │              │  Service Layer       │
             │              │  - Validation        │
             │              │  - Authorization     │
             │              │  - Business Logic    │
             │              └──────────┬───────────┘
             │                         │
             └─────────────┬───────────┘
                           │
                           ↓
                ┌──────────────────┐
                │   PostgreSQL     │
                │   Database       │
                └──────────────────┘
```

## Troubleshooting

### API-based seeding fails with "connection refused"

**Cause:** Workbench server is not running

**Solution:**
```bash
cd backend
task run &
sleep 5  # Wait for server to start
./cmd/bootstrap/bootstrap -port 9010 -use-api
```

### "Module not found" errors

**Cause:** Modules not registered before seeding

**Solution:** Ensure `RegisterAllModules()` runs before `RunSeedDataAPI()`

### SQL-based seeding still works after adding `-use-api`

**Cause:** Flag is not being parsed correctly

**Solution:**
```bash
# Rebuild the binary
go build -o cmd/bootstrap/bootstrap ./cmd/bootstrap

# Verify flag is set
./cmd/bootstrap/bootstrap -use-api=true -port 9010
```

## Related Documentation

- [Backend CLAUDE.md](backend/CLAUDE.md) - Backend development guidelines
- [Authorization System](backend/AUTHORIZATION_SYSTEM.md) - How authorization works
- [Bootstrap API README](backend/cmd/bootstrap/README_API_SEEDING.md) - Detailed API seeding docs

## Future Work

See `backend/cmd/bootstrap/README_API_SEEDING.md` for detailed roadmap.

**Key next steps:**
1. Add missing API endpoints for insurance products and feature flags
2. Implement proper service account authentication for API calls
3. Add idempotency and retry logic
4. Create integration tests for both seeding methods
5. Eventually deprecate SQL-based seeding in favor of API-based
