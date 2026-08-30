#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/labwc-firewall-security.XXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=11
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

printf '1..%s\n' "$TEST_COUNT"

firewall_menu="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-firewall-menu"
firewall_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/bin/labwc-firewall-action"
firewall_root_action="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/libexec/labwc-firewall-action-root"
firewall_package_parent="$ROOT_DIR/d-i/forky/hooks/role/desktop/target/usr/local/lib/python3.14/dist-packages"
firewall_package="$firewall_package_parent/labwc_firewall"
firewall_cli="$firewall_package/cli.py"
firewall_files="$firewall_package/files.py"
firewall_nftables="$firewall_package/nftables.py"
firewall_renderer="$firewall_package/renderer.py"
firewall_state="$firewall_package/state.py"
firewall_validation="$firewall_package/validation.py"
firewall_state_source="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables/firewall-security.rules"
firewall_fragment_source="$ROOT_DIR/d-i/forky/hooks/shared/target/etc/nftables.d/95-firewall-security.nft"
generator="$ROOT_DIR/d-i/forky/hooks/shared/target/usr/local/sbin/nft-policy-generate.py"
desktop_components="$ROOT_DIR/d-i/forky/scripts/desktop/components.sh"
desktop_verify="$ROOT_DIR/d-i/forky/scripts/desktop/verify.sh"
firstboot_validation="$ROOT_DIR/d-i/forky/scripts/firstboot/04-validation.sh"
security_helper="$ROOT_DIR/d-i/forky/scripts/late/security.sh"

firewall_labels_ok=true
for label in \
  ' Status & Managed Rules' \
  ' Incoming Traffic' \
  ' Outgoing Traffic' \
  'Show Firewall Status' \
  'Allow Incoming Port from Any Source' \
  'Allow Incoming Port from LAN' \
  'Allow Incoming Port from IP/CIDR' \
  'Block Incoming Port from Any Source' \
  'Block Incoming Port from LAN' \
  'Block Incoming Port from IP/CIDR' \
  'Allow Outgoing Port to Any Destination' \
  'Allow Outgoing Port to LAN' \
  'Allow Outgoing Port to IP/CIDR' \
  'Block Outgoing Port to Any Destination' \
  'Block Outgoing Port to LAN' \
  'Block Outgoing Port to IP/CIDR' \
  'Remove Managed Firewall Rule' \
  'Reset Managed Firewall Rules'
do
  grep -Fq "'${label}'" "$firewall_menu" || firewall_labels_ok=false
done

if [ "$firewall_labels_ok" = true ] &&
   grep -q '^incoming_traffic_menu() {$' "$firewall_menu" &&
   grep -q '^outgoing_traffic_menu() {$' "$firewall_menu" &&
   grep -q '^managed_rules_menu() {$' "$firewall_menu" &&
   grep -q 'Endpoint Security — Firewall Security' "$firewall_menu" &&
   grep -Fq 'change_summary="${verdict} ${direction} ${protocol}/${port} scope=${scope}"' "$firewall_menu" &&
   grep -q '^MAX_RULES = 128$' "$firewall_state" &&
   grep -q 'fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)' "$firewall_files" &&
   grep -q 'os.replace(self.state_candidate, self.paths.state_file)' "$firewall_files" &&
   grep -Fq 'runner.run(nft, "-c", "-f", str(nft_conf))' "$firewall_nftables" &&
   grep -Fq 'runner.run(systemctl, "reload", "nftables.service")' "$firewall_nftables" &&
   grep -q '^def _rollback_or_fail' "$firewall_nftables" &&
   grep -Fq 'include "/etc/nftables.d/95-firewall-security.nft"' "$generator" &&
   grep -q 'usr/local/bin/labwc-firewall-menu /usr/local/bin/labwc-firewall-menu 0755' "$desktop_components" &&
   grep -q 'usr/local/bin/labwc-firewall-action /usr/local/bin/labwc-firewall-action 0755' "$desktop_components" &&
   grep -q 'usr/local/libexec/labwc-firewall-action-root /usr/local/libexec/labwc-firewall-action-root 0755' "$desktop_components" &&
   grep -q '/usr/local/bin/labwc-firewall-menu' "$desktop_verify" &&
   grep -q '/usr/local/bin/labwc-firewall-action' "$firstboot_validation" &&
   grep -q 'etc/nftables/firewall-security.rules' "$security_helper" &&
   grep -q 'etc/nftables.d/95-firewall-security.nft' "$security_helper" &&
   grep -Fq 'PACKAGE_ROOT = Path("/usr/local/lib/python3.14/dist-packages")' "$firewall_action" &&
   grep -Fq 'PACKAGE_ROOT = Path("/usr/local/lib/python3.14/dist-packages")' "$firewall_root_action" &&
   grep -Fq 'metadata.st_uid != 0 or metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH)' "$firewall_action" &&
   grep -Fq 'metadata.st_uid != 0 or metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH)' "$firewall_root_action"; then
  pass "Firewall Security is categorized and persists bounded locked nftables policy"
else
  fail "Firewall Security is categorized and persists bounded locked nftables policy"
fi

if /bin/sh -n "$firewall_menu" &&
   python3 -I - "$firewall_action" "$firewall_root_action" "$firewall_package" <<'PY'
from pathlib import Path
import sys

paths = [Path(sys.argv[1]), Path(sys.argv[2])]
paths.extend(sorted(Path(sys.argv[3]).glob("*.py")))
for path in paths:
    source = path.read_text(encoding="utf-8")
    compile(source, str(path), "exec")
for path in paths[:2]:
    if not path.read_text(encoding="utf-8").startswith("#!/usr/bin/python3 -I\n"):
        raise SystemExit(f"{path}: isolated Python shebang is missing")
PY
then
  pass "Firewall Security menu is POSIX shell and action helpers are isolated Python"
else
  fail "Firewall Security menu is POSIX shell and action helpers are isolated Python"
fi

if python3 -I - "$firewall_package_parent" "$TMP_DIR" <<'PY'
from contextlib import redirect_stdout
from pathlib import Path
import io
import subprocess
import sys
import tempfile

package_parent = Path(sys.argv[1])
scratch = Path(sys.argv[2])
sys.path.insert(0, str(package_parent))

from labwc_firewall import cli, nftables
from labwc_firewall.files import FirewallPaths
from labwc_firewall.renderer import LAN_IPV4, LAN_IPV6, render_fragment
from labwc_firewall.state import (
    MAX_RULES,
    Rule,
    format_status,
    load_state,
    next_rule_id,
    serialize_state,
)
from labwc_firewall.validation import FirewallError


def expect_error(callable_object, message):
    try:
        callable_object()
    except FirewallError as exc:
        if message not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError(f"expected FirewallError containing: {message}")


invalid_requests = (
    (
        ["add-rule", "sideways", "allow", "tcp", "22", "any", "-", "confirmed-firewall-action"],
        "invalid firewall direction",
    ),
    (
        ["add-rule", "incoming", "permit", "tcp", "22", "any", "-", "confirmed-firewall-action"],
        "invalid firewall verdict",
    ),
    (
        ["add-rule", "incoming", "allow", "sctp", "22", "any", "-", "confirmed-firewall-action"],
        "invalid firewall protocol",
    ),
    (
        ["add-rule", "incoming", "allow", "tcp", "0", "any", "-", "confirmed-firewall-action"],
        "firewall port must be",
    ),
    (
        ["add-rule", "incoming", "allow", "tcp", "65536", "any", "-", "confirmed-firewall-action"],
        "firewall port must be",
    ),
    (
        ["add-rule", "incoming", "allow", "tcp", "22", "world", "-", "confirmed-firewall-action"],
        "invalid firewall scope",
    ),
    (
        ["add-rule", "incoming", "allow", "tcp", "22", "any", "192.0.2.0/24", "confirmed-firewall-action"],
        "cannot include a CIDR",
    ),
    (
        ["add-rule", "incoming", "allow", "tcp", "22", "ip", "not-an-ip", "confirmed-firewall-action"],
        "invalid IPv4 or IPv6 firewall CIDR",
    ),
    (
        ["remove-rule", "rule-1", "confirmed-firewall-action"],
        "invalid managed firewall rule identifier",
    ),
    (
        ["reset-rules", "missing-confirmation"],
        "firewall reset confirmation is missing",
    ),
)
for request, expected_message in invalid_requests:
    expect_error(lambda request=request: cli._client_request(request), expected_message)

valid_requests = (
    (
        ["add-rule", "incoming", "allow", "tcp", "22", "any", "-", "confirmed-firewall-action"],
        ["add-rule", "incoming", "allow", "tcp", "22", "any", "-", "confirmed-firewall-action"],
    ),
    (
        ["add-rule", "incoming", "block", "tcp", "443", "ip", "192.0.2.4", "confirmed-firewall-action"],
        ["add-rule", "incoming", "block", "tcp", "443", "ip", "192.0.2.4/32", "confirmed-firewall-action"],
    ),
    (
        ["add-rule", "outgoing", "allow", "tcp", "8443", "ip", "2001:db8::1", "confirmed-firewall-action"],
        ["add-rule", "outgoing", "allow", "tcp", "8443", "ip", "2001:db8::1/128", "confirmed-firewall-action"],
    ),
    (
        ["remove-rule", "rule-0002", "confirmed-firewall-action"],
        ["remove-rule", "rule-0002", "confirmed-firewall-action"],
    ),
    (
        ["reset-rules", "confirmed-firewall-action"],
        ["reset-rules", "confirmed-firewall-action"],
    ),
)
for request, expected_argv in valid_requests:
    root_argv, summary, body = cli._client_request(request)
    assert root_argv == expected_argv
    assert summary and body

rules = [
    Rule("rule-0001", "incoming", "allow", "tcp", 22, "any", "-"),
    Rule("rule-0002", "outgoing", "block", "udp", 53, "lan", "-"),
    Rule("rule-0003", "incoming", "block", "tcp", 443, "ip", "192.0.2.4/32"),
    Rule("rule-0004", "outgoing", "allow", "tcp", 8443, "ip", "2001:db8::1/128"),
]
state_path = scratch / "state.rules"
state_path.write_text(serialize_state(rules), encoding="utf-8")
assert load_state(state_path) == rules
assert next_rule_id(rules) == "rule-0005"
assert "rule-0004: outgoing allow tcp port 8443" in format_status(rules)
fragment = render_fragment(rules)
assert "add rule inet filter local_input tcp dport 22" in fragment
assert f"ip daddr {LAN_IPV4} udp dport 53" in fragment
assert f"ip6 daddr {LAN_IPV6} udp dport 53" in fragment
assert "ip saddr 192.0.2.4/32 tcp dport 443" in fragment
assert "ip6 daddr 2001:db8::1/128 tcp dport 8443" in fragment

paths = FirewallPaths(
    state_file=state_path,
    fragment_file=scratch / "fragment.nft",
    nft_conf=scratch / "nftables.conf",
    lock_file=scratch / "firewall.lock",
)
paths.fragment_file.write_text("# fragment\n", encoding="utf-8")
paths.nft_conf.write_text("# entrypoint\n", encoding="utf-8")
captured = []
original_apply = cli._apply_rules
cli._apply_rules = lambda _paths, updated, _runner: captured.append(list(updated))
try:
    state_path.write_text(serialize_state([]), encoding="utf-8")
    with redirect_stdout(io.StringIO()):
        cli._add_rule(
            paths,
            object(),
            ["incoming", "allow", "tcp", "22", "any", "-", "confirmed-firewall-action"],
        )
    assert captured[-1] == [
        Rule("rule-0001", "incoming", "allow", "tcp", 22, "any", "-")
    ]

    state_path.write_text(serialize_state(rules), encoding="utf-8")
    with redirect_stdout(io.StringIO()):
        cli._remove_rule(
            paths,
            object(),
            ["rule-0002", "confirmed-firewall-action"],
        )
    assert [rule.rule_id for rule in captured[-1]] == [
        "rule-0001",
        "rule-0003",
        "rule-0004",
    ]

    with redirect_stdout(io.StringIO()):
        cli._reset_rules(
            paths,
            object(),
            ["confirmed-firewall-action"],
        )
    assert captured[-1] == []
finally:
    cli._apply_rules = original_apply


class Completed:
    def __init__(self, returncode):
        self.returncode = returncode


class Mutation:
    def __init__(self, *, install_error=False):
        self.install_error = install_error
        self.installed = False
        self.rolled_back = False

    def install(self):
        if self.install_error:
            raise FirewallError("candidate nftables policy installation failed")
        self.installed = True

    def rollback(self):
        self.rolled_back = True


class Runner:
    def __init__(self, *, syntax_status=0, reload_status=0, restore_status=0):
        self.syntax_status = syntax_status
        self.reload_status = reload_status
        self.restore_status = restore_status
        self.calls = []

    def require(self, name):
        return f"/{name}"

    def run(self, *argv):
        self.calls.append(argv)
        if argv[0] == "/systemctl":
            return Completed(self.reload_status)
        if argv[1:3] == ("-c", "-f"):
            return Completed(self.syntax_status)
        return Completed(self.restore_status)


install_failure = Mutation(install_error=True)
expect_error(
    lambda: nftables.validate_and_apply(
        Runner(),
        install_failure,
        Path("/etc/nftables.conf"),
    ),
    "previous rules restored",
)
assert install_failure.rolled_back

syntax_failure = Mutation()
expect_error(
    lambda: nftables.validate_and_apply(
        Runner(syntax_status=1),
        syntax_failure,
        Path("/etc/nftables.conf"),
    ),
    "failed syntax validation; previous rules restored",
)
assert syntax_failure.installed and syntax_failure.rolled_back

reload_failure = Mutation()
reload_runner = Runner(reload_status=1)
expect_error(
    lambda: nftables.validate_and_apply(
        reload_runner,
        reload_failure,
        Path("/etc/nftables.conf"),
    ),
    "nftables reload failed; previous rules restored",
)
assert reload_failure.installed and reload_failure.rolled_back
assert ("/nft", "-f", "/etc/nftables.conf") in reload_runner.calls

success = Mutation()
nftables.validate_and_apply(
    Runner(),
    success,
    Path("/etc/nftables.conf"),
)
assert success.installed and not success.rolled_back

full_rules = [
    Rule(
        f"rule-{number:04d}",
        "incoming",
        "allow",
        "tcp",
        1024 + number,
        "any",
        "-",
    )
    for number in range(1, MAX_RULES + 1)
]
state_path.write_text(serialize_state(full_rules), encoding="utf-8")
mutation_attempted = False


def unexpected_apply(_paths, _rules, _runner):
    global mutation_attempted
    mutation_attempted = True


original_apply = cli._apply_rules
cli._apply_rules = unexpected_apply
try:
    expect_error(
        lambda: cli._add_rule(
            paths,
            object(),
            ["incoming", "allow", "tcp", "443", "any", "-", "confirmed-firewall-action"],
        ),
        f"managed firewall rule limit of {MAX_RULES} has been reached",
    )
finally:
    cli._apply_rules = original_apply
assert not mutation_attempted
PY
then
  pass "firewall client rejects invalid and unconfirmed requests before pkexec"
  pass "validated firewall requests normalize fixed root-helper arguments"
  pass "firewall state parsing and rendering cover any, LAN, IPv4, and IPv6 rules"
  pass "firewall mutations add, remove, and reset only managed state"
  pass "partial candidate installation restores the previous files"
  pass "nftables syntax failure restores the previous files"
  pass "nftables reload failure restores and reapplies the previous ruleset"
  pass "managed firewall state stops at 128 rules before nftables mutation"
else
  fail "firewall Python semantic harness"
fi

if grep -q '^# Managed by labwc-firewall-action-root\.$' "$firewall_state_source" &&
   grep -q '^# id[[:space:]]direction[[:space:]]verdict[[:space:]]protocol[[:space:]]port[[:space:]]scope[[:space:]]cidr$' "$firewall_state_source" &&
   grep -q '^# Managed by labwc-firewall-action-root\.$' "$firewall_fragment_source" &&
   grep -q '^# No Computer Management firewall rules are configured\.$' "$firewall_fragment_source" &&
   [ "$(grep -c '^rule-' "$firewall_state_source")" -eq 0 ]; then
  pass "repository firewall state starts empty with explicit managed ownership metadata"
else
  fail "repository firewall state starts empty with explicit managed ownership metadata"
fi
