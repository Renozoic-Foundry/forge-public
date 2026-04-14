#!/usr/bin/env bash
# compose-modules.sh — Assemble FORGE command files from core + enabled modules
# Part of Spec 139 — Modular Feature Architecture
#
# Usage:
#   compose-modules.sh              # compose all modules based on onboarding.yaml
#   compose-modules.sh --check      # report module status without modifying files
#   compose-modules.sh --list       # list available modules
#   compose-modules.sh --enable NAME   # enable a module and recompose
#   compose-modules.sh --disable NAME  # disable a module and recompose

set -euo pipefail

# Find project root (look for .forge/ directory)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.forge/modules" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "ERROR: No .forge/modules directory found. Run from a FORGE project root." >&2
    return 1
}

PROJECT_ROOT="$(find_project_root)"
MODULES_DIR="$PROJECT_ROOT/.forge/modules"
ONBOARDING_FILE="$PROJECT_ROOT/.forge/onboarding.yaml"

# Parse a YAML value from onboarding.yaml (simple grep-based, handles null/true/false)
get_feature_toggle() {
    local feature="$1"
    if [[ ! -f "$ONBOARDING_FILE" ]]; then
        echo "null"
        return
    fi
    local value
    value=$(grep -A1 "^features:" "$ONBOARDING_FILE" 2>/dev/null | tail -1 || true)
    # More robust: search for the specific feature line
    value=$(grep "^  ${feature}:" "$ONBOARDING_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '[:space:]' || true)
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "null"
    else
        echo "$value"
    fi
}

# Get module display name from manifest
get_module_field() {
    local manifest="$1"
    local field="$2"
    grep "^${field}:" "$manifest" 2>/dev/null | head -1 | sed "s/^${field}: *//" | tr -d '"' || echo ""
}

# List all modules
list_modules() {
    echo "FORGE Modules:"
    echo ""
    printf "  %-20s %-35s %-10s %s\n" "MODULE" "DISPLAY NAME" "STATUS" "CATEGORY"
    printf "  %-20s %-35s %-10s %s\n" "------" "------------" "------" "--------"
    for manifest in "$MODULES_DIR"/*/module.yaml; do
        [[ -f "$manifest" ]] || continue
        local name display_name category toggle
        name=$(get_module_field "$manifest" "name")
        display_name=$(get_module_field "$manifest" "display_name")
        category=$(get_module_field "$manifest" "category")
        toggle=$(get_feature_toggle "$name")
        printf "  %-20s %-35s %-10s %s\n" "$name" "$display_name" "$toggle" "$category"
    done
}

# Check module status (dry run)
check_modules() {
    echo "Module Composition Status:"
    echo ""
    local issues=0
    for manifest in "$MODULES_DIR"/*/module.yaml; do
        [[ -f "$manifest" ]] || continue
        local name toggle
        name=$(get_module_field "$manifest" "name")
        toggle=$(get_feature_toggle "$name")

        if [[ "$toggle" == "null" ]]; then
            echo "  ⬜ $name — not yet decided (onboarding pending)"
            continue
        fi

        # Check marker consistency in target files
        local marker_issues=0
        while IFS= read -r target_line; do
            local target
            target=$(echo "$target_line" | sed 's/.*target: *//' | tr -d '[:space:]')
            [[ -z "$target" ]] && continue
            local target_file="$PROJECT_ROOT/$target"
            [[ -f "$target_file" ]] || continue

            local has_content=false
            if grep -q "<!-- module:${name} -->" "$target_file" 2>/dev/null; then
                # Check if there's content between markers
                local between
                between=$(sed -n "/<!-- module:${name} -->/,/<!-- \/module:${name} -->/p" "$target_file" | grep -v "<!-- " | grep -v "^$" | wc -l)
                [[ "$between" -gt 0 ]] && has_content=true
            fi

            if [[ "$toggle" == "true" && "$has_content" == "false" ]]; then
                echo "  ⚠️  $name — enabled but $target has empty markers"
                marker_issues=$((marker_issues + 1))
            elif [[ "$toggle" == "false" && "$has_content" == "true" ]]; then
                echo "  ⚠️  $name — disabled but $target still has content"
                marker_issues=$((marker_issues + 1))
            fi
        done < <(grep "target:" "$manifest" 2>/dev/null || true)

        if [[ "$marker_issues" -eq 0 ]]; then
            if [[ "$toggle" == "true" ]]; then
                echo "  ✅ $name — enabled, markers consistent"
            else
                echo "  ⭕ $name — disabled, markers clean"
            fi
        else
            issues=$((issues + marker_issues))
        fi
    done

    if [[ "$issues" -gt 0 ]]; then
        echo ""
        echo "  $issues issue(s) found. Run compose-modules.sh to fix."
        return 1
    else
        echo ""
        echo "  All modules consistent."
    fi
}

# Enable or disable a module
set_module_toggle() {
    local name="$1"
    local value="$2"

    if [[ ! -f "$ONBOARDING_FILE" ]]; then
        echo "ERROR: $ONBOARDING_FILE not found." >&2
        return 1
    fi

    # Update the toggle in onboarding.yaml
    if grep -q "^  ${name}:" "$ONBOARDING_FILE"; then
        sed -i "s|^  ${name}:.*$|  ${name}: ${value}|" "$ONBOARDING_FILE"
        echo "Set $name: $value in $ONBOARDING_FILE"
    else
        # Add under features: section
        sed -i "/^features:/a\\  ${name}: ${value}" "$ONBOARDING_FILE"
        echo "Added $name: $value to $ONBOARDING_FILE"
    fi
}

# Clear content between module markers in a file
clear_module_markers() {
    local file="$1"
    local module_name="$2"
    local start_marker="<!-- module:${module_name} -->"
    local end_marker="<!-- /module:${module_name} -->"

    if grep -q "$start_marker" "$file" 2>/dev/null; then
        # Remove content between markers, keep markers themselves
        sed -i "\|${start_marker}|,\|${end_marker}|{\|${start_marker}|b;\|${end_marker}|b;d}" "$file"
        echo "  Cleared $module_name markers in $(basename "$file")"
    fi
}

# Delete module-owned files
delete_module_files() {
    local manifest="$1"
    local deleted=0
    while IFS= read -r file_line; do
        local file_path
        file_path=$(echo "$file_line" | sed 's/.*- *//' | tr -d '[:space:]')
        [[ -z "$file_path" ]] && continue
        local full_path="$PROJECT_ROOT/$file_path"
        if [[ -f "$full_path" ]]; then
            rm -f "$full_path"
            deleted=$((deleted + 1))
        elif [[ -d "$full_path" ]]; then
            rm -rf "$full_path"
            deleted=$((deleted + 1))
        fi
    done < <(sed -n '/^files:/,/^[^ ]/p' "$manifest" | grep "^  - " || true)
    echo "  Deleted $deleted file(s)"
}

# Main composition
compose() {
    echo "Composing FORGE modules..."
    echo ""

    for manifest in "$MODULES_DIR"/*/module.yaml; do
        [[ -f "$manifest" ]] || continue
        local name toggle
        name=$(get_module_field "$manifest" "name")
        toggle=$(get_feature_toggle "$name")

        if [[ "$toggle" == "null" ]]; then
            echo "  ⬜ $name — skipped (not yet decided)"
            continue
        fi

        if [[ "$toggle" == "false" ]]; then
            echo "  ⭕ Disabling $name..."
            # Clear markers in shared files
            while IFS= read -r target_line; do
                local target
                target=$(echo "$target_line" | sed 's/.*target: *//' | tr -d '[:space:]')
                [[ -z "$target" ]] && continue
                local target_file="$PROJECT_ROOT/$target"
                [[ -f "$target_file" ]] && clear_module_markers "$target_file" "$name"
            done < <(grep "target:" "$manifest" 2>/dev/null || true)
        else
            echo "  ✅ $name — enabled (markers preserved)"
        fi
    done

    echo ""
    echo "Composition complete."
}

# Main
case "${1:-}" in
    --list)
        list_modules
        ;;
    --check)
        check_modules
        ;;
    --enable)
        [[ -z "${2:-}" ]] && { echo "Usage: $0 --enable MODULE_NAME" >&2; exit 1; }
        set_module_toggle "$2" "true"
        compose
        ;;
    --disable)
        [[ -z "${2:-}" ]] && { echo "Usage: $0 --disable MODULE_NAME" >&2; exit 1; }
        set_module_toggle "$2" "false"
        compose
        ;;
    "")
        compose
        ;;
    *)
        echo "Usage: $0 [--list | --check | --enable NAME | --disable NAME]" >&2
        exit 1
        ;;
esac
