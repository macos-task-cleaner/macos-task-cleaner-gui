#!/usr/bin/env python3
import sys
import argparse
import re

def update_i18n(key, en_val, zh_hans_val, zh_hant_val, i18n_path="Sources/I18n.swift"):
    with open(i18n_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Check if key already exists
    if f"case {key}" in content:
        print(f"[WARN] Key '{key}' already exists in enum I18nKey.")
    else:
        # Insert into enum I18nKey before the closing bracket of enum I18nKey
        # Find the line right before the closing brace of enum I18nKey
        enum_pattern = r"(public enum I18nKey: String \{[\s\S]*?)(\n\})"
        match = re.search(enum_pattern, content)
        if not match:
            print("[ERROR] Could not find enum I18nKey closing bracket.")
            sys.exit(1)
        content = content[:match.start(2)] + f"\n    case {key}" + content[match.start(2):]

    # 2. Insert into .en dictionary
    en_pattern = r"(\.en: \[[\s\S]*?)(\n    \],)"
    match = re.search(en_pattern, content)
    if not match:
        print("[ERROR] Could not find .en dictionary closing bracket.")
        sys.exit(1)
    if f".{key}:" not in match.group(1):
        content = content[:match.start(2)] + f'\n        .{key}: "{en_val}",' + content[match.start(2):]

    # 3. Insert into .zhHans dictionary
    zh_hans_pattern = r"(\.zhHans: \[[\s\S]*?)(\n    \],)"
    match = re.search(zh_hans_pattern, content)
    if not match:
        print("[ERROR] Could not find .zhHans dictionary closing bracket.")
        sys.exit(1)
    if f".{key}:" not in match.group(1):
        content = content[:match.start(2)] + f'\n        .{key}: "{zh_hans_val}",' + content[match.start(2):]

    # 4. Insert into .zhHant dictionary
    zh_hant_pattern = r"(\.zhHant: \[[\s\S]*?)(\n    \],)"
    match = re.search(zh_hant_pattern, content)
    if not match:
        print("[ERROR] Could not find .zhHant dictionary closing bracket.")
        sys.exit(1)
    if f".{key}:" not in match.group(1):
        content = content[:match.start(2)] + f'\n        .{key}: "{zh_hant_val}",' + content[match.start(2):]

    with open(i18n_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[SUCCESS] Successfully injected '{key}' into I18n.swift.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Batch update I18n.swift dictionary")
    parser.add_argument("--key", required=True, help="I18nKey case name")
    parser.add_argument("--en", required=True, help="English translation")
    parser.add_argument("--zh", required=True, help="Simplified Chinese translation")
    parser.add_argument("--zht", required=False, help="Traditional Chinese translation (defaults to --zh if omitted)")
    args = parser.parse_args()

    zht = args.zht if args.zht else args.zh
    update_i18n(args.key, args.en, args.zh, zht)
