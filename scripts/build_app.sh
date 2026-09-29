#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

TARGET="${1:-native}"

echo "=============================================="
echo " Task Cleaner 应用程序打包构建脚本"
echo " 目标架构模式: $TARGET"
echo "=============================================="

# 确保图标文件存在
ensure_app_icon() {
    if [ ! -f "$DIR/Resources/AppIcon.icns" ] || [ "$DIR/scripts/generate_app_icon.swift" -nt "$DIR/Resources/AppIcon.icns" ]; then
        echo "[图标] 正在生成 AppIcon.icns..."
        swift "$DIR/scripts/generate_app_icon.swift"
        iconutil -c icns /tmp/AppIcon.iconset -o "$DIR/Resources/AppIcon.icns"
    fi
}

# 确保 DMG 背景图存在
ensure_dmg_background() {
    if [ ! -f "$DIR/Resources/dmg_background.png" ] || [ "$DIR/scripts/generate_dmg_background.swift" -nt "$DIR/Resources/dmg_background.png" ]; then
        echo "[DMG] 正在生成 Retina 分辨率 DMG 背景图..."
        swift "$DIR/scripts/generate_dmg_background.swift" "$DIR/Resources/dmg_background.png"
    fi
}

# 动态定位 TaskCleanerGUI 编译输出二进制
locate_gui_binary() {
    local scratch_dir="$1"
    local triple="$2"
    local candidate=""

    # 方式 1: 通过 swift build --show-bin-path 获取
    if [ -n "$triple" ]; then
        local bin_dir
        bin_dir="$(swift build -c release --triple "$triple" --scratch-path "$scratch_dir" --show-bin-path 2>/dev/null || true)"
        if [ -n "$bin_dir" ] && [ -f "$bin_dir/TaskCleanerGUI" ]; then
            echo "$bin_dir/TaskCleanerGUI"
            return 0
        fi
    else
        local bin_dir
        bin_dir="$(swift build -c release --show-bin-path 2>/dev/null || true)"
        if [ -n "$bin_dir" ] && [ -f "$bin_dir/TaskCleanerGUI" ]; then
            echo "$bin_dir/TaskCleanerGUI"
            return 0
        fi
    fi

    # 方式 2: 在 scratch 目录或 .build 目录中检索可执行文件
    if [ -d "$scratch_dir" ]; then
        candidate="$(find "$scratch_dir" -type f -name "TaskCleanerGUI" ! -path "*.dSYM*" ! -path "*/intermediates/*" | head -n 1)"
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    fi

    echo ""
}

# 查找对应架构的 mtc 引擎
find_mtc_binary() {
    local target_arch="$1"
    local cli_dir="$DIR/../macos-task-cleaner-cli"
    local candidate=""

    case "$target_arch" in
        arm64)
            if [ -f "$cli_dir/dist/arm64/mtc" ]; then
                candidate="$cli_dir/dist/arm64/mtc"
            elif [ -f "$cli_dir/target/aarch64-apple-darwin/release/mtc" ]; then
                candidate="$cli_dir/target/aarch64-apple-darwin/release/mtc"
            fi
            ;;
        x86_64)
            if [ -f "$cli_dir/dist/x86_64/mtc" ]; then
                candidate="$cli_dir/dist/x86_64/mtc"
            elif [ -f "$cli_dir/target/x86_64-apple-darwin/release/mtc" ]; then
                candidate="$cli_dir/target/x86_64-apple-darwin/release/mtc"
            fi
            ;;
        universal)
            if [ -f "$cli_dir/dist/universal/mtc" ]; then
                candidate="$cli_dir/dist/universal/mtc"
            elif [ -f "$cli_dir/target/aarch64-apple-darwin/release/mtc" ] && [ -f "$cli_dir/target/x86_64-apple-darwin/release/mtc" ]; then
                mkdir -p "$DIR/.build/universal"
                lipo -create "$cli_dir/target/aarch64-apple-darwin/release/mtc" "$cli_dir/target/x86_64-apple-darwin/release/mtc" -output "$DIR/.build/universal/mtc"
                candidate="$DIR/.build/universal/mtc"
            fi
            ;;
    esac

    # 回退检查：默认 target/release/mtc 或已安装的 mtc
    if [ -z "$candidate" ] || [ ! -f "$candidate" ]; then
        if [ -f "$cli_dir/target/release/mtc" ]; then
            candidate="$cli_dir/target/release/mtc"
        elif command -v mtc >/dev/null 2>&1; then
            candidate="$(command -v mtc)"
        fi
    fi

    echo "$candidate"
}

# 组装 TaskCleaner.app
assemble_bundle() {
    local target_arch="$1"
    local swift_bin="$2"
    local dest_dir="$3"

    echo "[组装] 正在组装 $target_arch 版本 -> $dest_dir"
    rm -rf "$dest_dir"
    local macos_dir="$dest_dir/Contents/MacOS"
    local resources_dir="$dest_dir/Contents/Resources"
    mkdir -p "$macos_dir" "$resources_dir"

    cp "$swift_bin" "$macos_dir/TaskCleanerGUI"
    chmod +x "$macos_dir/TaskCleanerGUI"

    local mtc_bin
    mtc_bin="$(find_mtc_binary "$target_arch")"
    if [ -n "$mtc_bin" ] && [ -f "$mtc_bin" ]; then
        echo "       嵌入内置 mtc 引擎: $mtc_bin"
        cp "$mtc_bin" "$macos_dir/mtc"
        chmod +x "$macos_dir/mtc"
    else
        echo "       [说明] 未检测到内置 mtc 引擎，应用将在运行时查找系统 PATH"
    fi

    cp "$DIR/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"

    cat << 'EOF' > "$dest_dir/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TaskCleanerGUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.donjone.taskcleaner-gui</string>
    <key>CFBundleName</key>
    <string>Task Cleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ja</string>
        <string>ko</string>
        <string>fr</string>
        <string>de</string>
        <string>es</string>
        <string>pt</string>
        <string>it</string>
        <string>ru</string>
        <string>nl</string>
        <string>pl</string>
        <string>tr</string>
        <string>ar</string>
        <string>th</string>
        <string>vi</string>
        <string>id</string>
        <string>sv</string>
        <string>da</string>
        <string>nb</string>
        <string>fi</string>
        <string>cs</string>
        <string>uk</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

    local langs=("en" "zh-Hans" "zh-Hant" "ja" "ko" "fr" "de" "es" "pt" "it" "ru" "nl" "pl" "tr" "ar" "th" "vi" "id" "sv" "da" "nb" "fi" "cs" "uk")
    for lang in "${langs[@]}"; do
        mkdir -p "$resources_dir/$lang.lproj"
        cat << EOF > "$resources_dir/$lang.lproj/InfoPlist.strings"
"CFBundleDisplayName" = "Task Cleaner";
"CFBundleName" = "Task Cleaner";
EOF
    done

    echo "       对 App Bundle 进行本地 Ad-Hoc 深度代码签名..."
    codesign -s - --force --deep "$dest_dir" >/dev/null 2>&1 || true
}

# 压缩 Zip 归档并计算 SHA256
package_zip() {
    local target_arch="$1"
    local source_app_dir="$2"
    local zip_file="$DIR/build/TaskCleaner-macOS-${target_arch}.zip"

    echo "[Zip] 正在打包 $(basename "$zip_file")..."
    (
        cd "$(dirname "$source_app_dir")"
        rm -f "$zip_file" "${zip_file}.sha256"
        zip -r -y -q "$zip_file" "$(basename "$source_app_dir")"
        cd "$DIR/build"
        shasum -a 256 "TaskCleaner-macOS-${target_arch}.zip" > "TaskCleaner-macOS-${target_arch}.zip.sha256"
        echo "      ZIP SHA256: $(cat "TaskCleaner-macOS-${target_arch}.zip.sha256")"
    )
}

# 打包 DMG 可视化拖拽安装盘并计算 SHA256
package_dmg() {
    local target_arch="$1"
    local source_app_dir="$2"
    local dmg_file="$DIR/build/TaskCleaner-macOS-${target_arch}.dmg"
    local source_parent_dir="$(dirname "$source_app_dir")"

    echo "[DMG] 正在打包 $(basename "$dmg_file")..."
    rm -f "$dmg_file" "${dmg_file}.sha256" "$DIR/build/rw.*.dmg" 2>/dev/null || true

    local bg_img="$DIR/Resources/dmg_background.png"
    local bg_opt=()
    if [ -f "$bg_img" ]; then
        bg_opt=(--background "$bg_img")
    fi

    local vol_icon="$DIR/Resources/AppIcon.icns"
    local icon_opt=()
    if [ -f "$vol_icon" ]; then
        icon_opt=(--volicon "$vol_icon")
    fi

    local built_with_create_dmg=false

    if command -v create-dmg >/dev/null 2>&1; then
        echo "       调用 create-dmg 进行可视化排版 (App + Applications 拖拽关联)..."
        local skip_opt=()
        if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
            skip_opt=(--skip-jenkins)
        fi

        if create-dmg \
            --volname "Task Cleaner" \
            "${icon_opt[@]}" \
            "${bg_opt[@]}" \
            --window-pos 200 120 \
            --window-size 600 380 \
            --icon-size 110 \
            --icon "TaskCleaner.app" 160 190 \
            --hide-extension "TaskCleaner.app" \
            --app-drop-link 440 190 \
            "${skip_opt[@]}" \
            --hdiutil-retries 10 \
            --overwrite \
            "$dmg_file" \
            "$source_parent_dir" >/dev/null 2>&1; then
            built_with_create_dmg=true
        else
            echo "       尝试使用 create-dmg 基础模式 (--skip-jenkins)..."
            if create-dmg \
                --volname "Task Cleaner" \
                "${icon_opt[@]}" \
                --icon-size 110 \
                --icon "TaskCleaner.app" 160 190 \
                --hide-extension "TaskCleaner.app" \
                --app-drop-link 440 190 \
                --skip-jenkins \
                --hdiutil-retries 10 \
                --overwrite \
                "$dmg_file" \
                "$source_parent_dir" >/dev/null 2>&1; then
                built_with_create_dmg=true
            fi
        fi
    fi

    if [ "$built_with_create_dmg" = false ]; then
        echo "       调用 macOS 原生 hdiutil 创建拖拽式安装镜像..."
        local staging_dir="$DIR/build/dmg_staging_${target_arch}"
        rm -rf "$staging_dir"
        mkdir -p "$staging_dir"
        cp -R "$source_app_dir" "$staging_dir/"
        ln -s /Applications "$staging_dir/Applications"
        hdiutil create \
            -volname "Task Cleaner" \
            -srcfolder "$staging_dir" \
            -ov \
            -format UDZO \
            "$dmg_file" >/dev/null
        rm -rf "$staging_dir"
    fi

    rm -f "$DIR/build/rw.*.dmg" 2>/dev/null || true

    (
        cd "$DIR/build"
        shasum -a 256 "TaskCleaner-macOS-${target_arch}.dmg" > "TaskCleaner-macOS-${target_arch}.dmg.sha256"
        echo "      DMG SHA256: $(cat "TaskCleaner-macOS-${target_arch}.dmg.sha256")"
    )
}

ensure_app_icon
ensure_dmg_background
mkdir -p "$DIR/build"

build_arm64() {
    echo "[编译] 正在准备 Apple Silicon (arm64) Release 二进制..."
    swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$DIR/.build/arm64"
    local bin
    bin="$(locate_gui_binary "$DIR/.build/arm64" "arm64-apple-macosx13.0")"
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        echo "[错误] 未找到编译完成的 arm64 TaskCleanerGUI 二进制文件"
        exit 1
    fi
    mkdir -p "$DIR/build/arm64"
    assemble_bundle "arm64" "$bin" "$DIR/build/arm64/TaskCleaner.app"
    package_zip "arm64" "$DIR/build/arm64/TaskCleaner.app"
    package_dmg "arm64" "$DIR/build/arm64/TaskCleaner.app"
}

build_x86_64() {
    echo "[编译] 正在准备 AMD64 / Intel (x86_64) Release 二进制..."
    swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$DIR/.build/x86_64"
    local bin
    bin="$(locate_gui_binary "$DIR/.build/x86_64" "x86_64-apple-macosx13.0")"
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        echo "[错误] 未找到编译完成的 x86_64 TaskCleanerGUI 二进制文件"
        exit 1
    fi
    mkdir -p "$DIR/build/x86_64"
    assemble_bundle "x86_64" "$bin" "$DIR/build/x86_64/TaskCleaner.app"
    package_zip "x86_64" "$DIR/build/x86_64/TaskCleaner.app"
    package_dmg "x86_64" "$DIR/build/x86_64/TaskCleaner.app"
}

build_universal() {
    echo "[编译] 准备构建 Universal 通用架构版本..."
    local arm64_bin
    arm64_bin="$(locate_gui_binary "$DIR/.build/arm64" "arm64-apple-macosx13.0")"
    if [ -z "$arm64_bin" ] || [ ! -f "$arm64_bin" ]; then
        build_arm64
        arm64_bin="$(locate_gui_binary "$DIR/.build/arm64" "arm64-apple-macosx13.0")"
    fi

    local x86_64_bin
    x86_64_bin="$(locate_gui_binary "$DIR/.build/x86_64" "x86_64-apple-macosx13.0")"
    if [ -z "$x86_64_bin" ] || [ ! -f "$x86_64_bin" ]; then
        build_x86_64
        x86_64_bin="$(locate_gui_binary "$DIR/.build/x86_64" "x86_64-apple-macosx13.0")"
    fi

    mkdir -p "$DIR/.build/universal"
    lipo -create \
        "$arm64_bin" \
        "$x86_64_bin" \
        -output "$DIR/.build/universal/TaskCleanerGUI"
    chmod +x "$DIR/.build/universal/TaskCleanerGUI"

    mkdir -p "$DIR/build/universal"
    assemble_bundle "universal" "$DIR/.build/universal/TaskCleanerGUI" "$DIR/build/universal/TaskCleaner.app"
    package_zip "universal" "$DIR/build/universal/TaskCleaner.app"
    package_dmg "universal" "$DIR/build/universal/TaskCleaner.app"

    # 同步兼容旧名称 TaskCleaner-macOS.zip 与 TaskCleaner-macOS.dmg
    cp "$DIR/build/TaskCleaner-macOS-universal.zip" "$DIR/build/TaskCleaner-macOS.zip"
    shasum -a 256 "$DIR/build/TaskCleaner-macOS.zip" > "$DIR/build/TaskCleaner-macOS.zip.sha256"

    cp "$DIR/build/TaskCleaner-macOS-universal.dmg" "$DIR/build/TaskCleaner-macOS.dmg"
    shasum -a 256 "$DIR/build/TaskCleaner-macOS.dmg" > "$DIR/build/TaskCleaner-macOS.dmg.sha256"
}

build_native() {
    echo "[编译] 开始编译本机原生架构 Release 二进制..."
    swift build -c release
    local bin
    bin="$(locate_gui_binary "$DIR/.build" "")"
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        echo "[错误] 未找到编译完成的 TaskCleanerGUI 二进制文件"
        exit 1
    fi
    assemble_bundle "native" "$bin" "$DIR/build/TaskCleaner.app"
    package_dmg "native" "$DIR/build/TaskCleaner.app"
    mv "$DIR/build/TaskCleaner-macOS-native.dmg" "$DIR/build/TaskCleaner.dmg"
    mv "$DIR/build/TaskCleaner-macOS-native.dmg.sha256" "$DIR/build/TaskCleaner.dmg.sha256"

    echo "[完成] 原生应用及 DMG 安装盘组装完成:"
    echo "       - App 应用目录: $DIR/build/TaskCleaner.app"
    echo "       - DMG 安装磁盘: $DIR/build/TaskCleaner.dmg"
}

build_bundle_only() {
    echo "[编译] 正在增量编译 Release 二进制 (跳过 DMG 打包)..."
    swift build -c release
    local bin
    local bin_dir
    bin_dir="$(swift build -c release --show-bin-path 2>/dev/null || true)"
    if [ -n "$bin_dir" ] && [ -f "$bin_dir/TaskCleanerGUI" ]; then
        bin="$bin_dir/TaskCleanerGUI"
    else
        bin="$(locate_gui_binary "$DIR/.build" "")"
    fi
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        echo "[错误] 未找到编译完成的 TaskCleanerGUI 二进制文件"
        exit 1
    fi
    assemble_bundle "native" "$bin" "$DIR/build/TaskCleaner.app"
    echo "[完成] App 应用目录: $DIR/build/TaskCleaner.app"
}

install_local() {
    build_bundle_only
    echo "[安装] 正在安装至 /Applications/TaskCleaner.app..."
    pkill -f TaskCleanerGUI 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/TaskCleaner.app"
    cp -R "$DIR/build/TaskCleaner.app" "/Applications/TaskCleaner.app"
    echo "[成功] 已成功安装至 /Applications/TaskCleaner.app"
}

case "$TARGET" in
    bundle|app)
        build_bundle_only
        ;;
    install)
        install_local
        ;;
    arm64)
        build_arm64
        rm -rf "$DIR/build/TaskCleaner.app"
        cp -R "$DIR/build/arm64/TaskCleaner.app" "$DIR/build/TaskCleaner.app"
        ;;
    x86_64|amd64)
        build_x86_64
        rm -rf "$DIR/build/TaskCleaner.app"
        cp -R "$DIR/build/x86_64/TaskCleaner.app" "$DIR/build/TaskCleaner.app"
        ;;
    universal)
        build_universal
        rm -rf "$DIR/build/TaskCleaner.app"
        cp -R "$DIR/build/universal/TaskCleaner.app" "$DIR/build/TaskCleaner.app"
        ;;
    all)
        build_arm64
        build_x86_64
        build_universal
        rm -rf "$DIR/build/TaskCleaner.app"
        cp -R "$DIR/build/universal/TaskCleaner.app" "$DIR/build/TaskCleaner.app"
        ;;
    native)
        build_native
        ;;
    *)
        echo "[错误] 未知架构目标: $TARGET"
        echo "支持选项: install | bundle | arm64 | x86_64 | amd64 | universal | all | native"
        exit 1
        ;;
esac

echo "[全部就绪] 构建与打包流程已顺利完成。"
