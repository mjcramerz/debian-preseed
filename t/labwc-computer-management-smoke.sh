#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-computer-management.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=22
TEST_INDEX=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
  exit 1
}

computer_management="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-computer-management"
ai_copilots="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-ai-copilots"
ai_copilots_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-ai-copilots-action"
ai_copilots_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/ai-copilots"
ai_runtime_module="$ai_copilots_module_root/AICopilots/Runtime.pm"
ai_model_catalog_module="$ai_copilots_module_root/AICopilots/ModelCatalog.pm"
ai_model_install_module="$ai_copilots_module_root/AICopilots/ModelInstallRoot.pm"
ai_model_store_module="$ai_copilots_module_root/AICopilots/ModelStore.pm"
ai_catalog_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/share/labwc-ai-copilots"
ai_llama_catalog="$ai_catalog_root/llama-models.tsv"
ai_whisper_catalog="$ai_catalog_root/whisper-models.tsv"
ai_llama_server="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-ai-llama-server"
ai_model_install_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-ai-model-install-root"
ai_copilots_python_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages"
ai_gguf_module="$ai_copilots_python_root/labwc_ai_copilots/gguf.py"
ai_model_info="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-ai-model-info"
llama_server_unit="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/systemd/user/llama-server.service"
digital_assets="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-digital-assets"
digital_assets_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-digital-assets-action"
digital_assets_module_root="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/perl5/site_perl/digital-assets"
digital_assets_catalog="$digital_assets_module_root/DigitalAssets/Catalog.pm"
digital_assets_cli="$digital_assets_module_root/DigitalAssets/CLI.pm"
digital_assets_context="$digital_assets_module_root/DigitalAssets/Context.pm"
digital_assets_document="$digital_assets_module_root/DigitalAssets/Document.pm"
digital_assets_pdf="$digital_assets_module_root/DigitalAssets/PDF.pm"
display_configuration="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-display-configuration"
maintenance_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-maintenance-menu"
users_groups_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-users-groups-menu"
firewall_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-firewall-menu"
fuzzel_wrapper="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-fuzzel"
labwc_rc="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/rc.xml.tmpl"
labwc_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/etc/skel/.config/labwc/menu.xml"
computer_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/computer-management.desktop"
rdp_desktop="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/share/applications/remote-desktop-management.desktop"
components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
apparmor_profile="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/apparmor.d/managed-desktop-wrappers"
llama_late="$ROOT_DIR/d-i/forky/scripts/late/llama.sh"
whisper_late="$ROOT_DIR/d-i/forky/scripts/late/whisper.sh"
digital_assets_perl_compat="$TMP_DIR/digital-assets-perl-compat"

mkdir -p "$digital_assets_perl_compat/MooX" "$digital_assets_perl_compat/Types"
cat >"$digital_assets_perl_compat/Moo.pm" <<'EOF'
package Moo;
use strict;
use warnings;
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::has"} = sub { return; };
    return;
}
1;
EOF
cat >"$digital_assets_perl_compat/MooX/StrictConstructor.pm" <<'EOF'
package MooX::StrictConstructor;
use strict;
use warnings;
sub import { return; }
1;
EOF
cat >"$digital_assets_perl_compat/MooX/TypeTiny.pm" <<'EOF'
package MooX::TypeTiny;
use strict;
use warnings;
sub import { return; }
1;
EOF
cat >"$digital_assets_perl_compat/Types/Standard.pm" <<'EOF'
package Types::Standard;
use strict;
use warnings;
sub import {
    my ($class, @symbols) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $symbol (@symbols) {
        *{"${caller}::${symbol}"} = sub { return sub { 1 }; };
    }
    return;
}
1;
EOF

printf '1..%s\n' "$TEST_COUNT"

categories_ok=true
for category in \
  'Container Management' \
  'Remote Desktop' \
  'Endpoint Security' \
  'Digital Assets' \
  'Users & Groups' \
  'Network Management' \
  'System Configuration' \
  'Phone Management' \
  'Backup & Recovery' \
  'Hardware & Peripherals' \
  'AI & Copilots'
do
  grep -Fq "\"⮞ ${category}\"" "$computer_management" ||
    categories_ok=false
done
category_sizing_ok=true
for setting_name in \
  LABWC_FUZZEL_CONTAINER_MANAGEMENT_WIDTH \
  LABWC_FUZZEL_REMOTE_DESKTOP_WIDTH \
  LABWC_FUZZEL_ENDPOINT_SECURITY_WIDTH \
  LABWC_FUZZEL_DIGITAL_ASSETS_WIDTH \
  LABWC_FUZZEL_USERS_GROUPS_WIDTH \
  LABWC_FUZZEL_NETWORK_MANAGEMENT_WIDTH \
  LABWC_FUZZEL_FIREWALL_SECURITY_WIDTH \
  LABWC_FUZZEL_SYSTEM_CONFIGURATION_WIDTH \
  LABWC_FUZZEL_PHONE_MANAGEMENT_WIDTH \
  LABWC_FUZZEL_BACKUP_RECOVERY_WIDTH \
  LABWC_FUZZEL_HARDWARE_PERIPHERALS_WIDTH \
  LABWC_FUZZEL_AI_COPILOTS_WIDTH
do
  grep -Fq "$setting_name" "$computer_management" ||
    category_sizing_ok=false
done
if [ "$categories_ok" = true ] &&
   [ "$category_sizing_ok" = true ] &&
   grep -q '^LABWC_FUZZEL_MANAGED_ICONS=1$' "$computer_management" &&
   grep -q '^choose_root_lines() {$' "$computer_management" &&
   grep -q '^run_sized_menu() ($' "$computer_management" &&
   grep -q '^    choose_root_lines \\$' "$computer_management" &&
   grep -Fq -- "--prompt \"\$prompt\"" "$computer_management" &&
   ! grep -Eq -- '--(width|lines)=' "$computer_management"; then
  pass "Computer Management exposes the complete icon-aware category tree"
else
  fail "Computer Management exposes the complete icon-aware category tree"
fi

codex_root_expected="$TMP_DIR/codex-root.expected"
llama_root_expected="$TMP_DIR/llama-root.expected"
llama_models_expected="$TMP_DIR/llama-models.expected"
llama_server_expected="$TMP_DIR/llama-server.expected"
whisper_root_expected="$TMP_DIR/whisper-root.expected"
whisper_models_expected="$TMP_DIR/whisper-models.expected"
cat >"$codex_root_expected" <<'EOF'
★ New Coding Session
★ Resume Last Session
★ Implement Task…
⮞ Sessions
⮞ Code Actions
⮞ Project Context
⮞ Models & Reasoning
⮞ Skills & Tools
⮞ Diagnostics
EOF
cat >"$llama_root_expected" <<'EOF'
★ Ask Llama…
★ New Chat
★ Resume Last Chat
★ Change Model…
★ Download New Model…
⮞ ★ Persistent Memory
⮞ Models
⮞ Chat & Context
⮞ Prompt Presets
⮞ Runtime
⮞ Performance
⮞ Server
⮞ Storage
⮞ Diagnostics
EOF
cat >"$llama_models_expected" <<'EOF'
Change Model…
Download New Model…
Search Models…
Browse Recommended Models
Browse Coding Models
Browse Reasoning Models
Browse Small / Fast Models
Browse Vision Models
Browse Embedding Models
Browse Recently Added Models
Show Installed Models
⮞ Favorite Models
Recent Models
Set Default Model
Set Model Alias
Show Model Details
Show Model License
Show Model Architecture
Show Parameter Count
Show Quantization
Show Model Size
Show Context Length
Show Disk Location
EOF
cat >"$llama_server_expected" <<'EOF'
Start Llama Server
Stop Llama Server
Show Server Status
Show Server Configuration
Show Server Endpoint
Show Server Help
EOF
cat >"$whisper_root_expected" <<'EOF'
★ Push-to-Talk
★ Toggle Dictation
★ Transcribe File…
★ Transcribe Last Recording
★ Change Model…
★ Download New Model…
★ Live Captions
★ Voice Note
⮞ Recording
⮞ Transcription
⮞ Languages
⮞ Output
⮞ Post-Processing
⮞ Models
⮞ History
⮞ Audio Devices
⮞ Diagnostics
EOF
cat >"$whisper_models_expected" <<'EOF'
Change Model…
Download New Model…
Show Installed Models
Show Configured Model
Show Model Size
Show Model Location
Check Model Readability
Prune Partial Downloads
Show Whisper Configuration
EOF

if /bin/sh "$ai_copilots" --catalog codex-root >"$TMP_DIR/codex-root.actual" &&
   /bin/sh "$ai_copilots" --catalog llama-root >"$TMP_DIR/llama-root.actual" &&
   /bin/sh "$ai_copilots" --catalog llama-models >"$TMP_DIR/llama-models.actual" &&
   /bin/sh "$ai_copilots" --catalog llama-server >"$TMP_DIR/llama-server.actual" &&
   /bin/sh "$ai_copilots" --catalog whisper-root >"$TMP_DIR/whisper-root.actual" &&
   /bin/sh "$ai_copilots" --catalog whisper-models >"$TMP_DIR/whisper-models.actual" &&
   cmp -s "$codex_root_expected" "$TMP_DIR/codex-root.actual" &&
   cmp -s "$llama_root_expected" "$TMP_DIR/llama-root.actual" &&
   cmp -s "$llama_models_expected" "$TMP_DIR/llama-models.actual" &&
   cmp -s "$llama_server_expected" "$TMP_DIR/llama-server.actual" &&
   cmp -s "$whisper_root_expected" "$TMP_DIR/whisper-root.actual" &&
   cmp -s "$whisper_models_expected" "$TMP_DIR/whisper-models.actual"; then
  pass "AI & Copilots exposes the requested root catalogs and fixed-storage model actions"
else
  fail "AI & Copilots exposes the exact requested Codex, Llama, Whisper, and Llama Models catalogs"
fi

if AI_LAUNCHER="$ai_copilots" \
   AI_RUNTIME="$ai_runtime_module" \
   /usr/bin/python3 - <<'PY'
from collections import Counter
import os
from pathlib import Path
import re
import shlex

launcher = Path(os.environ["AI_LAUNCHER"]).read_text(encoding="utf-8")
runtime = Path(os.environ["AI_RUNTIME"]).read_text(encoding="utf-8")

assert "labwc-fuzzel" not in launcher
assert "LABWC_FUZZEL" not in launcher
assert 'exec labwc-terminal -e "$TERMINAL_LAUNCHER" --terminal' in launcher
assert 'labwc-ai-copilots-action --run "$@"' in launcher
assert "fzf \\" in launcher
assert "/dev/tty" in launcher


def decode_case_pattern(pattern):
    labels = []
    for part in pattern.split("|"):
        value = part.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value not in ("", "← Back", "Exit", "*"):
            labels.append(value)
    return labels


catalog_body = re.search(
    r"^catalog\(\) \{\n(.*?)(?=^\}\n\ncodex_prompt_action\(\))",
    launcher,
    re.MULTILINE | re.DOTALL,
)
assert catalog_body is not None
catalogs = {
    name: tuple(body.splitlines())
    for name, body in re.findall(
        r"^\s{4}([a-z0-9-]+)\)\n\s+cat <<'EOF'\n(.*?)\nEOF\n\s+;;",
        catalog_body.group(1),
        re.MULTILINE | re.DOTALL,
    )
}
assert len(catalogs) == 29
assert sum(len(entries) for entries in catalogs.values()) == 218

functions = {
    name: body
    for name, body in re.findall(
        r"^([a-z][a-z0-9_]*)\(\) \{\n(.*?)(?=^\}\n)",
        launcher,
        re.MULTILINE | re.DOTALL,
    )
}
consumers = Counter(
    re.findall(r"choose_catalog[^\n]*\s([a-z0-9-]+)\)", launcher)
)
assert set(consumers) == set(catalogs)
assert all(count == 1 for count in consumers.values())

catalog_handlers = {}
for function_name, body in functions.items():
    selected = re.findall(r"choose_catalog[^\n]*\s([a-z0-9-]+)\)", body)
    if not selected:
        continue
    assert len(selected) == 1
    case_body = re.search(
        r'case "\$action" in\n(.*?)^\s{4}esac',
        body,
        re.MULTILINE | re.DOTALL,
    )
    assert case_body is not None
    labels = []
    for pattern in re.findall(r"^ {6}(\S.*?)\)", case_body.group(1), re.MULTILINE):
        labels.extend(decode_case_pattern(pattern))
    catalog_handlers[selected[0]] = tuple(labels)

root_loop = launcher.rsplit("\nwhile :; do\n", 1)[1]
root_case = re.search(
    r'case "\$category" in\n(.*?)^\s{2}esac',
    root_loop,
    re.MULTILINE | re.DOTALL,
)
assert root_case is not None
root_labels = []
for pattern in re.findall(r"^ {4}(\S.*?)\)", root_case.group(1), re.MULTILINE):
    root_labels.extend(decode_case_pattern(pattern))
catalog_handlers["root"] = tuple(root_labels)

assert set(catalog_handlers) == set(catalogs)
for catalog_name, entries in catalogs.items():
    assert Counter(entries) == Counter(catalog_handlers[catalog_name]), catalog_name

argument_block = re.search(
    r"my %ACTION_ARGUMENTS = \((.*?)\n\);",
    runtime,
    re.DOTALL,
)
assert argument_block is not None
declared = {
    name: (int(minimum), int(maximum))
    for name, minimum, maximum in re.findall(
        r"'([^']+)'\s*=>\s*\[(\d+),\s*(\d+)\]",
        argument_block.group(1),
    )
}

logical_lines = []
buffer = ""
start = 0
for line_number, physical in enumerate(launcher.splitlines(), 1):
    if not buffer:
        start = line_number
    if physical.rstrip().endswith("\\"):
        buffer += physical.rstrip()[:-1] + " "
    else:
        buffer += physical
        logical_lines.append((start, buffer))
        buffer = ""

calls = []
for line_number, line in logical_lines:
    if "run_action" not in line or re.search(r"\brun_action\s*\(\s*\)", line):
        continue
    lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    tokens = list(lexer)
    for index, token in enumerate(tokens):
        if token != "run_action" or index + 1 >= len(tokens):
            continue
        action = tokens[index + 1]
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", action):
            continue
        arguments = []
        for argument in tokens[index + 2 :]:
            if argument in {";", ";;", "&&", "||", "|", "&", ")", "}", "()"}:
                break
            arguments.append(argument)
        calls.append((line_number, action, arguments))

assert len(declared) == 47
assert len(calls) == 174
assert {action for _, action, _ in calls} == set(declared)
for line_number, action, arguments in calls:
    minimum, maximum = declared[action]
    assert minimum <= len(arguments) <= maximum, (line_number, action, arguments)

for interface, argument_count in (
    ("--list-model-names", 2),
    ("--resolve-model-name", 3),
    ("--list-download-models", 2),
    ("--resolve-download-model", 3),
):
    assert interface in launcher
    assert re.search(
        rf"@argv == {argument_count} && \$argv\[0\] eq '{re.escape(interface)}'",
        runtime,
    )
for compatibility_interface in (
    "--list-models",
    "--list-favorite-models",
    "--list-whisper-models",
):
    assert re.search(
        rf"@argv == 1 && \$argv\[0\] eq '{re.escape(compatibility_interface)}'",
        runtime,
    )


def sub_body(name):
    match = re.search(
        rf"^sub {re.escape(name)} \{{\n(.*?)(?=^sub |\Z)",
        runtime,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None
    return match.group(1)


for action, diagnostic_sub in (
    ("codex-diagnostic", "_codex_diagnostic"),
    ("llama-diagnostic", "_llama_diagnostic"),
    ("whisper-diagnostic", "_whisper_diagnostic"),
):
    emitted = {
        arguments[0]
        for _, candidate, arguments in calls
        if candidate == action and arguments and "$" not in arguments[0]
    }
    accepted = set(re.findall(r"\$kind eq '([^']+)'", sub_body(diagnostic_sub)))
    assert emitted == accepted, action

fixed_values = {
    "llama-open-model-search": {
        "search",
        "recommended",
        "coding",
        "reasoning",
        "small-fast",
        "vision",
        "embedding",
        "recent",
    },
    "llama-favorite": {"add", "remove"},
    "llama-memory": {"enable", "disable", "clear"},
    "llama-set-preset": {
        "coding",
        "code-review",
        "security-review",
        "deep-reasoning",
        "concise-summary",
        "brainstorm",
        "shell-safety",
        "clear",
    },
    "llama-set-runtime": {"context", "threads", "batch", "gpu-layers"},
    "llama-performance-preset": {"balanced", "low-memory", "high-context"},
    "whisper-control": {"start", "stop", "toggle"},
    "whisper-dictation": {"toggle"},
    "whisper-set-language": {"auto", "en", "sv", "de", "fr", "es"},
    "whisper-set-output": {"file", "clipboard", "both"},
    "whisper-set-post-processing": {"raw", "normalize"},
    "whisper-open": {"recording-folder", "transcript-folder", "audio-control"},
    "whisper-audio": {"toggle-mute", "mute", "unmute"},
}
for action, accepted in fixed_values.items():
    emitted = {
        arguments[0]
        for _, candidate, arguments in calls
        if candidate == action and arguments and "$" not in arguments[0]
    }
    assert emitted == accepted, action

reasoning = re.search(
    r"printf '%s\\n' ([a-z ]+) \|\n\s+choose_menu_input \"Codex reasoning effort\"",
    launcher,
)
assert reasoning is not None
assert set(reasoning.group(1).split()) == {
    "default",
    "low",
    "medium",
    "high",
    "xhigh",
}

model_info_fields = set(
    re.findall(
        r"run_model_info "
        r"(details|license|architecture|parameter-count|quantization|size|context-length|location)",
        launcher,
    )
)
model_info_fields.update(
    arguments[0]
    for _, action, arguments in calls
    if action == "llama-model-info" and arguments and "$" not in arguments[0]
)
assert model_info_fields == {
    "details",
    "license",
    "architecture",
    "parameter-count",
    "quantization",
    "size",
    "context-length",
    "location",
}
PY
then
  pass "every AI catalog entry, action arity, diagnostic kind, and fixed selector reaches its backend contract"
else
  fail "AI catalog and backend contracts remain in exact one-to-one parity"
fi

if PERL5LIB="$digital_assets_perl_compat:$ai_copilots_module_root" \
   /usr/bin/perl -MAICopilots::Runtime -e '
     package TestState;
     sub document { return $_[0]->{document}; }
     sub mutate {
         my ($self, $callback) = @_;
         $callback->($self->{document});
         return $self->{document};
     }

     package TestModels;
     sub active_model { return "/pool/cache/llama/models/test.Q4_K_M.gguf"; }

     package main;
     no warnings "redefine";
     my $state = bless {
         document => {
             llama => {
                 runtime => {
                     context               => 0,
                     threads               => 0,
                     batch                 => 0,
                     gpu_layers            => 0,
                     gpu_layers_overridden => 0,
                 },
             },
         },
     }, "TestState";
     my $models = bless {}, "TestModels";
     local *AICopilots::Runtime::state = sub { return $state; };
     local *AICopilots::Runtime::models = sub { return $models; };
     local $ENV{DBUS_SESSION_BUS_ADDRESS} = q{};
     my $runtime = bless {}, "AICopilots::Runtime";

     $runtime->_llama_action("llama-set-runtime", "gpu-layers", "0");
     my %environment = $runtime->_llama_environment();
     die "explicit zero GPU layers were not exported\n"
         if !$state->{document}{llama}{runtime}{gpu_layers_overridden}
         || !exists($environment{LLAMA_ARG_N_GPU_LAYERS})
         || $environment{LLAMA_ARG_N_GPU_LAYERS} != 0;

     $runtime->_llama_action("llama-performance-preset", "balanced");
     %environment = $runtime->_llama_environment();
     die "balanced preset did not disable GPU layers\n"
         if !$state->{document}{llama}{runtime}{gpu_layers_overridden}
         || !exists($environment{LLAMA_ARG_N_GPU_LAYERS})
         || $environment{LLAMA_ARG_N_GPU_LAYERS} != 0;

     $runtime->_llama_action("llama-reset-runtime");
     %environment = $runtime->_llama_environment();
     die "runtime reset retained the GPU-layer override\n"
         if $state->{document}{llama}{runtime}{gpu_layers_overridden}
         || exists($environment{LLAMA_ARG_N_GPU_LAYERS});
   ' >/dev/null 2>&1
then
  pass "Llama GPU-layer zero, performance presets, and reset preserve explicit override semantics"
else
  fail "Llama GPU-layer zero remains distinguishable from the managed default"
fi

ai_modules_ok=true
for ai_module in "$ai_copilots_module_root"/AICopilots/*.pm; do
  PERL5LIB="$digital_assets_perl_compat:$ai_copilots_module_root" \
    /usr/bin/perl -c "$ai_module" >/dev/null 2>&1 ||
    ai_modules_ok=false
done
python_cache="$TMP_DIR/python-cache"
mkdir -p "$python_cache"
gguf_model="$TMP_DIR/test.Q4_K_M.gguf"
TEST_MODEL="$gguf_model" /usr/bin/python3 - <<'PY'
import os
import struct
from pathlib import Path

path = Path(os.environ["TEST_MODEL"])

def string(value):
    raw = value.encode("utf-8")
    return struct.pack("<Q", len(raw)) + raw

payload = bytearray(b"GGUF")
payload += struct.pack("<IQQ", 3, 1, 4)
payload += string("general.architecture") + struct.pack("<I", 8) + string("llama")
payload += string("llama.context_length") + struct.pack("<II", 4, 8192)
payload += string("general.license") + struct.pack("<I", 8) + string("apache-2.0")
payload += string("general.file_type") + struct.pack("<II", 4, 15)
payload += string("weight")
payload += struct.pack("<IQQIQ", 2, 2, 3, 12, 0)
path.write_bytes(payload)
path.chmod(0o600)
PY

PYTHONPATH="$ai_copilots_python_root" \
TEST_MODEL="$gguf_model" \
  /usr/bin/python3 - <<'PY' >"$TMP_DIR/gguf.details"
import os
from pathlib import Path

from labwc_ai_copilots.gguf import _inspect_gguf_file

info = _inspect_gguf_file(Path(os.environ["TEST_MODEL"]))
assert info.architecture == "llama"
assert info.context_length == 8192
assert info.parameter_count == 6
assert info.tensor_types == {"Q4_K": 1}
assert info.license_text == "apache-2.0"
print("bounded-parser-ok")
PY

model_request_valid() {
  PERL5LIB="$digital_assets_perl_compat:$ai_copilots_module_root" \
    /usr/bin/perl -MAICopilots::ModelInstallRoot -e '
      my $ok = eval {
          AICopilots::ModelInstallRoot::_validate_install_request(@ARGV);
          1;
      };
      if (!$ok) {
          print STDERR $@;
          exit 1;
      }
      exit 0;
    ' -- "$@"
}

model_request_rejected() {
  if model_request_valid "$@" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

model_argv_rejected() {
  if PERL5LIB="$digital_assets_perl_compat:$ai_copilots_module_root" \
       /usr/bin/perl -MAICopilots::ModelInstallRoot -e '
         no warnings "redefine";
         local *AICopilots::ModelInstallRoot::_require_privileged_invoker =
             sub { return 1; };
         my $self = bless {}, "AICopilots::ModelInstallRoot";
         my $ok = eval {
             $self->run(@ARGV);
             1;
         };
         exit($ok ? 0 : 1);
       ' -- "$@" >/dev/null 2>&1
  then
    return 1
  fi
  return 0
}

catalog_shape_valid() {
  catalog_file=$1
  expected_models=$2

  /usr/bin/awk -F '\t' -v expected_models="$expected_models" '
    BEGIN {
      expected_header = "id\tdisplay_name\tlanguage\tparameters\tfile_mib\tmin_ram_gib\trecommended_ram_gib\tcpu_cores\tweights\trepository\trevision\tremote_filename\tlocal_filename\tnotes"
    }
    NR == 1 {
      if ($0 != expected_header || NF != 14) {
        exit 1
      }
      next
    }
    NF != 14 {
      exit 1
    }
    END {
      if (NR != expected_models + 1) {
        exit 1
      }
    }
  ' "$catalog_file"
}

catalog_staging_valid() {
  /usr/bin/awk '
    /^desktop_stage_ai_copilots_catalogs\(\) \{/ {
      in_catalog_staging = 1
      next
    }
    in_catalog_staging && /llama-models[.]tsv/ {
      llama_paths++
    }
    in_catalog_staging && /whisper-models[.]tsv/ {
      whisper_paths++
    }
    in_catalog_staging && /^[[:space:]]+0644$/ {
      catalog_modes++
    }
    in_catalog_staging && /^}/ {
      completed = 1
      if (llama_paths == 2 && whisper_paths == 2 && catalog_modes == 2) {
        exit 0
      }
      exit 1
    }
    END {
      if (!completed) {
        exit 1
      }
    }
  ' "$components"
}

valid_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
valid_llama_url=https://huggingface.co/example/models/resolve/main/test.Q4_K_M.gguf
valid_whisper_url=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
forbidden_home_model_pattern='\.local/share/labwc-ai-copilots/'\
'(llama|whisper)/models|user_model_'\
'directory'
if [ "$ai_modules_ok" = true ] &&
   /bin/sh -n "$ai_copilots" &&
   /bin/sh -n "$ai_copilots_action" &&
   /bin/sh -n "$ai_model_install_root" &&
   PYTHONPYCACHEPREFIX="$python_cache" \
     /usr/bin/python3 -m py_compile \
       "$ai_copilots_python_root/labwc_ai_copilots/__init__.py" \
       "$ai_copilots_python_root/labwc_ai_copilots/cli.py" \
       "$ai_copilots_python_root/labwc_ai_copilots/gguf.py" \
       "$ai_model_info" &&
   grep -Fqx 'bounded-parser-ok' "$TMP_DIR/gguf.details" &&
   model_request_valid \
     llama "$valid_llama_url" test.Q4_K_M.gguf "$valid_sha256" 1048576 &&
   model_request_valid \
     whisper "$valid_whisper_url" ggml-small.en.bin "$valid_sha256" 1048576 &&
   model_request_rejected \
     other "$valid_llama_url" test.Q4_K_M.gguf "$valid_sha256" 1048576 &&
   model_request_rejected \
     llama http://huggingface.co/example/test.gguf test.gguf "$valid_sha256" 1048576 &&
   model_request_rejected \
     llama https://user:password@huggingface.co/example/test.gguf test.gguf "$valid_sha256" 1048576 &&
   model_request_rejected \
     llama "$valid_llama_url" ../test.gguf "$valid_sha256" 1048576 &&
   model_request_rejected \
     llama "$valid_llama_url" ggml-small.en.bin "$valid_sha256" 1048576 &&
   model_request_rejected \
     llama "$valid_llama_url" test.gguf invalid 1048576 &&
   model_request_rejected \
     llama "$valid_llama_url" test.gguf "$valid_sha256" 1048575 &&
   model_argv_rejected \
     install llama "$valid_llama_url" test.Q4_K_M.gguf "$valid_sha256" 1048576 /tmp/forbidden &&
   model_argv_rejected install-catalog llama llama32-1b-q4-k-m extra &&
   model_argv_rejected prune llama /tmp/forbidden &&
   [ -r "$ai_model_catalog_module" ] &&
   [ -r "$ai_llama_catalog" ] &&
   [ -r "$ai_whisper_catalog" ] &&
   catalog_shape_valid "$ai_llama_catalog" 48 &&
   catalog_shape_valid "$ai_whisper_catalog" 40 &&
   grep -Fq 'AICopilots/ModelCatalog.pm' "$components" &&
   grep -Fq 'desktop_stage_ai_copilots_catalogs' "$components" &&
   catalog_staging_valid &&
   grep -Fq '($directory_stat[2] & 07777) == 0755' "$ai_model_catalog_module" &&
   grep -Fq '($stat[2] & 07777) == 0644' "$ai_model_catalog_module" &&
   grep -Fq '$stat[7] <= 262_144' "$ai_model_catalog_module" &&
   grep -Fq '@lines >= 40 && @lines <= 50' "$ai_model_catalog_module" &&
   grep -Fq '@values == @CATALOG_FIELDS' "$ai_model_catalog_module" &&
   grep -Fq '/usr/bin/env -i' "$ai_copilots_action" &&
   grep -Fq "'--disable'," "$ai_model_install_module" &&
   grep -Fq "'--max-redirs', '3'," "$ai_model_install_module" &&
   grep -Fq "'--proto-redir', '=https'," "$ai_model_install_module" &&
   grep -Fq "'--retry-max-time', '30'," "$ai_model_install_module" &&
   grep -Fq "'--connect-timeout', '10'," "$ai_model_install_module" &&
   grep -Fq "'--max-time', '60'," "$ai_model_install_module" &&
   grep -Fq "'--max-filesize', \"\$maximum_bytes\"," "$ai_model_install_module" &&
   grep -Fq 'my $maximum_bytes = 4_194_304;' "$ai_model_install_module" &&
   grep -Fq 'length($content) > $maximum_bytes' "$ai_model_install_module" &&
   grep -Fq '@matches == 1' "$ai_model_install_module" &&
   grep -Fq 'ref($match->{lfs}) eq '\''HASH'\''' "$ai_model_install_module" &&
   grep -Fq '$metadata->{sha} eq $entry->{revision}' "$ai_model_install_module" &&
   grep -Fq "default => sub { '/pool/cache/llama/models' }" "$ai_model_store_module" &&
   grep -Fq "default => sub { '/pool/cache/whisper/models' }" "$ai_model_store_module" &&
   grep -Fq "default => sub { '/pool/cache/llama/models' }" "$ai_model_install_module" &&
   grep -Fq "default => sub { '/pool/cache/whisper/models' }" "$ai_model_install_module" &&
   grep -Fq "getgrnam('devops')" "$ai_model_store_module" &&
   grep -Fq "getgrnam('devops')" "$ai_model_install_module" &&
   grep -Fq '($stat[2] & 07777) == 02750' "$ai_model_store_module" &&
   grep -Fq '($stat[2] & 07777) == 02750' "$ai_model_install_module" &&
   grep -Fq '($stat[2] & 07777) == 0640' "$ai_model_store_module" &&
   grep -Fq 'chown 0, _devops_gid(), $partial' "$ai_model_install_module" &&
   grep -Fq 'chmod 0640, $partial' "$ai_model_install_module" &&
   grep -Fq 'grp.getgrnam("devops").gr_gid' "$ai_gguf_module" &&
   grep -Fq '_LLAMA_MODEL_ROOT: Final[Path] = Path("/pool/cache/llama/models")' "$ai_gguf_module" &&
   grep -Fq 'stat_result.st_mode & 0o777 != 0o640' "$ai_gguf_module" &&
   grep -Fq 'LLAMA_MODEL_DIR must remain /pool/cache/llama/models' "$llama_late" &&
   grep -Fq 'WHISPER_MODEL_DIR must remain /pool/cache/whisper/models' "$whisper_late" &&
   grep -Fq "'--model', \$self->_whisper_model()," "$ai_runtime_module" &&
   grep -Fq 'return $self->models()->validate_whisper_model($selected)' "$ai_runtime_module" &&
   grep -Fq "return \$self->_configured_whisper_model();" "$ai_runtime_module" &&
   grep -Fq "'llama-start-server'" "$ai_runtime_module" &&
   grep -Fq "'llama-stop-server'" "$ai_runtime_module" &&
   grep -Fq "'start'," "$ai_runtime_module" &&
   grep -Fq "'stop'," "$ai_runtime_module" &&
   grep -Fq "'llama-server.service'," "$ai_runtime_module" &&
   grep -Fq 'sub run_llama_server {' "$ai_runtime_module" &&
   ! grep -R -E "$forbidden_home_model_pattern" \
     "$ai_copilots" \
     "$ai_copilots_module_root" \
     "$ai_copilots_python_root/labwc_ai_copilots" \
     "$components" \
     "$apparmor_profile" \
     "$llama_late" \
     "$whisper_late" &&
   grep -Fq "system { \$command[0] } @command" "$ai_copilots_module_root/AICopilots/Runtime.pm" &&
   ! grep -Fq 'system "' "$ai_copilots_module_root/AICopilots/Runtime.pm" &&
   ! grep -Fq "system '" "$ai_copilots_module_root/AICopilots/Runtime.pm" &&
   ! grep -Fq '`' "$ai_copilots_module_root/AICopilots/Runtime.pm"; then
  pass "AI actions use sanitized Moo/MooX and bounded GGUF, state, subprocess, and HTTPS contracts"
else
  fail "AI actions use sanitized Moo/MooX and bounded GGUF, state, subprocess, and HTTPS contracts"
fi

digital_assets_catalog_ok=true
for digital_assets_category in 'DOCX Actions' 'PDF Actions' 'Image Actions'; do
  grep -Fq "$digital_assets_category" "$digital_assets" ||
    digital_assets_catalog_ok=false
done
while IFS= read -r digital_assets_entry; do
  [ -n "$digital_assets_entry" ] || continue
  grep -Fq "$digital_assets_entry" "$digital_assets_catalog" ||
    digital_assets_catalog_ok=false
done <<'EOF'
Convert DOCX to PDF
Convert DOCX to Markdown
Convert DOCX to Plain Text
Convert DOCX to HTML
Convert PDF to PNG
Convert PDF to JPEG
Convert PDF to DOCX
Convert PDF to Plain Text
Convert Markdown to PDF
Extract Images from PDF
Merge Multiple PDF's
Split PDF (Burst to Pages)
Extract Specific Pages
Remove Specific Pages
Rotate Pages
Edit PDF Content
Edit PDF Bookmarks
Edit Hyperlinks and Typos
Clean / Repair Corrupted PDF
Inspect PDF Structure
Encrypt / Password Protect
Decrypt / Remove Password
Linearize (Optimize size for Web)
Add Page Numbers
Add Text Watermark
Extract TOC / Bookmarks
Convert Any Image to PNG
Convert Any Image to JPEG
Convert Image to WebP
Resize Image
Crop Image
Rotate Image
Flip (Horizontal)
Flip (Vertical)
Convert to Grayscale
Compress / Optimize PNG
Compress / Optimize JPEG
Create GIF from Images
Read Metadata
Edit Metadata
Remove All Metadata
EOF

digital_assets_catalog_cli_ok=false
if PERL5LIB="$digital_assets_perl_compat:$digital_assets_module_root" \
   /usr/bin/perl -MDigitalAssets::CLI \
     -e 'exit DigitalAssets::CLI->run(qw(--menu-catalog))' \
     >"$TMP_DIR/digital-assets-menu-catalog" 2>&1 &&
   grep -Fq 'docx-to-pdf' "$TMP_DIR/digital-assets-menu-catalog" &&
   grep -Fq 'pdf-to-png' "$TMP_DIR/digital-assets-menu-catalog"; then
  digital_assets_catalog_cli_ok=true
fi

if [ "$digital_assets_catalog_ok" = true ] &&
   [ "$digital_assets_catalog_cli_ok" = true ] &&
   grep -Fq -- '-I/usr/local/lib/perl5/site_perl/digital-assets' "$digital_assets_action" &&
   grep -Fq -- '-MDigitalAssets::CLI' "$digital_assets_action" &&
   grep -Fq 'exit DigitalAssets::CLI->new()->run(@ARGV)' "$digital_assets_action" &&
   ! grep -Fq 'use DigitalAssets::Runtime;' "$digital_assets_cli" &&
   grep -Fq 'require DigitalAssets::Runtime;' "$digital_assets_cli" &&
   grep -Fq 'my $root = "$documents/Digital-Assets";' "$digital_assets_context" &&
   grep -Fq -- "'--pdf-engine=/usr/local/bin/typst'" "$digital_assets_document" &&
   grep -Fq "'--qdf', '--object-streams=disable'" "$digital_assets_pdf" &&
   grep -Fq "run_timed(\$context->command_path('fix-qdf'), \$qdf)" "$digital_assets_pdf" &&
   grep -Fq "QT_QPA_PLATFORM => 'wayland'" "$digital_assets_pdf" &&
   grep -Fq "[ -n \"\${WAYLAND_DISPLAY:-}\" ]" "$digital_assets" &&
   grep -Fxq 'LABWC_FUZZEL_MANAGED_ICONS=1' "$digital_assets" &&
   grep -Fxq 'create_candidate_list() {' "$digital_assets" &&
   grep -Fxq 'show_no_candidates() {' "$digital_assets" &&
   grep -Fxq 'choose_menu_input() {' "$digital_assets" &&
   ! grep -Fq '|| true' "$digital_assets" &&
   grep -Fq 'No %s files detected in Downloads, Documents, or Desktop' "$digital_assets" &&
   grep -Fq 'show_no_candidates "$asset_kind" "$selection_prompt"' "$digital_assets" &&
   grep -Fq 'rm -f -- "$candidate_path"' "$digital_assets" &&
   grep -Fq "my \$bookmark_json = \$context->work_directory() . '/bookmarks.json';" "$digital_assets_pdf" &&
   grep -Fq "command_path('nano'), \$bookmark_json" "$digital_assets_pdf" &&
   grep -Fq "'bookmarks', 'import'" "$digital_assets_pdf" &&
   grep -Fq 'pymupdf4llm.to_markdown' "$digital_assets_pdf"; then
  pass "Digital Assets exposes the complete document, PDF, and image action catalog with native-Wayland tool paths"
else
  fail "Digital Assets exposes the complete document, PDF, and image action catalog with native-Wayland tool paths"
fi

digital_assets_cancel_bin="$TMP_DIR/digital-assets-cancel-bin"
digital_assets_cancel_helper="$TMP_DIR/digital-assets-cancel-helper.sh"
digital_assets_cancel_stdout="$TMP_DIR/digital-assets-cancel.stdout"
digital_assets_cancel_stderr="$TMP_DIR/digital-assets-cancel.stderr"
digital_assets_failure_stdout="$TMP_DIR/digital-assets-failure.stdout"
digital_assets_failure_stderr="$TMP_DIR/digital-assets-failure.stderr"
mkdir -p "$digital_assets_cancel_bin"
cat >"$digital_assets_cancel_bin/labwc-fuzzel" <<'EOF'
#!/bin/sh
exit "${FUZZEL_STATUS:?}"
EOF
chmod 0755 "$digital_assets_cancel_bin/labwc-fuzzel"
awk '
  /^require_command\(\) \{/ { exit }
  { print }
' "$digital_assets" >"$digital_assets_cancel_helper"
cat >>"$digital_assets_cancel_helper" <<'EOF'
choose_menu_input 'Digital Assets'
EOF
chmod 0700 "$digital_assets_cancel_helper"

if PATH="$digital_assets_cancel_bin:/usr/bin:/bin" \
   HOME="$TMP_DIR/home" \
   FUZZEL_STATUS=1 \
   /bin/sh "$digital_assets_cancel_helper" \
     >"$digital_assets_cancel_stdout" 2>"$digital_assets_cancel_stderr" &&
   [ ! -s "$digital_assets_cancel_stdout" ] &&
   [ ! -s "$digital_assets_cancel_stderr" ] &&
   ! PATH="$digital_assets_cancel_bin:/usr/bin:/bin" \
     HOME="$TMP_DIR/home" \
     FUZZEL_STATUS=2 \
     /bin/sh "$digital_assets_cancel_helper" \
       >"$digital_assets_failure_stdout" 2>"$digital_assets_failure_stderr" &&
   grep -Fq 'unable to open the Digital Assets menu (status 2)' \
     "$digital_assets_failure_stderr"; then
  pass "Digital Assets treats Fuzzel cancellation as Back while surfacing launcher failures"
else
  fail "Digital Assets treats Fuzzel cancellation as Back while surfacing launcher failures"
fi

if awk '
  /label[[:space:]]*=>.*Edit PDF Content/ {
    content_found = 1
    next
  }
  content_found && /label[[:space:]]*=>/ {
    bookmarks_follows = index($0, "Edit PDF Bookmarks") > 0
    exit
  }
  END { exit !(content_found && bookmarks_follows) }
' "$digital_assets_catalog"; then
  pass "Edit PDF Bookmarks is placed directly below Edit PDF Content"
else
  fail "Edit PDF Bookmarks is placed directly below Edit PDF Content"
fi

routes_ok=true
for route in \
  'labwc-podman-menu' \
  'labwc-remote-desktop' \
  'labwc-maintenance-menu security' \
  'labwc-digital-assets' \
  'labwc-users-groups-menu' \
  'labwc-network-scan-menu' \
  'labwc-network-control-menu connections' \
  'labwc-network-control-menu vpn' \
  'labwc-network-control-menu wireguard' \
  'labwc-network-control-menu dns' \
  'labwc-maintenance-menu system' \
  'labwc-display-configuration' \
  'labwc-output-refresh' \
  'labwc-power-settings' \
  'labwc-keyboard-layout' \
  'pavucontrol' \
  'systemctl --user --no-block restart crystal-dock.service' \
  'labwc-adb-menu' \
  'labwc-maintenance-menu recovery' \
  'labwc-external-drives' \
  'labwc-bluetooth menu' \
  'labwc-brightness-control' \
  'labwc-ai-copilots'
do
  grep -Fq "run_command ${route}" "$computer_management" ||
    routes_ok=false
done
hardware_display_removed=true
if sed -n '/^hardware_peripherals_menu() {$/,/^}$/p' "$computer_management" |
     grep -Fq 'Display Configuration'
then
  hardware_display_removed=false
fi
if [ "$routes_ok" = true ] &&
   [ "$hardware_display_removed" = true ] &&
   grep -q '^run_firewall_menu() ($' "$maintenance_menu" &&
   grep -q 'labwc-firewall-menu' "$maintenance_menu"; then
  pass "Computer Management preserves every delegated launcher action catalog"
else
  fail "Computer Management preserves every delegated launcher action catalog"
fi

if grep -q '<keybind key="W-m">' "$labwc_rc" &&
   grep -q '<keybind key="C-A-m">' "$labwc_rc" &&
   grep -q 'command="labwc-computer-management"' "$labwc_rc" &&
   ! grep -q '<keybind key="C-W-m">' "$labwc_rc" &&
   ! grep -q '<keybind key="C-A-S-m">' "$labwc_rc" &&
   ! grep -Eq '<keybind key="C-W-[anpr]">' "$labwc_rc" &&
   grep -q 'label="Computer Management"' "$labwc_menu" &&
   grep -q 'command="labwc-computer-management"' "$labwc_menu"; then
  pass "Super-M, Ctrl-Alt-M, and the Labwc menu use the single management entrypoint"
else
  fail "Super-M, Ctrl-Alt-M, and the Labwc menu use the single management entrypoint"
fi

if grep -q '^Name=Computer Management$' "$computer_desktop" &&
   grep -q '^TryExec=/usr/local/bin/labwc-computer-management$' "$computer_desktop" &&
   grep -q '^Exec=/usr/local/bin/labwc-computer-management$' "$computer_desktop" &&
   grep -q '^Categories=System;$' "$computer_desktop" &&
   grep -q '^Keywords=.*Users;.*Groups;.*Endpoint Security;.*Network;.*VPN;.*WireGuard;.*DNS;.*Firewall;.*nftables;.*System;.*Backup;.*Hardware;' "$computer_desktop" &&
   grep -q '^Keywords=.*AI;.*Copilots;.*Codex;.*Llama;.*Whisper;.*GGUF;.*Transcription;' "$computer_desktop" &&
   grep -q '^NoDisplay=true$' "$rdp_desktop" &&
   grep -q 'labwc-computer-management /usr/local/bin/labwc-computer-management 0755' "$components" &&
   grep -q 'labwc-ai-copilots /usr/local/bin/labwc-ai-copilots 0755' "$components" &&
   grep -q 'labwc-ai-copilots-action /usr/local/bin/labwc-ai-copilots-action 0755' "$components" &&
   grep -q 'labwc-ai-llama-server /usr/local/libexec/labwc-ai-llama-server 0755' "$components" &&
   grep -q 'labwc-ai-model-install-root /usr/local/libexec/labwc-ai-model-install-root 0755' "$components" &&
   grep -q 'labwc-ai-model-info /usr/local/libexec/labwc-ai-model-info 0755' "$components" &&
   grep -Fq 'AICopilots/ModelCatalog.pm' "$components" &&
   grep -Fq 'desktop_stage_ai_copilots_catalogs' "$components" &&
   grep -Fq 'usr/local/share/labwc-ai-copilots/llama-models.tsv' "$components" &&
   grep -Fq 'usr/local/share/labwc-ai-copilots/whisper-models.tsv' "$components" &&
   grep -q 'llama-server.service /etc/skel/.config/systemd/user/llama-server.service 0644' "$components" &&
   ! grep -q 'llama-server.service /etc/systemd/user/llama-server.service' "$components" &&
   ! grep -Eq 'desktop_enable_user_unit[^[:cntrl:]]*llama-server[.]service' "$components" &&
   grep -q 'labwc-display-configuration /usr/local/bin/labwc-display-configuration 0755' "$components" &&
   grep -q 'labwc-digital-assets /usr/local/bin/labwc-digital-assets 0755' "$components" &&
   grep -q 'labwc-digital-assets-action /usr/local/bin/labwc-digital-assets-action 0755' "$components" &&
   grep -q 'computer-management.desktop /usr/share/applications/computer-management.desktop 0644' "$components" &&
   grep -q '/usr/local/bin/labwc-computer-management' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-ai-copilots' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-ai-copilots-action' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-ai-llama-server' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-ai-model-install-root' "$desktop_verify" &&
   grep -q '/usr/local/libexec/labwc-ai-model-info' "$desktop_verify" &&
   grep -q '/etc/skel/.config/systemd/user/llama-server.service' "$desktop_verify" &&
   grep -q '"$account_home/.config/systemd/user/llama-server.service"' "$desktop_verify" &&
   grep -q 'require_absent "$account_home/.config/systemd/user/labwc-session.target.wants/llama-server.service"' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-display-configuration' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-digital-assets' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-digital-assets-action' "$desktop_verify" &&
   grep -q '/usr/share/applications/computer-management.desktop' "$desktop_verify" &&
   grep -q 'desktop-file-validate' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-network-scan-menu' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-ai-copilots' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-ai-copilots-action' "$firstboot_validation" &&
   grep -q '/usr/local/libexec/labwc-ai-llama-server' "$firstboot_validation" &&
   grep -q '/usr/local/libexec/labwc-ai-model-install-root' "$firstboot_validation" &&
   grep -q '/usr/local/libexec/labwc-ai-model-info' "$firstboot_validation" &&
   grep -q '/etc/skel/.config/systemd/user/llama-server.service' "$firstboot_validation" &&
   grep -q 'desktop-user-unit-llama-server.service-enable-absent' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-display-configuration' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-digital-assets' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-digital-assets-action' "$firstboot_validation" &&
   grep -q '/usr/local/bin/labwc-keyboard-layout' "$firstboot_validation" &&
   grep -q '/etc/skel/.config/systemd/user/crystal-dock.service' "$firstboot_validation" &&
   grep -Fxq 'GDK_BACKEND=wayland' "$display_configuration" &&
   grep -Fxq 'GTK_CSD=0' "$display_configuration" &&
   grep -Fxq 'exec /usr/bin/wdisplays "$@"' "$display_configuration" &&
   ! grep -Fq 'run_command wdisplays' "$computer_management" &&
   [ -x "$ai_llama_server" ] &&
   /bin/sh -n "$ai_llama_server" &&
   grep -Fq 'exec /usr/bin/env -i' "$ai_llama_server" &&
   grep -Fq 'require_wayland => 0' "$ai_llama_server" &&
   [ -r "$llama_server_unit" ] &&
   grep -Fqx 'ExecStart=/usr/local/libexec/labwc-ai-llama-server' "$llama_server_unit" &&
   grep -Fqx 'Requisite=labwc-session.target' "$llama_server_unit" &&
   grep -Fqx 'PartOf=labwc-session.target' "$llama_server_unit" &&
   grep -Fqx 'RestrictAddressFamilies=AF_UNIX AF_INET AF_NETLINK' "$llama_server_unit" &&
   ! grep -Fq '[Install]' "$llama_server_unit" &&
   grep -Fq 'profile managed-labwc-ai-llama-server /usr/local/libexec/labwc-ai-llama-server' "$apparmor_profile" &&
   grep -q 'desktop-management-launchers' "$firstboot_validation" &&
   { ! command -v desktop-file-validate >/dev/null 2>&1 ||
     desktop-file-validate "$computer_desktop"; }; then
  pass "desktop staging and verification expose one searchable management launcher"
else
  fail "desktop staging and verification expose one searchable management launcher"
fi

bin_dir="$TMP_DIR/bin"
selection_file="$TMP_DIR/selections"
menu_log="$TMP_DIR/menu.log"
menu_invocation_log="$TMP_DIR/menu-invocations.log"
action_log="$TMP_DIR/actions.log"
action_argv_log="$TMP_DIR/action-argv.log"
fzf_argv_log="$TMP_DIR/fzf-argv.log"
tty_input_file="$TMP_DIR/tty-input"
terminal_output="$TMP_DIR/ai-terminal.output"
mkdir -p "$bin_dir"

cat >"$bin_dir/labwc-fuzzel" <<'EOF'
#!/bin/sh
set -eu
menu_prompt=
expect_prompt_value=false
for menu_argument in "$@"; do
  if [ "$expect_prompt_value" = true ]; then
    menu_prompt=$menu_argument
    expect_prompt_value=false
    continue
  fi
  case "$menu_argument" in
    --prompt) expect_prompt_value=true ;;
    --prompt=*) menu_prompt=${menu_argument#--prompt=} ;;
  esac
done
if [ -n "${MENU_INVOCATION_LOG:-}" ]; then
  printf '%s|%s|%s|%s\n' \
    "$menu_prompt" \
    "${LABWC_FUZZEL_MENU_WIDTH_OVERRIDE:-}" \
    "${LABWC_FUZZEL_MENU_LINES_OVERRIDE:-}" \
    "${LABWC_FUZZEL_MENU_FONT_SIZE_OVERRIDE:-}" \
    >>"$MENU_INVOCATION_LOG"
fi
if [ "${REJECT_SYSTEM_CONFIGURATION_OVERRIDES:-0}" = 1 ] &&
   [ "$menu_prompt" = "System Configuration" ] &&
   [ -n "${LABWC_FUZZEL_MENU_WIDTH_OVERRIDE:-}${LABWC_FUZZEL_MENU_LINES_OVERRIDE:-}${LABWC_FUZZEL_MENU_FONT_SIZE_OVERRIDE:-}" ]
then
  exit 2
fi
cat >>"${MENU_LOG:?}"
selection=$(sed -n '1p' "${SELECTION_FILE:?}")
sed '1d' "$SELECTION_FILE" >"${SELECTION_FILE}.next"
mv "${SELECTION_FILE}.next" "$SELECTION_FILE"
case "$selection" in
  '__ESC__') exit 1 ;;
  '__FAIL__') exit 2 ;;
esac
printf '%s\n' "$selection"
EOF
chmod 0755 "$bin_dir/labwc-fuzzel"

cat >"$bin_dir/fzf" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${FZF_ARGV_LOG:?}"
cat >>"${MENU_LOG:?}"
selection=$(sed -n '1p' "${SELECTION_FILE:?}")
sed '1d' "$SELECTION_FILE" >"${SELECTION_FILE}.next"
mv "${SELECTION_FILE}.next" "$SELECTION_FILE"
case "$selection" in
  '__ESC__') exit 130 ;;
  '__FAIL__') exit 2 ;;
esac
printf '%s\n' "$selection"
EOF
chmod 0755 "$bin_dir/fzf"

for helper in \
  labwc-podman-menu \
  labwc-remote-desktop \
  labwc-maintenance-menu \
  labwc-digital-assets \
  labwc-users-groups-menu \
  labwc-network-scan-menu \
  labwc-network-control-menu \
  labwc-firewall-menu \
  labwc-adb-menu \
  labwc-external-drives \
  labwc-bluetooth \
  labwc-brightness-control \
  labwc-output-refresh \
  labwc-power-settings \
  labwc-keyboard-layout \
  labwc-ai-copilots \
  labwc-terminal \
  systemctl \
  labwc-display-configuration \
  pavucontrol
do
  cat >"$bin_dir/$helper" <<EOF
#!/bin/sh
printf '%s' '$helper' >>"\${ACTION_LOG:?}"
[ "\$#" -eq 0 ] || printf ' %s' "\$@" >>"\${ACTION_LOG:?}"
printf '\\n' >>"\${ACTION_LOG:?}"
EOF
  chmod 0755 "$bin_dir/$helper"
done

cat >"$bin_dir/id" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  -u) printf '%s\n' 1000 ;;
  -un) printf '%s\n' desktop-user ;;
  *) exec /usr/bin/id "$@" ;;
esac
EOF
chmod 0755 "$bin_dir/id"

run_launcher_case() {
  expected_action=$1
  shift

  printf '%s\n' "$@" >"$selection_file"
  : >"$menu_log"
  : >"$action_log"
  PATH="$bin_dir:$PATH" \
  LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
  MENU_LOG="$menu_log" \
  SELECTION_FILE="$selection_file" \
  ACTION_LOG="$action_log" \
    /bin/sh "$computer_management"

  actual_action=$(cat "$action_log")
  if [ "$actual_action" != "$expected_action" ]; then
    printf 'expected action: %s\nactual action: %s\n' \
      "$expected_action" "${actual_action:-none}" >&2
    return 1
  fi
}

if run_launcher_case 'labwc-podman-menu' \
     '⮞ Container Management' 'Exit' &&
   run_launcher_case 'labwc-remote-desktop' \
     '⮞ Remote Desktop' 'Exit' &&
   run_launcher_case 'labwc-maintenance-menu security' \
     '⮞ Endpoint Security' 'Exit' &&
   run_launcher_case 'labwc-digital-assets' \
     '⮞ Digital Assets' 'Exit' &&
   run_launcher_case 'labwc-users-groups-menu' \
     '⮞ Users & Groups' 'Exit' &&
   run_launcher_case 'labwc-network-scan-menu' \
     '⮞ Network Management' '⮞ Network Scanning' '← Back' 'Exit' &&
   run_launcher_case 'labwc-network-control-menu connections' \
     '⮞ Network Management' '⮞ Connection Profiles' '← Back' 'Exit' &&
   run_launcher_case 'labwc-network-control-menu vpn' \
     '⮞ Network Management' '⮞ VPN Connections' '← Back' 'Exit' &&
   run_launcher_case 'labwc-network-control-menu wireguard' \
     '⮞ Network Management' '⮞ WireGuard Connections' '← Back' 'Exit' &&
   run_launcher_case 'labwc-network-control-menu dns' \
     '⮞ Network Management' '⮞ DNS Configuration' '← Back' 'Exit' &&
   run_launcher_case 'labwc-maintenance-menu system' \
     '⮞ System Configuration' '⮞ System Maintenance & Diagnostics' '← Back' 'Exit' &&
   run_launcher_case 'labwc-display-configuration' \
     '⮞ System Configuration' 'Display Configuration' '← Back' 'Exit' &&
   run_launcher_case 'labwc-output-refresh' \
     '⮞ System Configuration' 'Refresh Display Layout' '← Back' 'Exit' &&
   run_launcher_case 'labwc-power-settings' \
     '⮞ System Configuration' 'Power Profile' '← Back' 'Exit' &&
   run_launcher_case 'labwc-keyboard-layout' \
     '⮞ System Configuration' 'Keyboard Layout' '← Back' 'Exit' &&
   run_launcher_case 'pavucontrol' \
     '⮞ System Configuration' 'Audio Control' '← Back' 'Exit' &&
   run_launcher_case 'systemctl --user --no-block restart crystal-dock.service' \
     '⮞ System Configuration' 'Restart Dock' '← Back' 'Exit' &&
   run_launcher_case 'labwc-adb-menu' \
     '⮞ Phone Management' 'Exit' &&
   run_launcher_case 'labwc-maintenance-menu recovery' \
     '⮞ Backup & Recovery' '⮞ Troubleshooting' '← Back' 'Exit' &&
   run_launcher_case 'labwc-external-drives' \
     '⮞ Backup & Recovery' '⮞ Backup Drives' '← Back' 'Exit' &&
   run_launcher_case 'labwc-external-drives' \
     '⮞ Hardware & Peripherals' '⮞ External Drives' '← Back' 'Exit' &&
   run_launcher_case 'labwc-bluetooth menu' \
     '⮞ Hardware & Peripherals' '⮞ Bluetooth Devices' '← Back' 'Exit' &&
   run_launcher_case 'labwc-brightness-control' \
     '⮞ Hardware & Peripherals' '⮞ Brightness' '← Back' 'Exit' &&
   run_launcher_case 'labwc-ai-copilots' \
     '⮞ AI & Copilots' 'Exit' &&
   run_launcher_case '' \
     '⮞ Network Management' '__ESC__' 'Exit' &&
   [ ! -s "$selection_file" ] &&
   run_launcher_case '' \
     '⮞ System Configuration' '__ESC__' 'Exit' &&
   [ ! -s "$selection_file" ] &&
   grep -q '⮞ Container Management' "$menu_log" &&
   grep -q '⮞ Hardware & Peripherals' "$menu_log" &&
   grep -q '⮞ AI & Copilots' "$menu_log" &&
   /bin/sh -n "$computer_management" &&
   /bin/sh -n "$display_configuration" &&
   /bin/sh -n "$digital_assets" &&
   /bin/sh -n "$digital_assets_action" &&
   /bin/sh -n "$maintenance_menu" &&
   /bin/sh -n "$users_groups_menu" &&
   /bin/sh -n "$firewall_menu"; then
  pass "the unified launcher dispatches every menu action with fixed arguments"
else
  fail "the unified launcher dispatches every menu action with fixed arguments"
fi

printf '%s\n' \
  '⮞ System Configuration' \
  '⮞ System Maintenance & Diagnostics' \
  '← Back' \
  'Exit' >"$selection_file"
: >"$menu_log"
: >"$menu_invocation_log"
: >"$action_log"
system_configuration_case_body=$(
  sed -n '/^    "⮞ System Configuration")$/,/^      ;;$/p' "$computer_management"
)
if PATH="$bin_dir:$PATH" \
   LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
   MENU_LOG="$menu_log" \
   MENU_INVOCATION_LOG="$menu_invocation_log" \
   REJECT_SYSTEM_CONFIGURATION_OVERRIDES=1 \
   SELECTION_FILE="$selection_file" \
   ACTION_LOG="$action_log" \
     /bin/sh "$computer_management" \
       >"$TMP_DIR/system-configuration.stdout" \
       2>"$TMP_DIR/system-configuration.stderr" &&
   [ "$(cat "$action_log")" = "labwc-maintenance-menu system" ] &&
   [ "$(awk -F '|' '$1 == "System Configuration" { count++ } END { print count + 0 }' "$menu_invocation_log")" -eq 2 ] &&
   [ "$(awk -F '|' '$1 == "System Configuration" && ($2 != "" || $3 != "" || $4 != "") { count++ } END { print count + 0 }' "$menu_invocation_log")" -eq 0 ] &&
   [ "$(awk -F '|' '$1 == "System Configuration" { print; exit }' "$menu_invocation_log")" = 'System Configuration|||' ] &&
   grep -Fxq 'System Configuration|||' "$menu_invocation_log" &&
   printf '%s\n' "$system_configuration_case_body" | grep -q '^      run_sized_menu_if_distinct \\$' &&
   printf '%s\n' "$system_configuration_case_body" | grep -q '^        system_configuration_menu$' &&
   ! grep -Fq 'retrying the System Configuration menu without category sizing overrides' \
     "$TMP_DIR/system-configuration.stderr"; then
  pass "System Configuration opens on the first backend invocation without redundant sizing overrides"
else
  fail "System Configuration opens on the first backend invocation without redundant sizing overrides"
fi

llama_download_row=$(
  printf '%-32.32s  %-12.12s  %-7.7s  %9.9s  %7.7s  %7.7s  %7.7s  %-10.10s  %.36s' \
    'Llama 3.2 1B Instruct' \
    'Multilingual' \
    '1B' \
    '808 MiB' \
    '2 GiB' \
    '4 GiB' \
    '4-8' \
    'Q4_K_M' \
    'Balanced small instruction model'
)
whisper_download_row=$(
  printf '%-32.32s  %-12.12s  %-7.7s  %9.9s  %7.7s  %7.7s  %7.7s  %-10.10s  %.36s' \
    'Whisper Small English' \
    'English' \
    '466M' \
    '466 MiB' \
    '2 GiB' \
    '4 GiB' \
    '4-8' \
    'Q8_0' \
    'Fast English transcription model'
)

cat >"$bin_dir/labwc-ai-copilots-action" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  --list-model-names)
    [ "$#" -eq 2 ] || exit 64
    case "$2" in
      llama) printf '%s\n' 'test.Q4_K_M.gguf' ;;
      llama-favorite) : ;;
      whisper) printf '%s\n' 'ggml-small.en.bin' ;;
      *) exit 64 ;;
    esac
    exit 0
    ;;
  --resolve-model-name)
    [ "$#" -eq 3 ] || exit 64
    case "$2:$3" in
      llama:test.Q4_K_M.gguf)
        printf '%s\n' '/pool/cache/llama/models/test.Q4_K_M.gguf'
        ;;
      whisper:ggml-small.en.bin)
        printf '%s\n' '/pool/cache/whisper/models/ggml-small.en.bin'
        ;;
      *)
        exit 64
        ;;
    esac
    exit 0
    ;;
  --list-download-models)
    [ "$#" -eq 2 ] || exit 64
    printf '%s\n' \
      'MODEL                             LANGUAGE      PARAMS        SIZE  RAM MIN  RAM REC      CPU  WEIGHTS     NOTES' \
      '--------------------------------  ------------  -------  ---------  -------  -------  -------  ----------  ------------------------------------'
    case "$2" in
      llama) printf '%s\n' "${LLAMA_DOWNLOAD_ROW:?}" ;;
      whisper) printf '%s\n' "${WHISPER_DOWNLOAD_ROW:?}" ;;
      *) exit 64 ;;
    esac
    exit 0
    ;;
  --resolve-download-model)
    [ "$#" -eq 3 ] || exit 64
    case "$2:$3" in
      "llama:${LLAMA_DOWNLOAD_ROW:?}")
        printf '%s\n' 'llama32-1b-q4-k-m'
        ;;
      "whisper:${WHISPER_DOWNLOAD_ROW:?}")
        printf '%s\n' 'whisper-small-en-q8-0'
        ;;
      *)
        exit 64
        ;;
    esac
    exit 0
    ;;
  --list-models)
    printf '%s\n' '/pool/cache/llama/models/test.Q4_K_M.gguf'
    exit 0
    ;;
  --list-favorite-models)
    exit 0
    ;;
  --list-whisper-models)
    printf '%s\n' '/pool/cache/whisper/models/ggml-small.en.bin'
    exit 0
    ;;
esac
run_flag=${1:-}
[ "$run_flag" = --run ] || exit 64
shift
printf '%s' "$run_flag" >>"${ACTION_ARGV_LOG:?}"
[ "$#" -eq 0 ] || printf ' %s' "$@" >>"${ACTION_ARGV_LOG:?}"
printf '\n' >>"${ACTION_ARGV_LOG:?}"
printf '%s' "${1:-}" >>"${ACTION_LOG:?}"
shift || true
[ "$#" -eq 0 ] || printf ' %s' "$@" >>"${ACTION_LOG:?}"
printf '\n' >>"${ACTION_LOG:?}"
EOF
chmod 0755 "$bin_dir/labwc-ai-copilots-action"

run_ai_terminal() {
  PATH="$bin_dir:$PATH" \
  HOME="$TMP_DIR/home" \
  MENU_LOG="$menu_log" \
  SELECTION_FILE="$selection_file" \
  ACTION_LOG="$action_log" \
  ACTION_ARGV_LOG="$action_argv_log" \
  FZF_ARGV_LOG="$fzf_argv_log" \
  LLAMA_DOWNLOAD_ROW="$llama_download_row" \
  WHISPER_DOWNLOAD_ROW="$whisper_download_row" \
  AI_COPILOTS="$ai_copilots" \
  TTY_INPUT_FILE="$tty_input_file" \
  TERMINAL_OUTPUT="$terminal_output" \
    /usr/bin/timeout 15s /usr/bin/python3 - <<'PY'
import errno
import os
from pathlib import Path
import pty
import sys

child_pid, master_fd = pty.fork()
if child_pid == 0:
    os.execvpe(
        "/bin/sh",
        ["/bin/sh", os.environ["AI_COPILOTS"], "--terminal"],
        os.environ.copy(),
    )

payload = Path(os.environ["TTY_INPUT_FILE"]).read_bytes()
if payload:
    os.write(master_fd, payload)

output = bytearray()
while True:
    try:
        chunk = os.read(master_fd, 4096)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    output.extend(chunk)
    if len(output) > 1024 * 1024:
        os.kill(child_pid, 9)
        raise RuntimeError("AI terminal smoke output exceeded 1 MiB")

os.close(master_fd)
Path(os.environ["TERMINAL_OUTPUT"]).write_bytes(output)
_, wait_status = os.waitpid(child_pid, 0)
sys.exit(os.waitstatus_to_exitcode(wait_status))
PY
}

run_ai_case() {
  expected_action=$1
  tty_input=$2
  shift 2
  printf '%s\n' "$@" >"$selection_file"
  if [ -n "$tty_input" ]; then
    printf '%s\n' "$tty_input" >"$tty_input_file"
  else
    : >"$tty_input_file"
  fi
  : >"$menu_log"
  : >"$action_log"
  : >"$action_argv_log"
  : >"$fzf_argv_log"
  : >"$terminal_output"
  run_ai_terminal
  [ "$(cat "$action_log")" = "$expected_action" ] &&
    [ "$(cat "$action_argv_log")" = "--run $expected_action" ] &&
    [ ! -s "$selection_file" ]
}

injection_marker="$TMP_DIR/ai-prompt-executed"
llama_custom_tty=$(
  printf '%s\n' \
    "$valid_llama_url" \
    test.Q4_K_M.gguf \
    "$valid_sha256" \
    1048576
)
whisper_custom_tty=$(
  printf '%s\n' \
    "$valid_whisper_url" \
    ggml-small.en.bin \
    "$valid_sha256" \
    1048576
)
injection_tty='$(touch '"$injection_marker"')'
terminal_launch_expected='labwc-terminal -e /usr/local/bin/labwc-ai-copilots --terminal'
: >"$action_log"
if PATH="$bin_dir:$PATH" \
     HOME="$TMP_DIR/home" \
     ACTION_LOG="$action_log" \
       /bin/sh "$ai_copilots" &&
   [ "$(cat "$action_log")" = "$terminal_launch_expected" ] &&
   run_ai_case 'codex-new-session' '' \
     '⮞ Codex' '★ New Coding Session' '← Back' 'Exit' &&
   run_ai_case 'llama-model-info context-length /pool/cache/llama/models/test.Q4_K_M.gguf' \
     '' \
     '⮞ Llama' '⮞ Models' 'Show Context Length' \
     'test.Q4_K_M.gguf' \
     '← Back' '← Back' 'Exit' &&
   grep -Fq 'test.Q4_K_M.gguf' "$menu_log" &&
   ! grep -Fq '/pool/cache/llama/models/' "$menu_log" &&
   run_ai_case \
     'llama-download-catalog-model llama32-1b-q4-k-m' \
     '' \
     '⮞ Llama' '⮞ Models' 'Download New Model…' \
     "$llama_download_row" \
     '← Back' '← Back' 'Exit' &&
   grep -Fq 'LANGUAGE' "$menu_log" &&
   grep -Fq 'PARAMS' "$menu_log" &&
   grep -Fq 'RAM MIN' "$menu_log" &&
   grep -Fq 'RAM REC' "$menu_log" &&
   grep -Fq 'WEIGHTS' "$menu_log" &&
   grep -Fq -- '--header-lines=2' "$fzf_argv_log" &&
   ! grep -Fq 'llama32-1b-q4-k-m' "$menu_log" &&
   ! grep -Fq '/pool/cache/' "$menu_log" &&
   run_ai_case \
     "llama-download-model $valid_llama_url test.Q4_K_M.gguf $valid_sha256 1048576" \
     "$llama_custom_tty" \
     '⮞ Llama' '★ Download New Model…' \
     '★ Custom Hugging Face URL…' \
     '← Back' 'Exit' &&
   run_ai_case 'whisper-set-active-model /pool/cache/whisper/models/ggml-small.en.bin' \
     '' \
     '⮞ Whisper' '★ Change Model…' \
     'ggml-small.en.bin' \
     '← Back' 'Exit' &&
   grep -Fq 'ggml-small.en.bin' "$menu_log" &&
   ! grep -Fq '/pool/cache/whisper/models/' "$menu_log" &&
   run_ai_case \
     'whisper-download-catalog-model whisper-small-en-q8-0' \
     '' \
     '⮞ Whisper' '★ Download New Model…' \
     "$whisper_download_row" \
     '← Back' 'Exit' &&
   grep -Fq 'LANGUAGE' "$menu_log" &&
   grep -Fq 'PARAMS' "$menu_log" &&
   grep -Fq 'RAM MIN' "$menu_log" &&
   grep -Fq 'RAM REC' "$menu_log" &&
   grep -Fq 'WEIGHTS' "$menu_log" &&
   grep -Fq -- '--header-lines=2' "$fzf_argv_log" &&
   ! grep -Fq 'whisper-small-en-q8-0' "$menu_log" &&
   ! grep -Fq '/pool/cache/' "$menu_log" &&
   run_ai_case \
     "whisper-download-model $valid_whisper_url ggml-small.en.bin $valid_sha256 1048576" \
     "$whisper_custom_tty" \
     '⮞ Whisper' '★ Download New Model…' \
     '★ Custom Hugging Face URL…' \
     '← Back' 'Exit' &&
   run_ai_case 'llama-start-server' '' \
     '⮞ Llama' '⮞ Server' 'Start Llama Server' \
     '← Back' '← Back' 'Exit' &&
   run_ai_case 'llama-stop-server' '' \
     '⮞ Llama' '⮞ Server' 'Stop Llama Server' \
     '← Back' '← Back' 'Exit' &&
   run_ai_case 'llama-diagnostic server-status' '' \
     '⮞ Llama' '⮞ Server' 'Show Server Status' \
     '← Back' '← Back' 'Exit' &&
   run_ai_case 'whisper-dictation toggle' '' \
     '⮞ Whisper' '★ Toggle Dictation' '← Back' 'Exit' &&
   run_ai_case 'llama-ask $(touch '"$injection_marker"')' \
     "$injection_tty" \
     '⮞ Llama' '★ Ask Llama…' \
     '← Back' 'Exit' &&
   [ ! -e "$injection_marker" ] &&
   /bin/sh -n "$ai_copilots"; then
  pass "AI & Copilots uses one Foot-first terminal selector while preserving private model paths and fixed argv"
else
  fail "AI & Copilots uses one Foot-first terminal selector while preserving private model paths and fixed argv"
fi

printf '%s\n' '__FAIL__' >"$selection_file"
: >"$menu_log"
: >"$action_log"
if ! PATH="$bin_dir:$PATH" \
     LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
     MENU_LOG="$menu_log" \
     SELECTION_FILE="$selection_file" \
     ACTION_LOG="$action_log" \
       /bin/sh "$computer_management" \
         >"$TMP_DIR/computer-management-failure.stdout" \
         2>"$TMP_DIR/computer-management-failure.stderr" &&
   [ ! -s "$action_log" ] &&
   grep -Fq 'unable to open the Computer Management menu (status 2)' \
     "$TMP_DIR/computer-management-failure.stderr"; then
  pass "Computer Management treats Fuzzel cancellation as Back while surfacing launcher failures"
else
  fail "Computer Management treats Fuzzel cancellation as Back while surfacing launcher failures"
fi

cat >"$bin_dir/labwc-brightness-control" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${ACTION_LOG:?}"
exit 1
EOF
chmod 0755 "$bin_dir/labwc-brightness-control"
printf '%s\n' \
  '⮞ Hardware & Peripherals' \
  '⮞ Brightness' \
  'Exit' >"$selection_file"
: >"$action_log"
if PATH="$bin_dir:$PATH" \
   LABWC_DESKTOP_DEFAULTS_FILE=/nonexistent \
   MENU_LOG="$menu_log" \
   SELECTION_FILE="$selection_file" \
   ACTION_LOG="$action_log" \
     /bin/sh "$computer_management" \
       >"$TMP_DIR/computer-management-action-failure.stdout" \
       2>"$TMP_DIR/computer-management-action-failure.stderr" &&
   [ -s "$action_log" ] &&
   grep -Fq 'warning: Computer Management action returned status 1: labwc-brightness-control' \
     "$TMP_DIR/computer-management-action-failure.stderr"; then
  pass "Computer Management records a child failure and returns to the launcher"
else
  fail "Computer Management records a child failure and returns to the launcher"
fi

for helper in systemctl ip labwc-security-action; do
  cat >"$bin_dir/$helper" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 0755 "$bin_dir/$helper"
done

printf '%s\n' '← Back' >"$selection_file"
: >"$menu_log"
PATH="$bin_dir:$PATH" \
MENU_LOG="$menu_log" \
SELECTION_FILE="$selection_file" \
  /bin/sh "$maintenance_menu" security

if grep -q '⮞ Security Auditing' "$menu_log" &&
   grep -q '⮞ Malware & Rootkit Scanning' "$menu_log" &&
   grep -q '⮞ Vulnerability & Integrity' "$menu_log" &&
   grep -q '⮞ AppArmor' "$menu_log" &&
   grep -q '⮞ Firewall Security' "$menu_log" &&
   ! grep -q '⮞ System' "$menu_log" &&
   ! grep -q '⮞ Troubleshooting' "$menu_log"; then
  pass "Computer Management opens the folder-style Endpoint Security category tree"
else
  fail "Computer Management opens the folder-style Endpoint Security category tree"
fi

wrapper_bin="$TMP_DIR/wrapper-bin"
wrapper_input="$TMP_DIR/wrapper.input"
mkdir -p "$wrapper_bin"

cat >"$wrapper_bin/fuzzel" <<'EOF'
#!/bin/sh
set -eu
cat >"${FUZZEL_INPUT:?}"
[ -z "${FUZZEL_ARGS:-}" ] || printf '%s\n' "$@" >"$FUZZEL_ARGS"
printf '%s\n' "${FUZZEL_SELECTION:?}"
EOF
chmod 0755 "$wrapper_bin/fuzzel"

cat >"$wrapper_bin/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$wrapper_bin/pgrep"

managed_selection=$(
  printf '%s\n' \
    'Show System Overview' \
    'Restart NetworkManager' \
    'Exit' |
    PATH="$wrapper_bin:$PATH" \
    HOME="$TMP_DIR/home" \
    XDG_RUNTIME_DIR="$TMP_DIR" \
    FUZZEL_INPUT="$wrapper_input" \
    FUZZEL_ARGS="$TMP_DIR/wrapper.args" \
    FUZZEL_SELECTION='  Show System Overview' \
    LABWC_FUZZEL_MANAGED_ICONS=1 \
    LABWC_FUZZEL_MENU_WIDTH_OVERRIDE=31 \
    LABWC_FUZZEL_MENU_LINES_OVERRIDE=12 \
    LABWC_FUZZEL_MENU_FONT_SIZE_OVERRIDE=17 \
      /bin/sh "$fuzzel_wrapper" menu --dmenu --prompt System
)

if [ "$managed_selection" = 'Show System Overview' ] &&
   grep -Fxq '  Show System Overview' "$wrapper_input" &&
   grep -Fxq '  Restart NetworkManager' "$wrapper_input" &&
   grep -Fxq '← Back' "$wrapper_input" &&
   ! grep -Fxq 'Exit' "$wrapper_input" &&
   [ "$(grep -Fxc '← Back' "$wrapper_input")" -eq 1 ] &&
   grep -Fxq -- '--width=31' "$TMP_DIR/wrapper.args" &&
   grep -Fxq -- '--lines=12' "$TMP_DIR/wrapper.args" &&
   grep -Fxq -- '--font=Noto Sans:size=17,Noto Color Emoji:size=17,Font Awesome 6 Free:size=17' "$TMP_DIR/wrapper.args" &&
   /bin/sh -n "$fuzzel_wrapper"; then
  pass "managed Fuzzel menus decorate actions, apply sizing overrides, and translate child Exit into Back"
else
  fail "managed Fuzzel menus decorate actions, apply sizing overrides, and translate child Exit into Back"
fi

render_managed_icons() {
  prompt=$1
  output_file=$2
  shift 2

  printf '%s\n' "$@" |
    PATH="$wrapper_bin:$PATH" \
    HOME="$TMP_DIR/home" \
    XDG_RUNTIME_DIR="$TMP_DIR" \
    FUZZEL_INPUT="$output_file" \
    FUZZEL_SELECTION='← Back' \
    LABWC_FUZZEL_MANAGED_ICONS=1 \
      /bin/sh "$fuzzel_wrapper" menu --dmenu --prompt "$prompt" >/dev/null
}

container_icon_input="$TMP_DIR/container-icons.input"
managed_users_icon_input="$TMP_DIR/managed-users-icons.input"
managed_service_icon_input="$TMP_DIR/managed-service-icons.input"
remote_icon_input="$TMP_DIR/remote-icons.input"
security_icon_input="$TMP_DIR/security-icons.input"
apparmor_icon_input="$TMP_DIR/apparmor-icons.input"
users_groups_icon_input="$TMP_DIR/users-groups-icons.input"
system_icon_input="$TMP_DIR/system-icons.input"
adb_icon_input="$TMP_DIR/adb-icons.input"
troubleshooting_icon_input="$TMP_DIR/troubleshooting-icons.input"
network_icon_input="$TMP_DIR/network-icons.input"
whisper_recording_icon_input="$TMP_DIR/whisper-recording-icons.input"
digital_assets_root_icon_input="$TMP_DIR/digital-assets-root-icons.input"
docx_icon_input="$TMP_DIR/docx-icons.input"
pdf_icon_input="$TMP_DIR/pdf-icons.input"
image_icon_input="$TMP_DIR/image-icons.input"
missing_files_icon_input="$TMP_DIR/missing-files-icons.input"

render_managed_icons \
  "Container Management" \
  "$container_icon_input" \
  '⮞ Managed Users' \
  '⮞ User Runtime' \
  'Open Podbin Guide' \
  '← Back'
render_managed_icons \
  "Container Management — Managed Users" \
  "$managed_users_icon_input" \
  'List Managed Users' \
  'Show User Environment' \
  '← Back'
render_managed_icons \
  "Container Management — Managed Service" \
  "$managed_service_icon_input" \
  'Show Service Environment' \
  'List Service Networks' \
  'Show Service Statistics' \
  'Show Recent Service Logs' \
  '← Back'
render_managed_icons \
  "Remote Desktop Management" \
  "$remote_icon_input" \
  'Show FreeRDP Help' \
  '← Back'
render_managed_icons \
  "Endpoint Security" \
  "$security_icon_input" \
  '⮞ Security Auditing' \
  '⮞ Malware & Rootkit Scanning' \
  '⮞ Vulnerability & Integrity' \
  '⮞ AppArmor' \
  '⮞ Firewall Security' \
  '← Back'
render_managed_icons \
  "AppArmor" \
  "$apparmor_icon_input" \
  'AppArmor Status' \
  'Kernel Enablement' \
  'Features ABI' \
  'Complain Events (24h)' \
  'Denied Events (24h)' \
  'Easyprof Draft' \
  'Autodep Base Draft' \
  'Logprof Draft Update' \
  'Genprof Interactive Draft' \
  'List Drafts' \
  'Validate Drafts' \
  'Show App Modes' \
  'Enforce All' \
  'Complain All' \
  'Disable All' \
  'Set App Mode' \
  'Set App Audit Logging' \
  'Disabled Profiles' \
  'Preview Unknown Cleanup' \
  '← Back'
render_managed_icons \
  "Users & Groups" \
  "$users_groups_icon_input" \
  'List User Accounts' \
  'List Non-Sudo Users' \
  'List Groups' \
  'List Sudo Administrators' \
  '← Back'
render_managed_icons \
  System \
  "$system_icon_input" \
  'Show System Overview' \
  'Show Failed Services' \
  'Show Recent System Errors' \
  'Show Kernel Warnings' \
  'Show Memory and Swap' \
  'Check Package Health' \
  'List Pending Upgrades' \
  'Inspect Service and Logs' \
  'Show Upgradeable Packages' \
  'Run Unattended Upgrades Now' \
  'Show Failed System Units' \
  'Show Failed User Units' \
  'Show Timers' \
  'Test Mako Notification' \
  '← Back'
render_managed_icons \
  "ADB Server" \
  "$adb_icon_input" \
  'Show Server Status' \
  'Reconnect USB Devices' \
  'Reconnect Offline Devices' \
  'Wait for Any Device (60s)' \
  'List Devices with Details' \
  'Show Host Features' \
  '← Back'
render_managed_icons \
  Troubleshooting \
  "$troubleshooting_icon_input" \
  'Aggressive Journal Vacuum' \
  '← Back'
render_managed_icons \
  "Network Management" \
  "$network_icon_input" \
  'Show Wi-Fi Radio' \
  'Scan LAN' \
  'Scan WAN Host' \
  'Capture Packet' \
  'Show Listening Port' \
  'DNS Configuration' \
  'Show Resolver Statistics' \
  'Network Scanning' \
  'Connection Profiles' \
  'VPN Connections' \
  'WireGuard Connections' \
  'Unmapped Action' \
  '← Back'
render_managed_icons \
  "Whisper — Recording" \
  "$whisper_recording_icon_input" \
  '⮞ Recording Settings' \
  'Open Recording Folder' \
  '← Back'
render_managed_icons \
  "Digital Assets" \
  "$digital_assets_root_icon_input" \
  'DOCX Actions' \
  'PDF Actions' \
  'Image Actions' \
  '← Back'
render_managed_icons \
  "DOCX Actions" \
  "$docx_icon_input" \
  'Convert DOCX to PDF' \
  'Convert DOCX to Markdown' \
  'Convert DOCX to Plain Text' \
  'Convert DOCX to HTML' \
  'Read Metadata' \
  'Edit Metadata' \
  'Remove All Metadata' \
  '← Back'
render_managed_icons \
  "PDF Actions" \
  "$pdf_icon_input" \
  'Convert PDF to PNG' \
  'Convert PDF to JPEG' \
  'Convert PDF to DOCX' \
  'Convert PDF to Plain Text' \
  'Convert Markdown to PDF' \
  'Extract Images from PDF' \
  "Merge Multiple PDF's" \
  'Split PDF (Burst to Pages)' \
  'Extract Specific Pages' \
  'Remove Specific Pages' \
  'Rotate Pages' \
  'Edit PDF Content' \
  'Edit PDF Bookmarks' \
  'Edit Hyperlinks and Typos' \
  'Clean / Repair Corrupted PDF' \
  'Inspect PDF Structure' \
  'Encrypt / Password Protect' \
  'Decrypt / Remove Password' \
  'Linearize (Optimize size for Web)' \
  'Add Page Numbers' \
  'Add Text Watermark' \
  'Extract TOC / Bookmarks' \
  'Read Metadata' \
  'Edit Metadata' \
  'Remove All Metadata' \
  '← Back'
render_managed_icons \
  "Image Actions" \
  "$image_icon_input" \
  'Convert Any Image to PNG' \
  'Convert Any Image to JPEG' \
  'Convert Image to WebP' \
  'Resize Image' \
  'Crop Image' \
  'Rotate Image' \
  'Flip (Horizontal)' \
  'Flip (Vertical)' \
  'Convert to Grayscale' \
  'Compress / Optimize PNG' \
  'Compress / Optimize JPEG' \
  'Create GIF from Images' \
  'Read Image Metadata' \
  'Edit Image Metadata' \
  'Remove All Metadata' \
  '← Back'
render_managed_icons \
  "PDF to PNG" \
  "$missing_files_icon_input" \
  'No DOCX files detected in Downloads, Documents, or Desktop' \
  'No PDF files detected in Downloads, Documents, or Desktop' \
  'No Image files detected in Downloads, Documents, or Desktop' \
  'No Markdown files detected in Downloads, Documents, or Desktop' \
  '← Back'

if grep -Fxq '⮞ Managed Users' "$container_icon_input" &&
   grep -Fxq '⮞ User Runtime' "$container_icon_input" &&
   grep -Fxq '  Open Podbin Guide' "$container_icon_input" &&
   grep -Fxq '  List Managed Users' "$managed_users_icon_input" &&
   grep -Fxq '  Show User Environment' "$managed_users_icon_input" &&
   grep -Fxq '  Show Service Environment' "$managed_service_icon_input" &&
   grep -Fxq '  List Service Networks' "$managed_service_icon_input" &&
   grep -Fxq '  Show Service Statistics' "$managed_service_icon_input" &&
   grep -Fxq '  Show Recent Service Logs' "$managed_service_icon_input" &&
   grep -Fxq '  Show FreeRDP Help' "$remote_icon_input" &&
   grep -Fxq '⮞ Security Auditing' "$security_icon_input" &&
   grep -Fxq '⮞ Malware & Rootkit Scanning' "$security_icon_input" &&
   grep -Fxq '⮞ Vulnerability & Integrity' "$security_icon_input" &&
   grep -Fxq '⮞ AppArmor' "$security_icon_input" &&
   grep -Fxq '⮞ Firewall Security' "$security_icon_input" &&
   grep -Fxq '  AppArmor Status' "$apparmor_icon_input" &&
   grep -Fxq '  Kernel Enablement' "$apparmor_icon_input" &&
   grep -Fxq '  Features ABI' "$apparmor_icon_input" &&
   grep -Fxq '  Complain Events (24h)' "$apparmor_icon_input" &&
   grep -Fxq '  Denied Events (24h)' "$apparmor_icon_input" &&
   [ "$(grep -Fc '  ' "$apparmor_icon_input")" -eq 4 ] &&
   grep -Fxq '  List Drafts' "$apparmor_icon_input" &&
   grep -Fxq '  Validate Drafts' "$apparmor_icon_input" &&
   grep -Fxq '  Show App Modes' "$apparmor_icon_input" &&
   grep -Fxq '  Enforce All' "$apparmor_icon_input" &&
   grep -Fxq '  Complain All' "$apparmor_icon_input" &&
   grep -Fxq '  Disable All' "$apparmor_icon_input" &&
   grep -Fxq '  Set App Mode' "$apparmor_icon_input" &&
   grep -Fxq '  Set App Audit Logging' "$apparmor_icon_input" &&
   grep -Fxq '  Disabled Profiles' "$apparmor_icon_input" &&
   grep -Fxq '  Preview Unknown Cleanup' "$apparmor_icon_input" &&
   [ "$(grep -Fc '  ' "$users_groups_icon_input")" -eq 4 ] &&
   grep -Fxq '  Show System Overview' "$system_icon_input" &&
   grep -Fxq '  Show Failed Services' "$system_icon_input" &&
   grep -Fxq '  Show Recent System Errors' "$system_icon_input" &&
   grep -Fxq '  Show Kernel Warnings' "$system_icon_input" &&
   grep -Fxq '  Show Memory and Swap' "$system_icon_input" &&
   grep -Fxq '  Check Package Health' "$system_icon_input" &&
   grep -Fxq '  List Pending Upgrades' "$system_icon_input" &&
   grep -Fxq '  Inspect Service and Logs' "$system_icon_input" &&
   grep -Fxq '  Show Upgradeable Packages' "$system_icon_input" &&
   grep -Fxq '  Run Unattended Upgrades Now' "$system_icon_input" &&
   grep -Fxq '  Show Failed System Units' "$system_icon_input" &&
   grep -Fxq '  Show Failed User Units' "$system_icon_input" &&
   grep -Fxq '  Show Timers' "$system_icon_input" &&
   grep -Fxq '  Test Mako Notification' "$system_icon_input" &&
   grep -Fxq '  Show Server Status' "$adb_icon_input" &&
   grep -Fxq '  Reconnect USB Devices' "$adb_icon_input" &&
   grep -Fxq '  Reconnect Offline Devices' "$adb_icon_input" &&
   grep -Fxq '  Wait for Any Device (60s)' "$adb_icon_input" &&
   grep -Fxq '  List Devices with Details' "$adb_icon_input" &&
   grep -Fxq '  Show Host Features' "$adb_icon_input" &&
   grep -Fxq '  Aggressive Journal Vacuum' "$troubleshooting_icon_input" &&
   grep -Fxq '  Show Wi-Fi Radio' "$network_icon_input" &&
   grep -Fxq '  Scan LAN' "$network_icon_input" &&
   grep -Fxq '  Scan WAN Host' "$network_icon_input" &&
   grep -Fxq '  Capture Packet' "$network_icon_input" &&
   grep -Fxq '  Show Listening Port' "$network_icon_input" &&
   grep -Fxq '  DNS Configuration' "$network_icon_input" &&
   grep -Fxq '  Show Resolver Statistics' "$network_icon_input" &&
   grep -Fxq '  Network Scanning' "$network_icon_input" &&
   grep -Fxq '  Connection Profiles' "$network_icon_input" &&
   grep -Fxq '  VPN Connections' "$network_icon_input" &&
   grep -Fxq '  WireGuard Connections' "$network_icon_input" &&
   grep -Fxq '  Unmapped Action' "$network_icon_input" &&
   [ "$(grep -Fc '  ' "$network_icon_input")" -eq 1 ] &&
   grep -Fxq '⮞ Recording Settings' "$whisper_recording_icon_input" &&
   grep -Fxq '  Open Recording Folder' "$whisper_recording_icon_input" &&
   grep -Fqx '⮞  DOCX Actions' "$digital_assets_root_icon_input" &&
   grep -Fqx '⮞  PDF Actions' "$digital_assets_root_icon_input" &&
   grep -Fqx '⮞  Image Actions' "$digital_assets_root_icon_input" &&
   grep -Fqx '  Convert DOCX to PDF' "$docx_icon_input" &&
   grep -Fqx '  Convert DOCX to Markdown' "$docx_icon_input" &&
   grep -Fqx '  Convert DOCX to Plain Text' "$docx_icon_input" &&
   grep -Fqx '  Convert DOCX to HTML' "$docx_icon_input" &&
   grep -Fqx '  Read Metadata' "$docx_icon_input" &&
   grep -Fqx '  Edit Metadata' "$docx_icon_input" &&
   grep -Fqx '  Remove All Metadata' "$docx_icon_input" &&
   grep -Fqx '  Convert PDF to PNG' "$pdf_icon_input" &&
   grep -Fqx '  Convert PDF to JPEG' "$pdf_icon_input" &&
   grep -Fqx '  Convert PDF to DOCX' "$pdf_icon_input" &&
   grep -Fqx '  Convert PDF to Plain Text' "$pdf_icon_input" &&
   grep -Fqx '  Convert Markdown to PDF' "$pdf_icon_input" &&
   grep -Fqx '  Extract Images from PDF' "$pdf_icon_input" &&
   grep -Fqx '  Merge Multiple PDF'\''s' "$pdf_icon_input" &&
   grep -Fqx '  Split PDF (Burst to Pages)' "$pdf_icon_input" &&
   grep -Fqx '  Extract Specific Pages' "$pdf_icon_input" &&
   grep -Fqx '  Remove Specific Pages' "$pdf_icon_input" &&
   grep -Fqx '  Rotate Pages' "$pdf_icon_input" &&
   grep -Fqx '  Edit PDF Content' "$pdf_icon_input" &&
   grep -Fqx '  Edit PDF Bookmarks' "$pdf_icon_input" &&
   grep -Fqx '  Edit Hyperlinks and Typos' "$pdf_icon_input" &&
   grep -Fqx '  Clean / Repair Corrupted PDF' "$pdf_icon_input" &&
   grep -Fqx '  Inspect PDF Structure' "$pdf_icon_input" &&
   grep -Fqx '  Encrypt / Password Protect' "$pdf_icon_input" &&
   grep -Fqx '  Decrypt / Remove Password' "$pdf_icon_input" &&
   grep -Fqx '  Linearize (Optimize size for Web)' "$pdf_icon_input" &&
   grep -Fqx '  Add Page Numbers' "$pdf_icon_input" &&
   grep -Fqx '  Add Text Watermark' "$pdf_icon_input" &&
   grep -Fqx '  Extract TOC / Bookmarks' "$pdf_icon_input" &&
   grep -Fqx '  Read Metadata' "$pdf_icon_input" &&
   grep -Fqx '  Edit Metadata' "$pdf_icon_input" &&
   grep -Fqx '  Remove All Metadata' "$pdf_icon_input" &&
   grep -Fqx '  Convert Any Image to PNG' "$image_icon_input" &&
   grep -Fqx '  Convert Any Image to JPEG' "$image_icon_input" &&
   grep -Fqx '  Convert Image to WebP' "$image_icon_input" &&
   grep -Fqx '  Resize Image' "$image_icon_input" &&
   grep -Fqx '  Crop Image' "$image_icon_input" &&
   grep -Fqx '  Rotate Image' "$image_icon_input" &&
   grep -Fqx '↔  Flip (Horizontal)' "$image_icon_input" &&
   grep -Fqx '↕  Flip (Vertical)' "$image_icon_input" &&
   grep -Fqx '  Convert to Grayscale' "$image_icon_input" &&
   grep -Fqx '  Compress / Optimize PNG' "$image_icon_input" &&
   grep -Fqx '  Compress / Optimize JPEG' "$image_icon_input" &&
   grep -Fqx '  Create GIF from Images' "$image_icon_input" &&
   grep -Fqx '  Read Image Metadata' "$image_icon_input" &&
   grep -Fqx '  Edit Image Metadata' "$image_icon_input" &&
   grep -Fqx '  Remove All Metadata' "$image_icon_input" &&
   [ "$(grep -Fc '  No ' "$missing_files_icon_input")" -eq 4 ]; then
  pass "managed Fuzzel uses structured Digital Assets and missing-file status icons"
else
  fail "managed Fuzzel uses structured Digital Assets and missing-file status icons"
fi

root_selection=$(
  printf '%s\n' \
    '⮞ System Configuration' \
    'Exit' |
    PATH="$wrapper_bin:$PATH" \
    HOME="$TMP_DIR/home" \
    XDG_RUNTIME_DIR="$TMP_DIR" \
    FUZZEL_INPUT="$wrapper_input" \
    FUZZEL_SELECTION='  Exit' \
    LABWC_FUZZEL_MANAGED_ICONS=1 \
    LABWC_FUZZEL_ROOT_MENU=1 \
      /bin/sh "$fuzzel_wrapper" menu --dmenu --prompt Root
)

if [ "$root_selection" = Exit ] &&
   grep -Fxq '⮞ System Configuration' "$wrapper_input" &&
   grep -Fxq '  Exit' "$wrapper_input" &&
   ! grep -Fxq '← Back' "$wrapper_input"; then
  pass "the Computer Management root keeps an iconized Exit while child menus use Back"
else
  fail "the Computer Management root keeps an iconized Exit while child menus use Back"
fi

nul_input="$TMP_DIR/nul.input"
nul_expected="$TMP_DIR/nul.expected"
printf 'first\0second\0' >"$nul_expected"
if nul_selection=$(
     cat "$nul_expected" |
       PATH="$wrapper_bin:$PATH" \
       HOME="$TMP_DIR/home" \
       XDG_RUNTIME_DIR="$TMP_DIR" \
       FUZZEL_INPUT="$nul_input" \
       FUZZEL_SELECTION=first \
       LABWC_FUZZEL_MANAGED_ICONS=1 \
         /bin/sh "$fuzzel_wrapper" menu --dmenu0
   ) &&
   [ "$nul_selection" = first ] &&
   cmp -s "$nul_expected" "$nul_input"; then
  pass "managed Fuzzel preserves NUL-delimited dmenu backends without line decoration"
else
  fail "managed Fuzzel preserves NUL-delimited dmenu backends without line decoration"
fi

rm -f "$wrapper_input"
if ! awk 'BEGIN { for (line = 1; line <= 1025; line++) print "bounded" }' |
     PATH="$wrapper_bin:$PATH" \
     HOME="$TMP_DIR/home" \
     XDG_RUNTIME_DIR="$TMP_DIR" \
     FUZZEL_INPUT="$wrapper_input" \
     FUZZEL_SELECTION=bounded \
     LABWC_FUZZEL_MANAGED_ICONS=1 \
       /bin/sh "$fuzzel_wrapper" menu --dmenu --prompt Bounds >/dev/null 2>&1 &&
   [ ! -e "$wrapper_input" ] &&
   ! printf '%s\n' bounded |
     PATH="$wrapper_bin:$PATH" \
     HOME="$TMP_DIR/home" \
     XDG_RUNTIME_DIR="$TMP_DIR" \
     FUZZEL_INPUT="$wrapper_input" \
     FUZZEL_SELECTION=bounded \
     LABWC_FUZZEL_MANAGED_ICONS=1 \
     LABWC_FUZZEL_MENU_WIDTH_OVERRIDE=15 \
       /bin/sh "$fuzzel_wrapper" menu --dmenu --prompt Bounds >/dev/null 2>&1 &&
   [ ! -e "$wrapper_input" ]; then
  pass "managed Fuzzel rejects oversized catalogs and out-of-range sizing before invoking the backend"
else
  fail "managed Fuzzel rejects oversized catalogs and out-of-range sizing before invoking the backend"
fi
