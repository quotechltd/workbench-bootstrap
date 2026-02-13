# Zitadel Export Status

## Issue Found

❌ **Zitadel export FAILED - Token is invalid/expired**

### Error Details

**API Response**:
```json
{
  "code": 16,
  "message": "Errors.Token.Invalid (AUTH-7fs1e)",
  "details": [...]
}
```

**HTTP Status**: 401 Unauthorized

### Root Cause

The Personal Access Token (PAT) stored in `setup.env` is **invalid**:
- Either expired
- Or revoked
- Or lost permissions

### What This Means

The Zitadel export silently failed during the last setup run:
- ✅ Database restore completed successfully
- ❌ Zitadel data was NOT exported from UAT
- ❌ Zitadel data was NOT imported to local

**Impact**: Your local Zitadel does NOT have UAT users, organizations, or projects.

## How to Fix

### Option 1: Generate New PAT (Recommended)

1. Login to UAT Zitadel:
   ```
   https://test-vbzyqi.us1.zitadel.cloud/ui/console
   ```

2. Navigate to the service account:
   - Organization Settings → Service Users
   - Find `test-service@demo-customer`
   - Generate new Personal Access Token

3. Update `setup.env`:
   ```bash
   UAT_ZITADEL_SERVICE_KEY="<new-PAT-token>"
   ```

4. Run setup script again:
   ```bash
   ./setup-dev-environment.sh
   ```

### Option 2: Manual User Creation

Since the database is already populated, you just need a user with the right permissions:

1. Start local Zitadel:
   ```bash
   cd backend
   docker compose up -d zitadel
   ```

2. Login to local Zitadel:
   ```
   http://localhost:9010/ui/console
   ```

3. Use bootstrap admin credentials (from backend docker-compose.yaml)

4. Create a test user manually with:
   - Email: `will.hunt@quotech.io`
   - Password: From setup.env
   - Assign to organization
   - Grant necessary permissions/modules

### Option 3: Use Existing Backend Script

The backend likely has user auto-provisioning:
- When you login via the frontend
- The backend syncs users from Zitadel
- It creates database records automatically

So you might just need to:
1. Create a user in local Zitadel UI
2. Login via the frontend
3. Backend will sync the user automatically

## Improvements Made

The script now:
- ✅ Logs HTTP status codes for all Zitadel API calls
- ✅ Saves error responses to `*_error.json` files
- ✅ Shows clear success/failure summary
- ✅ Exports to `exports/` directory (not `/tmp`)
- ✅ All operations logged to `setup-dev-environment.log`

**Next run will show**:
```
Exported data summary:
  ✗ Organization: Failed (check exports/zitadel_export_*/organization_error.json)
  ✗ Users: Failed (check exports/zitadel_export_*/users_error.json)
  ✗ Projects: Failed (check exports/zitadel_export_*/projects_error.json)
```

## Current Status

**Database**: ✅ Successfully restored from UAT
- 1,298 rows imported
- Users, permissions, organizations all present in database
- Some year_of_account/claim records incomplete (acceptable)

**Zitadel**: ❌ No UAT data exported
- Empty organization.json (0 bytes)
- Empty users.json (0 bytes)
- Empty projects.json (0 bytes)
- Reason: Invalid/expired PAT token

## Recommendations

**For immediate development**:
1. Generate new PAT token
2. Update setup.env
3. Re-run: `./setup-dev-environment.sh`
4. Choose "y" to skip database dump (reuse existing)
5. Zitadel export will succeed with new token

**Alternative (if PAT generation is blocked)**:
1. Manually create test user in local Zitadel
2. Use backend's auto-provisioning
3. Database already has all permission data
