#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=8
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

printf '1..%s\n' "$TEST_COUNT"

desktop_packages="$ROOT_DIR/d-i/forky/classes/class-select/role/desktop.cfg"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
gtkgreet_css="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/greetd/gtkgreet.css"
crystal_dock_appearance_template="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/crystal-dock/labwc/appearance.conf.tmpl"
desktop_env="$ROOT_DIR/d-i/forky/hosts/profiles/btrfs/desktop.env"
mpv_conf="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mpv/mpv.conf"
mpv_input="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/mpv/input.conf"
target_assets="$ROOT_DIR/d-i/forky/scripts/late/target-assets.sh"
podman_late="$ROOT_DIR/d-i/forky/scripts/late/podman.sh"
docs_index="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/README.md"
podbin_doc="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/podbin.md"
podbin_bridge_doc="$ROOT_DIR/d-i/forky/hooks/shared/target/data/docs/podbin-service-bridge.md"
btrfs_family="$ROOT_DIR/d-i/forky/scripts/late/btrfs-family.sh"
f2fs_family="$ROOT_DIR/d-i/forky/scripts/late/f2fs-family.sh"

if grep -Eq '(^|[[:space:]])mpv([[:space:]]|$)' "$desktop_packages"; then
  pass "desktop package set installs mpv"
else
  fail "desktop package set installs mpv"
fi

if grep -q '/etc/skel/.config/mpv/mpv.conf' "$desktop_components" &&
   grep -q '/etc/skel/.config/mpv/input.conf' "$desktop_components" &&
   grep -Fq ".config/mpv \\" "$desktop_components" &&
   grep -q '/etc/skel/.config/mpv/mpv.conf' "$firstboot_validation" &&
   grep -q '/etc/skel/.config/mpv/input.conf' "$firstboot_validation" &&
   grep -Eq '^[[:space:]]+mpv[[:space:]]+\\$' "$firstboot_validation"; then
  pass "desktop role stages mpv config and validates it on first boot"
else
  fail "desktop role stages mpv config and validates it on first boot"
fi

if grep -q '^gpu-context=wayland$' "$mpv_conf" &&
   grep -q '^hwdec=vaapi-copy$' "$mpv_conf" &&
   grep -q '^save-position-on-quit=yes$' "$mpv_conf" &&
   grep -q '^volume-max=150$' "$mpv_conf" &&
   grep -q '^screenshot-directory=~/Pictures$' "$mpv_conf" &&
   grep -q '^WHEEL_UP add volume 2$' "$mpv_input" &&
   grep -q '^MBTN_BACK playlist-prev$' "$mpv_input"; then
  pass "mpv defaults force the VAAPI Wayland decode path with practical desktop controls"
else
  fail "mpv defaults force the VAAPI Wayland decode path with practical desktop controls"
fi

if grep -q '^  background-image: url("__INSTALLER_LABWC_GREETER_BACKGROUND_URL__");$' "$gtkgreet_css" &&
   grep -q '^  font-size: __INSTALLER_LABWC_GREETER_CLOCK_FONT_SIZE__px;$' "$gtkgreet_css" &&
   grep -q '^  margin: __INSTALLER_LABWC_GREETER_PANEL_MARGIN__px;$' "$gtkgreet_css" &&
   grep -q '^  min-width: __INSTALLER_LABWC_GREETER_PANEL_MIN_WIDTH__px;$' "$gtkgreet_css" &&
   grep -q '^  padding: __INSTALLER_LABWC_GREETER_PANEL_PADDING_Y__px __INSTALLER_LABWC_GREETER_PANEL_PADDING_X__px;$' "$gtkgreet_css" &&
   grep -q '^box#body label {$' "$gtkgreet_css" &&
   grep -q '^  font-size: __INSTALLER_LABWC_GREETER_LABEL_FONT_SIZE__px;$' "$gtkgreet_css" &&
   grep -q '^box#body entry#input-field {$' "$gtkgreet_css" &&
   grep -q '^  min-width: __INSTALLER_LABWC_GREETER_ENTRY_MIN_WIDTH__px;$' "$gtkgreet_css" &&
   grep -q '^box#body combobox#command-selector {$' "$gtkgreet_css" &&
   grep -q '^  min-width: __INSTALLER_LABWC_GREETER_SHELL_MIN_WIDTH__px;$' "$gtkgreet_css" &&
   grep -q '^box#body combobox#command-selector entry,$' "$gtkgreet_css" &&
   grep -q '^box#body combobox#command-selector button {$' "$gtkgreet_css" &&
   grep -q '^  min-width: 0;$' "$gtkgreet_css" &&
   grep -q '^box#body button {$' "$gtkgreet_css" &&
   grep -q '^  background-color: #374151;$' "$gtkgreet_css" &&
   grep -q '^box#body button.suggested-action {$' "$gtkgreet_css" &&
   grep -q '^  background-color: #1d4ed8;$' "$gtkgreet_css" &&
   grep -q '^  min-width: __INSTALLER_LABWC_GREETER_BUTTON_MIN_WIDTH__px;$' "$gtkgreet_css" &&
   grep -q '^desktop_render_gtkgreet_css() {$' "$desktop_components" &&
   grep -Eq '^[[:space:]]+"etc/greetd/gtkgreet.css" \\$' "$desktop_components" &&
   grep -Eq '^[[:space:]]+LABWC_GREETER_BACKGROUND_URL ' "$desktop_components" &&
   grep -Eq '^[[:space:]]+LABWC_GREETER_CLOCK_FONT_SIZE ' "$desktop_components" &&
   grep -Eq '^[[:space:]]+LABWC_GREETER_PANEL_MIN_WIDTH ' "$desktop_components" &&
   grep -Eq '^[[:space:]]+LABWC_GREETER_ENTRY_MIN_WIDTH ' "$desktop_components" &&
   grep -Eq '^[[:space:]]+LABWC_GREETER_BUTTON_MIN_WIDTH ' "$desktop_components" &&
   grep -q '^LABWC_GREETER_BACKGROUND_PATH=\"/usr/share/backgrounds/login/welcome-1920x1080.png\"$' "$desktop_env" &&
   grep -q '^LABWC_GTK_FONT_SIZE=\"12\"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_FONT_SIZE=\"17\"$' "$desktop_env" &&
   grep -q '^LABWC_GREETER_CLOCK_FONT_SIZE=\"104\"$' "$desktop_env"; then
  pass "gtkgreet styling is policy-driven and scales the real login widgets without distorting combobox alignment"
else
  fail "gtkgreet styling is policy-driven and scales the real login widgets without distorting combobox alignment"
fi

if grep -q '^stage_target_helper_docs() {$' "$target_assets" &&
   grep -q 'stage_target_helper_docs podbin.md podbin-service-bridge.md' "$podman_late" &&
   grep -q '^stage_target_docs_index$' "$btrfs_family" &&
   grep -q '^stage_target_docs_index$' "$f2fs_family"; then
  pass "late-command docs logic stages the docs index and the full podbin guide set"
else
  fail "late-command docs logic stages the docs index and the full podbin guide set"
fi

if grep -q 'installer always stages this index' "$docs_index" &&
   grep -Fq 'podbin-service-bridge.md' "$docs_index" &&
   grep -q '^## Root-admin lifecycle$' "$podbin_doc" &&
   grep -q '^### Wipe all resources and delete a Podbin user$' "$podbin_doc" &&
   grep -q '^## Daily-account bridge to the managed podsvc service$' "$podbin_doc" &&
   grep -q '^## Security model$' "$podbin_doc" &&
   grep -q '^## Discover the service environment$' "$podbin_bridge_doc" &&
   grep -q '^## Read-only Podman inspection$' "$podbin_bridge_doc" &&
   grep -q '^## Troubleshooting checklist$' "$podbin_bridge_doc"; then
  pass "staged podbin docs cover lifecycle, service bridge, and troubleshooting"
else
  fail "staged podbin docs cover lifecycle, service bridge, and troubleshooting"
fi

if grep -q '^minimumIconSize=__INSTALLER_LABWC_CRYSTAL_DOCK_MINIMUM_ICON_SIZE__$' "$crystal_dock_appearance_template" &&
   grep -q '^maximumIconSize=__INSTALLER_LABWC_CRYSTAL_DOCK_MAXIMUM_ICON_SIZE__$' "$crystal_dock_appearance_template" &&
   grep -q '^spacingFactor=0.56$' "$crystal_dock_appearance_template" &&
   grep -q '^tooltipFontSize=__INSTALLER_LABWC_CRYSTAL_DOCK_TOOLTIP_FONT_SIZE__$' "$crystal_dock_appearance_template" &&
   grep -q '^floatingMargin=5$' "$crystal_dock_appearance_template" &&
   grep -q '^iconSize=__INSTALLER_LABWC_CRYSTAL_DOCK_APP_MENU_ICON_SIZE__$' "$crystal_dock_appearance_template" &&
   grep -q '^fontSize=__INSTALLER_LABWC_CRYSTAL_DOCK_APP_MENU_FONT_SIZE__$' "$crystal_dock_appearance_template" &&
   grep -q '^fontScaleFactor=__INSTALLER_LABWC_CRYSTAL_DOCK_CLOCK_FONT_SCALE_FACTOR__$' "$crystal_dock_appearance_template" &&
   grep -q '^LABWC_CRYSTAL_DOCK_MINIMUM_ICON_SIZE="50"$' "$desktop_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_MAXIMUM_ICON_SIZE="80"$' "$desktop_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_TOOLTIP_FONT_SIZE="13"$' "$desktop_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_APP_MENU_ICON_SIZE="40"$' "$desktop_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_APP_MENU_FONT_SIZE="15"$' "$desktop_env" &&
   grep -q '^LABWC_CRYSTAL_DOCK_CLOCK_FONT_SCALE_FACTOR="1.0"$' "$desktop_env" &&
   grep -q 'appearance.conf.tmpl' "$desktop_components"; then
  pass "crystal dock sizing is policy-driven through the managed appearance template"
else
  fail "crystal dock sizing is policy-driven through the managed appearance template"
fi

if grep -q '^sudo podbin --create-user alice$' "$podbin_doc" &&
   grep -q '^sudo podbin --wipe-all alice$' "$podbin_doc" &&
   grep -q 'does not configure or' "$podbin_doc" &&
   grep -q 'fuse-overlayfs' "$podbin_doc" &&
   grep -q '^sudo podbin --service-env$' "$podbin_doc" &&
   grep -q '^sudo podbin --service-systemctl status podman.socket$' "$podbin_bridge_doc"; then
  pass "podbin docs include concrete operator command examples"
else
  fail "podbin docs include concrete operator command examples"
fi

[ "$FAIL_COUNT" -eq 0 ]
