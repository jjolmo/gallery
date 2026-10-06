#!/bin/sh
# Installs the unpacked release bundle for the current user.
set -e
here=$(cd "$(dirname "$0")" && pwd)
prefix="${PREFIX:-$HOME/.local}"
mkdir -p "$prefix/lib/gallery" "$prefix/bin" "$prefix/share/applications" "$prefix/share/icons/hicolor/512x512/apps"
cp -r "$here"/gallery "$here"/lib "$here"/data "$prefix/lib/gallery/"
ln -sf "$prefix/lib/gallery/gallery" "$prefix/bin/gallery"
cp "$here/data/flutter_assets/assets/icon.png" "$prefix/share/icons/hicolor/512x512/apps/com.jjolmo.gallery.png"
sed "s|^Exec=.*|Exec=$prefix/bin/gallery|" "$here/gallery.desktop" > "$prefix/share/applications/com.jjolmo.gallery.desktop"
echo "Installed to $prefix. Needs libmpv (Debian/Ubuntu: sudo apt install libmpv2)."
