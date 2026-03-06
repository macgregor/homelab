#!/usr/bin/env python3
"""Homelab diagnostic tool. Gathers system state across nodes, k8s, and router."""

import argparse
import json
import logging
import re
import subprocess
import sys
import time
import random
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone

# --- Constants ---

KNOWN_NODES = ["k3-m1", "k3-n1"]
KNOWN_HOSTS = ["router", "k3-m1", "k3-n1"]
ROUTER_HOST = "router"
SSH_TIMEOUT = 30
KUBECTL_TIMEOUT = 30

log = logging.getLogger("homelab-diagnose")

# --- Core Primitives ---

ANSI_RE = re.compile(r"(\x1b\[[0-9;]*[A-Za-z]|\x1b\]0;[^\x07]*\x07|\r)")


@dataclass
class CommandResult:
    command: str
    stdout: str
    stderr: str
    exit_code: int
    host: str = ""

    def to_dict(self) -> dict:
        return {
            "command": self.command,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "exit_code": self.exit_code,
            "host": self.host,
        }


class CommandError(Exception):
    pass


class HostUnreachableError(CommandError):
    pass


class CommandTimeoutError(CommandError):
    pass


@dataclass
class Check:
    title: str
    result: CommandResult
    error: CommandError | None = None

    def to_dict(self) -> dict:
        d: dict = {
            "title": self.title,
            "result": self.result.to_dict(),
        }
        if self.error is not None:
            d["error"] = type(self.error).__name__
        return d


@dataclass
class CollectorResult:
    checks: list[Check] = field(default_factory=list)
    preflight_error: CommandError | None = None

    def to_dict(self) -> dict:
        d: dict = {"checks": [c.to_dict() for c in self.checks]}
        if self.preflight_error is not None:
            d["preflight_error"] = {
                "type": type(self.preflight_error).__name__,
                "message": str(self.preflight_error),
            }
        return d


@dataclass
class SSHCollectorResult(CollectorResult):
    host: str = ""

    def to_dict(self) -> dict:
        d = super().to_dict()
        d["host"] = self.host
        return d


@dataclass
class AppCollectorResult(CollectorResult):
    name: str = ""
    namespace: str = ""

    def to_dict(self) -> dict:
        d = super().to_dict()
        d["name"] = self.name
        d["namespace"] = self.namespace
        return d


@dataclass
class DiagnosticReport:
    timestamp: str
    mode: str
    collectors: list[CollectorResult]

    def to_dict(self) -> dict:
        return {
            "timestamp": self.timestamp,
            "mode": self.mode,
            "collectors": [c.to_dict() for c in self.collectors],
        }

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent)

    def to_markdown(self) -> str:
        lines: list[str] = []
        lines.append(f"# Homelab Diagnostic Report")
        lines.append(f"")
        lines.append(f"**Timestamp:** {self.timestamp}  ")
        lines.append(f"**Mode:** {self.mode}")
        lines.append("")

        # Summary table
        lines.append("## Summary")
        lines.append("")
        lines.append("| Target | Status |")
        lines.append("|--------|--------|")
        for c in self.collectors:
            target = _collector_target(c)
            status = _collector_status(c)
            lines.append(f"| {target} | {status} |")
        lines.append("")

        # Per-collector sections
        for c in self.collectors:
            target = _collector_target(c)
            lines.append(f"## {target}")
            lines.append("")

            if c.preflight_error is not None:
                lines.append(f"**Preflight failed:** {type(c.preflight_error).__name__}: {c.preflight_error}")
                lines.append("")
                continue

            for check in c.checks:
                lines.append(f"### {check.title}")
                lines.append("")
                if check.error is not None:
                    lines.append(f"**Error:** {type(check.error).__name__}")
                    lines.append("")
                cmd_display = check.result.command
                if check.result.host:
                    cmd_display = f"ssh {check.result.host} {check.result.command}"
                lines.append(f"`{cmd_display}`")
                lines.append("")
                output = check.result.stdout.strip()
                stderr = check.result.stderr.strip()
                if output:
                    lines.append("```")
                    lines.append(output)
                    lines.append("```")
                    lines.append("")
                if stderr:
                    lines.append("stderr:")
                    lines.append("```")
                    lines.append(stderr)
                    lines.append("```")
                    lines.append("")

        return "\n".join(lines)


def _collector_target(c: CollectorResult) -> str:
    if isinstance(c, SSHCollectorResult):
        return f"Host: {c.host}"
    if isinstance(c, AppCollectorResult):
        ns = f" ({c.namespace})" if c.namespace else ""
        return f"App: {c.name}{ns}"
    return "Kubernetes Cluster"


def _collector_status(c: CollectorResult) -> str:
    if c.preflight_error is not None:
        return f"PREFLIGHT FAILED ({type(c.preflight_error).__name__})"
    failed = sum(1 for ch in c.checks if ch.error is not None)
    total = len(c.checks)
    if failed == 0:
        return f"OK ({total} checks)"
    return f"{failed}/{total} checks failed"


# --- Collectors ---


class Collector(ABC):
    def collect(self) -> CollectorResult:
        try:
            self._preflight()
        except CommandError as e:
            log.warning("Preflight failed: %s", e)
            return self._make_result([], preflight_error=e)
        log.info("Running checks")
        checks = self._run_checks()
        log.info("Completed %d checks (%d failed)", len(checks), sum(1 for c in checks if c.error))
        return self._make_result(checks)

    def run_check(self, title: str, result: CommandResult) -> Check:
        error: CommandError | None = None
        if result.exit_code == -1:
            if "timed out" in result.stderr.lower() or "timed out" in str(result.stdout).lower():
                error = CommandTimeoutError(result.stderr or "Command timed out")
            else:
                error = CommandError(result.stderr or "Infrastructure error")
        elif result.exit_code != 0:
            error = CommandError(f"Exit code {result.exit_code}: {result.stderr[:200]}" if result.stderr else f"Exit code {result.exit_code}")
        return Check(title=title, result=result, error=error)

    @abstractmethod
    def _preflight(self) -> None: ...

    @abstractmethod
    def _run_checks(self) -> list[Check]: ...

    @abstractmethod
    def _make_result(self, checks: list[Check], preflight_error: CommandError | None = None) -> CollectorResult: ...


class SSHCollector(Collector):
    def __init__(self, host: str):
        self.host = host

    def ssh(self, cmd: str, timeout: int = SSH_TIMEOUT, retries: int = 0) -> CommandResult:
        ssh_cmd = ["ssh", "-o", "BatchMode=yes", self.host, cmd]
        log.info("  ssh %s: %s", self.host, cmd[:60])
        attempt = 0
        while True:
            try:
                proc = subprocess.run(
                    ssh_cmd,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                )
                stdout = proc.stdout
                # Strip ANSI escape codes from router output
                if self.host == ROUTER_HOST:
                    stdout = ANSI_RE.sub("", stdout)
                result = CommandResult(
                    command=cmd,
                    stdout=stdout,
                    stderr=proc.stderr,
                    exit_code=proc.returncode,
                    host=self.host,
                )
                # Only retry infrastructure failures, not real nonzero exits
                if proc.returncode != 0 and attempt < retries and _is_infra_failure(proc.stderr):
                    attempt += 1
                    _backoff(attempt)
                    continue
                return result
            except subprocess.TimeoutExpired:
                if attempt < retries:
                    attempt += 1
                    _backoff(attempt)
                    continue
                return CommandResult(
                    command=cmd, stdout="", stderr="SSH command timed out",
                    exit_code=-1, host=self.host,
                )
            except FileNotFoundError:
                return CommandResult(
                    command=cmd, stdout="", stderr="ssh binary not found",
                    exit_code=-1, host=self.host,
                )

    def _preflight(self) -> None:
        log.info("Checking SSH connectivity to %s", self.host)
        result = self.ssh("echo ok", timeout=10)
        if result.exit_code != 0:
            raise HostUnreachableError(f"Cannot reach {self.host}: {result.stderr}")

    def _make_result(self, checks: list[Check], preflight_error: CommandError | None = None) -> SSHCollectorResult:
        return SSHCollectorResult(checks=checks, preflight_error=preflight_error, host=self.host)

    @abstractmethod
    def _run_checks(self) -> list[Check]: ...


class KubectlCollector(Collector):
    def kubectl(self, args: str, timeout: int = KUBECTL_TIMEOUT, retries: int = 0) -> CommandResult:
        cmd_parts = ["kubectl"] + args.split()
        log.info("  kubectl %s", args[:60])
        attempt = 0
        while True:
            try:
                proc = subprocess.run(
                    cmd_parts,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                )
                if proc.returncode != 0 and attempt < retries and _is_infra_failure(proc.stderr):
                    attempt += 1
                    _backoff(attempt)
                    continue
                return CommandResult(
                    command=f"kubectl {args}",
                    stdout=proc.stdout,
                    stderr=proc.stderr,
                    exit_code=proc.returncode,
                )
            except subprocess.TimeoutExpired:
                if attempt < retries:
                    attempt += 1
                    _backoff(attempt)
                    continue
                return CommandResult(
                    command=f"kubectl {args}", stdout="",
                    stderr="kubectl command timed out", exit_code=-1,
                )
            except FileNotFoundError:
                return CommandResult(
                    command=f"kubectl {args}", stdout="",
                    stderr="kubectl binary not found", exit_code=-1,
                )


def _is_infra_failure(stderr: str) -> bool:
    indicators = ["connection refused", "connection reset", "no route to host", "timed out"]
    lower = stderr.lower()
    return any(ind in lower for ind in indicators)


def _backoff(attempt: int) -> None:
    delay = min(2 ** attempt + random.uniform(0, 1), 10)
    log.debug("Retrying in %.1fs", delay)
    time.sleep(delay)


class RouterCollector(SSHCollector):
    def __init__(self):
        super().__init__(ROUTER_HOST)

    def _run_checks(self) -> list[Check]:
        return [
            self.run_check("System Resources", self.ssh("/system resource print")),
            self.run_check("Interfaces", self.ssh("/interface print terse")),
            self.run_check("DHCP Leases", self.ssh("/ip dhcp-server lease print")),
            self.run_check("DNS Configuration", self.ssh("/ip dns print")),
            self.run_check("Recent Errors", self.ssh('/log print where topics~"error" or topics~"critical"')),
        ]


class NodeCollector(SSHCollector):
    def __init__(self, host: str):
        super().__init__(host)

    def _run_checks(self) -> list[Check]:
        return [
            self.run_check("Uptime", self.ssh("uptime")),
            self.run_check("Memory", self.ssh("free -h")),
            self.run_check("Disk", self.ssh("df -h /")),
            self.run_check("CPU Temperature", self.ssh("awk '{printf \"%.1f°C\\n\", $1/1000}' /sys/class/thermal/thermal_zone0/temp")),
            self.run_check("k3s Service Status", self.ssh("systemctl is-active k3s")),
            self.run_check("k3s Version", self.ssh("k3s --version")),
            self.run_check("k3s Recent Errors", self.ssh("journalctl -u k3s -p err --since '1 hour ago' --no-pager -n 20")),
            self.run_check("NFS Mounts", self.ssh("mount | grep nfs")),
            self.run_check("iSCSI Sessions", self.ssh("iscsiadm -m session 2>/dev/null || echo 'No active sessions'")),
            self.run_check("iSCSI Mounts", self.ssh("mount | grep iscsi")),
        ]


class KubeCollector(KubectlCollector):
    def _preflight(self) -> None:
        log.info("Checking kubectl connectivity")
        result = self.kubectl("cluster-info", timeout=10)
        if result.exit_code != 0:
            raise CommandError(f"kubectl not reachable: {result.stderr}")

    def _run_checks(self) -> list[Check]:
        return [
            self.run_check("Nodes", self.kubectl("get nodes -o wide")),
            self.run_check("Node Conditions", self.kubectl(
                "get nodes -o custom-columns="
                "NAME:.metadata.name,"
                "READY:.status.conditions[?(@.type==\"Ready\")].status,"
                "DISK_PRESSURE:.status.conditions[?(@.type==\"DiskPressure\")].status,"
                "MEM_PRESSURE:.status.conditions[?(@.type==\"MemoryPressure\")].status,"
                "PID_PRESSURE:.status.conditions[?(@.type==\"PIDPressure\")].status"
            )),
            self.run_check("All Pods", self.kubectl("get pods -A -o wide")),
            self.run_check("Pod Health", self.kubectl(
                "get pods -A -o custom-columns="
                "NAMESPACE:.metadata.namespace,"
                "NAME:.metadata.name,"
                "READY:.status.conditions[?(@.type==\"ContainersReady\")].status,"
                "PHASE:.status.phase,"
                "RESTARTS:.status.containerStatuses[0].restartCount"
            )),
            self.run_check("Warning Events", self.kubectl("get events -A --field-selector type=Warning --sort-by=.lastTimestamp")),
            self.run_check("Persistent Volumes", self.kubectl("get pv,pvc -A")),
            self.run_check("LoadBalancer Services", self.kubectl("get svc -A --field-selector spec.type=LoadBalancer")),
            self.run_check("Ingress", self.kubectl("get ingress -A")),
            self.run_check("Certificates", self.kubectl(
                "get certificates -A -o custom-columns="
                "NAMESPACE:.metadata.namespace,"
                "NAME:.metadata.name,"
                "READY:.status.conditions[?(@.type==\"Ready\")].status,"
                "EXPIRY:.status.notAfter,"
                "RENEWAL:.status.renewalTime"
            )),
            self.run_check("Resource Usage", self.kubectl("top nodes")),
            self.run_check("Pod Resource Usage", self.kubectl("top pods -A --sort-by=memory")),
        ]

    def _make_result(self, checks: list[Check], preflight_error: CommandError | None = None) -> CollectorResult:
        return CollectorResult(checks=checks, preflight_error=preflight_error)


class AppCollector(KubectlCollector):
    def __init__(self, name: str):
        self.name = name
        self.namespace = ""

    def _preflight(self) -> None:
        log.info("Discovering app: %s", self.name)
        result = self.kubectl(f"get deploy,sts -A -l app.kubernetes.io/name={self.name} -o jsonpath={{.items[0].metadata.namespace}}")
        if result.exit_code != 0 or not result.stdout.strip():
            raise CommandError(f"App '{self.name}' not found in cluster")
        self.namespace = result.stdout.strip()
        log.info("Found app %s in namespace %s", self.name, self.namespace)

    def _run_checks(self) -> list[Check]:
        ns = self.namespace
        label = f"app.kubernetes.io/name={self.name}"
        return [
            self.run_check("Pod Details", self.kubectl(f"-n {ns} describe pod -l {label}")),
            self.run_check("Logs", self.kubectl(f"-n {ns} logs -l {label} --tail=100")),
            self.run_check("Events", self.kubectl(f"-n {ns} get events --sort-by=.lastTimestamp")),
            self.run_check("Resources", self.kubectl(f"-n {ns} get svc,endpoints,ingress,pvc -l {label}")),
        ]

    def _make_result(self, checks: list[Check], preflight_error: CommandError | None = None) -> AppCollectorResult:
        return AppCollectorResult(
            checks=checks, preflight_error=preflight_error,
            name=self.name, namespace=self.namespace,
        )


# --- CLI ---


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Homelab diagnostic tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--output", "-o", choices=["md", "json"], default="md",
        help="Output format (default: md)",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Enable debug logging",
    )

    subparsers = parser.add_subparsers(dest="command")

    node_parser = subparsers.add_parser("node", help="Diagnose cluster nodes")
    node_parser.add_argument("name", nargs="?", choices=KNOWN_NODES, help="Node to diagnose (default: all)")

    app_parser = subparsers.add_parser("app", help="App-specific deep dive")
    app_parser.add_argument("name", help="Application name")

    subparsers.add_parser("kube", help="Cluster-wide Kubernetes state")
    subparsers.add_parser("router", help="MikroTik router diagnostics")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )

    collectors: list[Collector] = []
    mode = args.command or "full"

    if mode == "full":
        collectors.append(RouterCollector())
        for node in KNOWN_NODES:
            collectors.append(NodeCollector(node))
        collectors.append(KubeCollector())
    elif mode == "router":
        collectors.append(RouterCollector())
    elif mode == "node":
        nodes = [args.name] if args.name else KNOWN_NODES
        for node in nodes:
            collectors.append(NodeCollector(node))
    elif mode == "kube":
        collectors.append(KubeCollector())
    elif mode == "app":
        collectors.append(AppCollector(args.name))

    results: list[CollectorResult] = []
    for collector in collectors:
        results.append(collector.collect())

    report = DiagnosticReport(
        timestamp=datetime.now(timezone.utc).isoformat(),
        mode=mode,
        collectors=results,
    )

    if args.output == "json":
        print(report.to_json())
    else:
        print(report.to_markdown())


if __name__ == "__main__":
    main()
