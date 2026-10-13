#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

install=false
[[ "${1:-}" == "--install" ]] && install=true

swift build -c release --product HyprOSX
swift build -c release --product hyprctl
bin="$(swift build -c release --show-bin-path)"
app=".build/HyprOSX.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/HyprOSX" "$bin/hyprctl" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp NOTICE "$app/Contents/Resources/NOTICE"

identity="HyprOSX Local Signing"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
    sign="$identity"
else
    sign="-"
    print -u2 "note: no \"$identity\" identity, signing ad hoc; macOS asks for Accessibility again after each rebuild"
fi
codesign --force --sign "$sign" --identifier dev.hyprosx.hyprctl "$app/Contents/MacOS/hyprctl"
codesign --force --sign "$sign" --identifier dev.hyprosx.HyprOSX "$app"
codesign --verify --strict "$app"
print "built $app (signature: $sign)"

if $install; then
    dest="$HOME/Applications/HyprOSX.app"
    running=false
    if pgrep -xq HyprOSX; then
        running=true
        pkill -TERM -x HyprOSX
        for _ in {1..50}; do pgrep -xq HyprOSX || break; sleep 0.1; done
    fi
    mkdir -p "$HOME/Applications" "$HOME/.local/bin"
    rsync -a --delete "$app/" "$dest/"
    ln -sf "$dest/Contents/MacOS/hyprctl" "$HOME/.local/bin/hyprctl"
    print "installed $dest and $HOME/.local/bin/hyprctl"
    if $running; then open "$dest"; fi
fi
