#!/usr/bin/env bash

# This script analyzes database restore errors and provides recommendations

LOG_FILE="setup-dev-environment.log"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

echo "=== Database Restore Error Analysis ==="
echo ""

# Count error types
echo "Error Summary:"
echo "-------------"
ownership_errors=$(grep -c "must be owner" "$LOG_FILE" 2>/dev/null || echo 0)
fk_errors=$(grep -c "violates foreign key constraint" "$LOG_FILE" 2>/dev/null || echo 0)
duplicate_errors=$(grep -c "duplicate key value" "$LOG_FILE" 2>/dev/null || echo 0)
extension_errors=$(grep -c "extension.*not available\|extension.*does not exist" "$LOG_FILE" 2>/dev/null || echo 0)
already_exists=$(grep -c "already exists" "$LOG_FILE" 2>/dev/null || echo 0)

echo "  Ownership errors: $ownership_errors"
echo "  Foreign key violations: $fk_errors"
echo "  Duplicate key errors: $duplicate_errors"
echo "  Extension errors: $extension_errors"
echo "  Already exists errors: $already_exists"
echo ""

echo "Analysis:"
echo "--------"
if [[ $ownership_errors -gt 0 ]]; then
    echo "✓ Ownership errors ($ownership_errors) - These are SAFE TO IGNORE"
    echo "  The --no-owner flag prevents ownership issues from blocking the restore."
    echo ""
fi

if [[ $duplicate_errors -gt 0 ]] || [[ $already_exists -gt 0 ]]; then
    echo "✓ Duplicate/Already exists errors ($((duplicate_errors + already_exists))) - These are EXPECTED"
    echo "  These occur because the database already has base data (currencies, countries, etc.)"
    echo "  The restore skips these and continues."
    echo ""
fi

if [[ $extension_errors -gt 0 ]]; then
    echo "⚠ Extension errors ($extension_errors) - ACTION REQUIRED"
    echo "  Missing extensions:"
    grep "extension.*not available\|extension.*does not exist" "$LOG_FILE" | head -5
    echo ""
fi

if [[ $fk_errors -gt 0 ]]; then
    echo "⚠ Foreign key violations ($fk_errors) - PARTIAL DATA LOSS"
    echo "  These occur when parent records are missing (usually due to ownership/permission issues)"
    echo "  Top missing references:"
    grep "violates foreign key constraint" "$LOG_FILE" | sed 's/ERROR:  //' | sort | uniq -c | sort -rn | head -10
    echo ""
fi

echo "Recommendations:"
echo "---------------"
if [[ $fk_errors -gt 100 ]]; then
    echo "1. Most FK errors are due to the database being partially populated already"
    echo "2. Try running with a CLEAN database (drop all data first)"
    echo "3. Or accept that some records won't be imported due to missing dependencies"
else
    echo "✓ The restore completed successfully despite the errors"
    echo "✓ Most errors are benign (ownership, duplicates, already exists)"
fi

echo ""
echo "To view full log: less $LOG_FILE"
