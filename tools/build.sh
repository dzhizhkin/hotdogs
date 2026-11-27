#!/bin/sh
# Собирает игру и пакует архивы в build/upload.
# Запуск: sh tools/build.sh [macos|windows]  (без аргумента — обе платформы)
# Godot берётся из $GODOT, иначе из PATH. Нужен .env с ключами EOS — экспорт кладёт его в pck.
set -eu

cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
BUILD=build
OUT="$BUILD/upload"

[ -f .env ] || { echo "Нет .env с ключами EOS" >&2; exit 1; }

check() {
	"$GODOT" --headless --path . --import > /dev/null 2>&1
	"$GODOT" --headless --path . --quit-after 120 scenes/main.tscn > "$BUILD/check.log" 2>&1 || true
	if grep -qE "SCRIPT ERROR|Parse Error" "$BUILD/check.log"; then
		cat "$BUILD/check.log" >&2
		echo "✗ Ошибки в скриптах" >&2
		exit 1
	fi
}

build_macos() {
	app="$BUILD/macos/Hotdogs.app"
	key=Hotdogs-macOS.zip
	rm -rf "$app" "$OUT/$key"
	mkdir -p "$BUILD/macos"
	"$GODOT" --headless --path . --export-release macOS "$app"
	# Зависимость из eosg.gdextension копируется ещё и в корень Frameworks, хотя
	# плагин грузит копию из своего фреймворка (@loader_path) — лишние 48 МБ
	rm -f "$app/Contents/Frameworks/libEOSSDK-Mac-Shipping.dylib"
	# Встроенная подпись Godot ломает печать вокруг фреймворка EOSG, переподписываем ad-hoc
	fw="$app/Contents/Frameworks/libeosg.macos.template_release.framework"
	codesign --force --sign - "$fw/libEOSSDK-Mac-Shipping.dylib"
	codesign --force --sign - "$fw"
	codesign --force --sign - --preserve-metadata=entitlements,flags "$app"
	codesign --verify --deep --strict "$app"
	# ditto сохраняет подпись и атрибуты пакета .app
	ditto -c -k --keepParent "$app" "$OUT/$key"
}

build_windows() {
	dir="$BUILD/windows"
	key=Hotdogs-Windows.zip
	rm -rf "$dir" "$OUT/$key"
	mkdir -p "$dir"
	"$GODOT" --headless --path . --export-release "Windows Desktop" "$dir/hotdogs.exe"
	# Рядом с exe лежат DLL плагина и EOS SDK, без них игра не запустится
	(cd "$dir" && zip -q -9 -r "../upload/$key" .)
}

mkdir -p "$OUT"
if [ $# -eq 0 ]; then set -- macos windows; fi
check
for platform in "$@"; do
	case "$platform" in
		macos) build_macos ;;
		windows) build_windows ;;
		*) echo "Неизвестная платформа: $platform" >&2; exit 1 ;;
	esac
	size=$(wc -c < "$OUT/$key" | tr -d ' ')
	echo "✓ $platform: $OUT/$key, $((size / 1048576)) МБ"
done
