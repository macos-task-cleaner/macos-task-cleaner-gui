#!/usr/bin/env python3
"""
Batch I18n Injection Tool for macOS Task Cleaner GUI
Reads a JSON file with language translations and safely injects missing keys into Sources/I18n.swift.
"""
import sys
import json
import re
import os

def inject_translations(json_path, i18n_path="Sources/I18n.swift"):
    if not os.path.exists(json_path):
        print(f"[ERROR] JSON file not found: {json_path}")
        sys.exit(1)
    if not os.path.exists(i18n_path):
        print(f"[ERROR] I18n.swift file not found: {i18n_path}")
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    with open(i18n_path, "r", encoding="utf-8") as f:
        content = f.read()

    total_added = 0
    languages_updated = []

    for lang, keys_dict in data.items():
        if not isinstance(keys_dict, dict) or not keys_dict:
            continue

        # Match the language dictionary block: .<lang>: [\n...\n    ],
        pattern = rf"(\.{lang}:\s*\[[\s\S]*?)(\n    \],)"
        match = re.search(pattern, content)
        if not match:
            print(f"[WARN] Language block for .{lang} not found in {i18n_path}")
            continue

        lang_block = match.group(1)
        closing = match.group(2)

        added_for_lang = 0
        new_entries = []

        for raw_key, val in keys_dict.items():
            key = raw_key.lstrip(".")
            # Escape double quotes and newlines if not already escaped
            # If string already has \n or \", preserve or escape
            clean_val = val.replace("\r", "")
            # Ensure escaped backslashes and quotes
            clean_val = clean_val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            
            # Check if key already exists in this language
            if f".{key}:" in lang_block:
                continue

            new_entries.append(f'        .{key}: "{clean_val}",')
            added_for_lang += 1

        if new_entries:
            injected_block = lang_block + "\n" + "\n".join(new_entries) + closing
            content = content[:match.start()] + injected_block + content[match.end():]
            total_added += added_for_lang
            languages_updated.append((lang, added_for_lang))

    with open(i18n_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[SUCCESS] Injected {total_added} total keys across {len(languages_updated)} languages.")
    for lang, count in languages_updated:
        print(f"  - {lang}: +{count} keys")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/batch_inject_i18n.py <translations.json> [path/to/I18n.swift]")
        sys.exit(1)
    json_file = sys.argv[1]
    swift_file = sys.argv[2] if len(sys.argv) > 2 else "Sources/I18n.swift"
    inject_translations(json_file, swift_file)
