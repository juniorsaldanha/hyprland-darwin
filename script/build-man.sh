#!/usr/bin/env bash
# Man pages for the `hypr` CLI (hypr.1, hypr-<command>.1) from docs/aerospace-*.adoc, into .man/.
# Needs asciidoctor (brew install asciidoctor). Run by .github/workflows/release.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf .man && mkdir -p .man/util
cp docs/util/*.adoc .man/util/
cat > .man/util/man-attributes.adoc <<'ADOC'
ifndef::env-site[]
:doctype: manpage
:manmanual: HyprDarwin Manual
:mansource: HyprDarwin
endif::[]
ADOC
cat > .man/util/man-footer.adoc <<'ADOC'
== Resources

*Project homepage:* https://github.com/juniorsaldanha/hyprland-darwin +
*Website:* https://juniorsaldanha.github.io/hyprland-darwin/ +
*Tiling commands in depth (AeroSpace):* https://nikitabobko.github.io/AeroSpace/commands +

== BUGS

Report bugs at https://github.com/juniorsaldanha/hyprland-darwin/issues

== License

MIT. Copyright (C) 2026 Junior Saldanha (HyprDarwin), Copyright (C) 2023 Nikita Bobko (AeroSpace).

== AUTHOR

Junior Saldanha, Nikita Bobko and contributors
ADOC

# The command is `hypr`; the app is HyprDarwin. Links to AeroSpace's site keep their name.
for file in docs/aerospace*.adoc; do
    sed -E 's/(^|[^-a-z./])aerospace($|[^.a-z])/\1hypr\2/g; s/(^|[^/.#])aerospace-/\1hypr-/g; s/(^|[^/])AeroSpace/\1HyprDarwin/g' "$file" \
        > ".man/$(basename "$file" | sed 's/^aerospace/hypr/')"
done

cd .man
asciidoctor -b manpage hypr*.adoc
# groff renders bare .~ and /~ as ligatures: use its literal-tilde escape
sed -E -i '' 's|\.~|\.\\[ti]|g; s|/~|/\\[ti]|g' hypr-test.1
rm -rf -- *.adoc util
echo "Built $(ls | wc -l | tr -d ' ') man pages in .man/"
