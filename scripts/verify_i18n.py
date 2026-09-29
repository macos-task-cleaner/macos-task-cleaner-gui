#!/usr/bin/env python3
"""
Verification Script for I18n Completeness in macOS Task Cleaner GUI
Checks that all 24 languages in Sources/I18n.swift have 100% key coverage.
"""
import sys
import os
import re

def verify_i18n(i18n_path="Sources/I18n.swift"):
    if not os.path.exists(i18n_path):
        print(f"[ERROR] {i18n_path} not found.")
        sys.exit(1)

    with open(i18n_path, "r", encoding="utf-8") as f:
        text = f.read()

    # 1. Extract enum keys
    enum_match = re.search(r"public enum I18nKey: String \{([\s\S]*?)\n\}", text)
    if not enum_match:
        print("[ERROR] Could not parse enum I18nKey")
        sys.exit(1)
    
    enum_keys = set(re.findall(r"case\s+([a-zA-Z0-9_]+)", enum_match.group(1)))
    total_keys = len(enum_keys)

    # 2. Extract languages
    trans_match = re.search(r"private let translations: \[AppLanguage: \[I18nKey: String\]\] = \[([\s\S]*?)\n\]", text)
    if not trans_match:
        print("[ERROR] Could not parse translations dictionary")
        sys.exit(1)

    trans_block = trans_match.group(1)

    lang_dict = {}
    current_lang = None
    for line in trans_block.splitlines():
        m_lang = re.match(r"^\s*\.([a-zA-Z]+):\s*\[", line)
        if m_lang:
            current_lang = m_lang.group(1)
            lang_dict[current_lang] = []
            continue
        if current_lang:
            m_key = re.match(r"^\s*\.([a-zA-Z0-9_]+):", line)
            if m_key:
                lang_dict[current_lang].append(m_key.group(1))
            if re.match(r"^\s*\],", line):
                current_lang = None

    print(f"==================================================")
    print(f" I18n 完整度校验报告 (基准枚举总键数: {total_keys})")
    print(f"==================================================")

    all_passed = True
    for lang, keys in lang_dict.items():
        keys_set = set(keys)
        missing = enum_keys - keys_set
        pct = (len(keys_set) / total_keys) * 100 if total_keys > 0 else 0
        status = "[PASS]" if len(missing) == 0 else f"[MISSING {len(missing)}]"
        print(f" {status:15s} .{lang:8s}: {len(keys_set):3d} / {total_keys:3d} ({pct:5.1f}%)")
        if missing:
            all_passed = False
            if len(missing) <= 5:
                print(f"                 缺失键: {', '.join(sorted(missing))}")

    print(f"--------------------------------------------------")
    if all_passed:
        print("[SUCCESS] 全部 24 种语言均已达成 100% 词条覆盖！")
        return 0
    else:
        print("[WARN] 部分语言存在缺失键，请运行批量注入脚本补全。")
        return 1

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "Sources/I18n.swift"
    sys.exit(verify_i18n(path))
