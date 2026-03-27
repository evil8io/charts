#!/usr/bin/env python3
"""Syslog traffic generator with realistic multi-profile messages."""

import argparse
import json
import logging
import os
import random
import signal
import socket
import sys
import time
from datetime import datetime, timezone

logger = logging.getLogger("syslog-loadgen")

FACILITIES = {
    "kern": 0, "user": 1, "mail": 2, "daemon": 3,
    "auth": 4, "syslog": 5, "lpr": 6, "news": 7,
    "uucp": 8, "cron": 9, "authpriv": 10, "ftp": 11,
    "local0": 16, "local1": 17, "local2": 18, "local3": 19,
    "local4": 20, "local5": 21, "local6": 22, "local7": 23,
}

SEVERITIES = {
    "emerg": 0, "alert": 1, "crit": 2, "error": 3,
    "warning": 4, "notice": 5, "info": 6, "debug": 7,
}

PROFILES = {
    "firewall": {
        "hostnames": ["fw-01.dc1.local", "fw-02.dc1.local"],
        "program": "fortigate",
        "facility": "local0",
        "format": "rfc5424",
        "severity_weights": {"info": 60, "notice": 10, "warning": 15, "error": 10, "crit": 5},
        "templates": [
            {
                "msg": "id=20085 trace_id={trace_id} func=firewall_local_in_handler line=122 msg=\"iprope_in_check() check failed on policy 0, drop\"",
                "sd": "[origin ip=\"{src_ip}\"][meta sequenceId=\"{seq}\" eventId=\"0100020085\"]",
            },
            {
                "msg": "id=20001 trace_id={trace_id} func=ipsengine_process line=836 msg=\"close={src_ip}:{src_port}->{dst_ip}:{dst_port} proto=6 service=HTTPS duration={duration} sent={sent} rcvd={rcvd} action=accept\"",
                "sd": "[origin ip=\"{src_ip}\"][meta sequenceId=\"{seq}\" eventId=\"0100020001\"]",
            },
            {
                "msg": "id=20010 trace_id={trace_id} func=fw_forward_handler line=789 msg=\"Allowed by policy {policy_id}: {src_ip}:{src_port}->{dst_ip}:{dst_port} proto=6\"",
                "sd": "[origin ip=\"{src_ip}\"][meta sequenceId=\"{seq}\" eventId=\"0100020010\"]",
            },
            {
                "msg": "id=20015 trace_id={trace_id} func=fw_forward_handler line=802 msg=\"Denied by policy {policy_id}: {src_ip}:{src_port}->{dst_ip}:{dst_port} proto=17\"",
                "sd": "[origin ip=\"{src_ip}\"][meta sequenceId=\"{seq}\" eventId=\"0100020015\"]",
            },
            {
                "msg": "id=37138 trace_id={trace_id} func=ike_phase1_main line=410 msg=\"IPsec tunnel {tunnel_name} phase1 up\"",
                "sd": "[origin ip=\"{src_ip}\"][meta sequenceId=\"{seq}\" eventId=\"0100037138\"]",
            },
        ],
    },
    "switch": {
        "hostnames": ["sw-core-01.dc1.local", "sw-core-02.dc1.local", "sw-access-01.dc1.local"],
        "program": "nos",
        "facility": "local0",
        "format": "rfc5424",
        "severity_weights": {"info": 40, "notice": 15, "warning": 25, "error": 15, "crit": 5},
        "templates": [
            {"msg": "Interface {iface} link-state changed to up", "sd": "-"},
            {"msg": "Interface {iface} link-state changed to down", "sd": "-"},
            {"msg": "BGP neighbor {peer_ip} state changed from Established to Idle (hold timer expired)", "sd": "-"},
            {"msg": "BGP neighbor {peer_ip} state changed from Idle to Established", "sd": "-"},
            {"msg": "STP topology change detected on port {iface}, transitioning to forwarding", "sd": "-"},
            {"msg": "Port {iface} security violation: MAC address {mac} not allowed", "sd": "-"},
        ],
    },
    "sshd": {
        "hostnames": ["web-01.prod.local", "web-02.prod.local", "web-03.prod.local", "web-04.prod.local", "web-05.prod.local"],
        "program": "sshd",
        "facility": "auth",
        "format": "rfc3164",
        "severity_weights": {"info": 70, "warning": 15, "error": 10, "crit": 5},
        "templates": [
            {"msg": "Accepted publickey for {user} from {src_ip} port {src_port} ssh2: RSA SHA256:{fingerprint}"},
            {"msg": "Failed password for {user} from {src_ip} port {src_port} ssh2"},
            {"msg": "Failed password for invalid user {user} from {src_ip} port {src_port} ssh2"},
            {"msg": "Disconnected from user {user} {src_ip} port {src_port}"},
            {"msg": "Connection closed by authenticating user {user} {src_ip} port {src_port} [preauth]"},
            {"msg": "Invalid user {user} from {src_ip} port {src_port}"},
        ],
    },
    "sudo": {
        "hostnames": ["web-01.prod.local", "web-02.prod.local", "web-03.prod.local", "web-04.prod.local", "web-05.prod.local"],
        "program": "sudo",
        "facility": "auth",
        "format": "rfc3164",
        "severity_weights": {"info": 80, "notice": 15, "error": 5},
        "templates": [
            {"msg": "{user} : TTY=pts/{tty} ; PWD={pwd} ; USER=root ; COMMAND={cmd}"},
            {"msg": "{user} : 3 incorrect password attempts ; TTY=pts/{tty} ; PWD={pwd} ; USER=root ; COMMAND={cmd}"},
        ],
    },
    "kernel": {
        "hostnames": [f"node-{i:02d}.k8s.local" for i in range(1, 11)],
        "program": "kernel",
        "facility": "kern",
        "format": "rfc3164",
        "severity_weights": {"info": 10, "warning": 35, "error": 30, "crit": 20, "alert": 5},
        "templates": [
            {"msg": "Out of memory: Killed process {pid} ({proc}) total-vm:{vm_kb}kB, anon-rss:{rss_kb}kB, file-rss:0kB, shmem-rss:0kB, UID:{uid} pgtables:{pgtables}kB oom_score_adj:{oom_adj}"},
            {"msg": "{proc}[{pid}]: segfault at {hex_addr} ip {hex_addr} sp {hex_addr} error 4 in {lib}[{hex_addr}+{hex_offset}]"},
            {"msg": "iptables: DROP IN=eth0 OUT= MAC={mac} SRC={src_ip} DST={dst_ip} LEN={pkt_len} TOS=0x00 PREC=0x00 TTL=64 ID={pkt_id} PROTO=TCP SPT={src_port} DPT={dst_port} WINDOW=65535 RES=0x00 SYN URGP=0"},
            {"msg": "EXT4-fs (sda1): error count since last fsck: {error_count}"},
            {"msg": "NMI watchdog: BUG: soft lockup - CPU#{cpu_id} stuck for {lockup_secs}s! [{proc}:{pid}]"},
        ],
    },
    "nginx": {
        "hostnames": ["web-01.prod.local", "web-02.prod.local", "web-03.prod.local", "web-04.prod.local", "web-05.prod.local"],
        "program": "nginx",
        "facility": "local7",
        "format": "rfc3164",
        "severity_weights": {"info": 85, "warning": 10, "error": 5},
        "templates": [
            {"msg": "{src_ip} - {user_or_dash} [{clf_time}] \"{method} {path} HTTP/1.1\" {status} {bytes} \"{referer}\" \"{ua}\""},
        ],
    },
    "postfix": {
        "hostnames": ["mail-01.corp.local", "mail-02.corp.local"],
        "program": "postfix/smtp",
        "facility": "mail",
        "format": "rfc3164",
        "severity_weights": {"info": 75, "warning": 15, "error": 10},
        "templates": [
            {"msg": "{queue_id}: to=<{to_addr}>, relay={relay_host}[{relay_ip}]:25, delay={delay}, delays={delays}, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as {remote_queue_id})", "program": "postfix/smtp"},
            {"msg": "{queue_id}: from=<{from_addr}>, size={mail_size}, nrcpt=1 (queue active)", "program": "postfix/qmgr"},
            {"msg": "{queue_id}: message-id=<{msg_id}@{mail_domain}>", "program": "postfix/cleanup"},
            {"msg": "connect from {client_host}[{src_ip}]", "program": "postfix/smtpd"},
            {"msg": "disconnect from {client_host}[{src_ip}] ehlo=1 mail=1 rcpt=1 data=1 quit=1 commands=5", "program": "postfix/smtpd"},
            {"msg": "{queue_id}: to=<{to_addr}>, relay=none, delay={delay}, delays={delays}, dsn=4.4.1, status=deferred (connect to {relay_host}[{relay_ip}]:25: Connection timed out)", "program": "postfix/smtp"},
        ],
    },
}

# Randomization pools
USERNAMES = ["admin", "root", "deploy", "ubuntu", "ec2-user", "jenkins", "gitlab", "ansible", "www-data", "nginx"]
COMMANDS = ["/usr/bin/systemctl restart nginx", "/bin/journalctl -u sshd", "/usr/bin/apt update",
            "/usr/sbin/reboot", "/bin/cat /etc/shadow", "/usr/bin/docker ps", "/usr/bin/crictl pods"]
PATHS = ["/home/admin", "/var/log", "/etc/nginx", "/opt/app", "/tmp", "/root", "/srv/www"]
HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"]
HTTP_PATHS = ["/", "/api/v1/users", "/api/v1/health", "/login", "/static/js/app.js",
              "/static/css/main.css", "/api/v1/orders", "/api/v1/metrics", "/favicon.ico",
              "/api/v2/search?q=test", "/assets/logo.png", "/graphql"]
HTTP_STATUSES = [200, 200, 200, 200, 200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 404, 500, 502, 503]
HTTP_REFERERS = ["-", "https://example.com/", "https://example.com/login", "https://www.google.com/"]
USER_AGENTS = [
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15",
    "curl/8.7.1", "python-requests/2.32.3", "Go-http-client/2.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0",
]
INTERFACES = [f"Gi0/{i}" for i in range(1, 49)] + ["Gi1/0/1", "Gi1/0/2", "Te0/1", "Te0/2"]
PROCESSES = ["java", "python3", "node", "nginx", "redis-server", "postgres", "containerd-shim"]
TUNNEL_NAMES = ["vpn-dc2", "vpn-branch-01", "vpn-branch-02", "ipsec-partner-a", "ipsec-partner-b"]
MAIL_DOMAINS = ["corp.local", "example.com", "partner.net", "client.org"]
CLIENT_HOSTS = ["mail-relay.partner.net", "smtp.client.org", "mx1.example.com", "unknown"]
RELAY_HOSTS = ["mx1.example.com", "mx2.example.com", "aspmx.l.google.com", "mail.corp.local"]
LIBRARIES = ["libc-2.31.so", "libpthread-2.31.so", "ld-2.31.so", "libssl.so.1.1", "libz.so.1"]

_seq = 0
_shutdown = False


def signal_handler(signum, frame):
    global _shutdown
    _shutdown = True
    logger.info("Shutdown signal received")


def next_seq():
    global _seq
    _seq += 1
    return _seq


def random_ip():
    return f"10.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"


def random_public_ip():
    return f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"


def random_port():
    return random.randint(1024, 65535)


def random_pid():
    return random.randint(100, 65535)


def random_mac():
    return ":".join(f"{random.randint(0, 255):02x}" for _ in range(6))


def random_hex(length=8):
    return f"0x{random.getrandbits(length * 4):0{length}x}"


def random_fingerprint():
    return "".join(random.choices("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", k=43))


def random_queue_id():
    return "".join(random.choices("0123456789ABCDEF", k=10))


def random_msg_id():
    return "".join(random.choices("0123456789abcdef", k=16))


def random_trace_id():
    return "".join(random.choices("0123456789abcdef", k=16))


def pick_severity(weights):
    names = list(weights.keys())
    w = [weights[n] for n in names]
    return random.choices(names, weights=w, k=1)[0]


def priority(facility_name, severity_name):
    return FACILITIES[facility_name] * 8 + SEVERITIES[severity_name]


def fill_template(tmpl_str):
    now = datetime.now(timezone.utc)
    return tmpl_str.format(
        src_ip=random_ip(),
        dst_ip=random_ip(),
        peer_ip=random_ip(),
        relay_ip=random_ip(),
        src_port=random_port(),
        dst_port=random_port(),
        pid=random_pid(),
        seq=next_seq(),
        trace_id=random_trace_id(),
        duration=random.randint(1, 3600),
        sent=random.randint(100, 10_000_000),
        rcvd=random.randint(100, 10_000_000),
        policy_id=random.randint(1, 200),
        tunnel_name=random.choice(TUNNEL_NAMES),
        iface=random.choice(INTERFACES),
        mac=random_mac(),
        user=random.choice(USERNAMES),
        user_or_dash=random.choice(["-", "-", "-"] + USERNAMES[:4]),
        tty=random.randint(0, 9),
        pwd=random.choice(PATHS),
        cmd=random.choice(COMMANDS),
        proc=random.choice(PROCESSES),
        vm_kb=random.randint(100_000, 8_000_000),
        rss_kb=random.randint(50_000, 4_000_000),
        uid=random.randint(0, 65534),
        pgtables=random.randint(100, 50_000),
        oom_adj=random.choice([0, 0, 0, 100, 500, 999, 1000]),
        hex_addr=random_hex(16),
        hex_offset=random_hex(4),
        lib=random.choice(LIBRARIES),
        pkt_len=random.randint(40, 1500),
        pkt_id=random.randint(1, 65535),
        error_count=random.randint(1, 500),
        cpu_id=random.randint(0, 15),
        lockup_secs=random.randint(22, 120),
        fingerprint=random_fingerprint(),
        method=random.choice(HTTP_METHODS),
        path=random.choice(HTTP_PATHS),
        status=random.choice(HTTP_STATUSES),
        bytes=random.randint(0, 500_000),
        referer=random.choice(HTTP_REFERERS),
        ua=random.choice(USER_AGENTS),
        clf_time=now.strftime("%d/%b/%Y:%H:%M:%S +0000"),
        queue_id=random_queue_id(),
        remote_queue_id=random_queue_id(),
        msg_id=random_msg_id(),
        from_addr=f"{random.choice(USERNAMES)}@{random.choice(MAIL_DOMAINS)}",
        to_addr=f"{random.choice(USERNAMES)}@{random.choice(MAIL_DOMAINS)}",
        mail_domain=random.choice(MAIL_DOMAINS),
        relay_host=random.choice(RELAY_HOSTS),
        client_host=random.choice(CLIENT_HOSTS),
        delay=f"{random.uniform(0.1, 30.0):.1f}",
        delays=f"{random.uniform(0, 1):.2f}/{random.uniform(0, 1):.2f}/{random.uniform(0, 5):.2f}/{random.uniform(0, 10):.2f}",
        mail_size=random.randint(200, 5_000_000),
    )


def format_rfc3164(pri, hostname, program, pid, message):
    now = datetime.now(timezone.utc)
    ts = now.strftime("%b %d %H:%M:%S")
    # Pad single-digit day with space (BSD format)
    if ts[4] == "0":
        ts = ts[:4] + " " + ts[5:]
    return f"<{pri}>{ts} {hostname} {program}[{pid}]: {message}"


def format_rfc5424(pri, hostname, program, pid, msg_id, sd, message):
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond:06d}+00:00"
    return f"<{pri}>1 {ts} {hostname} {program} {pid} {msg_id} {sd} {message}"


def generate_message(profile_name, profile):
    tmpl = random.choice(profile["templates"])
    sev = pick_severity(profile["severity_weights"])
    pri = priority(profile["facility"], sev)
    hostname = random.choice(profile["hostnames"])
    pid = random_pid()

    # Determine program: per-template override (postfix) or profile default
    program = tmpl.get("program", profile.get("program", profile_name))

    msg = fill_template(tmpl["msg"])

    if profile["format"] == "rfc5424":
        sd = fill_template(tmpl.get("sd", "-"))
        msg_id = f"ID{next_seq()}"
        return format_rfc5424(pri, hostname, program, pid, msg_id, sd, msg)
    else:
        return format_rfc3164(pri, hostname, program, pid, msg)


class TCPSender:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sock = None
        self.backoff = 1

    def connect(self):
        while not _shutdown:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(10)
                s.connect((self.host, self.port))
                s.settimeout(None)
                self.sock = s
                self.backoff = 1
                logger.info("TCP connected to %s:%d", self.host, self.port)
                return
            except OSError as e:
                logger.warning("TCP connect failed (%s), retrying in %ds", e, self.backoff)
                time.sleep(self.backoff)
                self.backoff = min(self.backoff * 2, 30)

    def send(self, message):
        data = (message + "\n").encode("utf-8")
        while not _shutdown:
            if self.sock is None:
                self.connect()
                if _shutdown:
                    return
            try:
                self.sock.sendall(data)
                return
            except OSError:
                logger.warning("TCP send failed, reconnecting")
                try:
                    self.sock.close()
                except OSError:
                    pass
                self.sock = None

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass


class UDPSender:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def send(self, message):
        data = message.encode("utf-8")
        try:
            self.sock.sendto(data, (self.host, self.port))
        except OSError as e:
            logger.warning("UDP send failed: %s", e)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def build_weighted_pool(profiles_config):
    pool = []
    for name, prof_def in PROFILES.items():
        cfg = profiles_config.get(name, {})
        if not cfg.get("enabled", True):
            continue
        weight = cfg.get("weight", 10)
        pool.append((name, prof_def, weight))
    if not pool:
        logger.error("No profiles enabled, exiting")
        sys.exit(1)
    return pool


def main():
    parser = argparse.ArgumentParser(description="Syslog traffic generator")
    parser.add_argument("--rate", type=float, default=1, help="Messages per second")
    parser.add_argument("--host", required=True, help="Target host")
    parser.add_argument("--port", type=int, default=514, help="Target port")
    parser.add_argument("--transport", choices=["tcp", "udp"], default="tcp", help="Transport protocol")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    profiles_config = json.loads(os.environ.get("LOADGEN_PROFILES", "{}"))
    pool = build_weighted_pool(profiles_config)
    names, defs, weights = zip(*pool)

    logger.info("Starting syslog-loadgen: rate=%.1f msg/s, target=%s:%d/%s",
                 args.rate, args.host, args.port, args.transport)
    logger.info("Enabled profiles: %s", ", ".join(f"{n} (w={w})" for n, _, w in pool))

    if args.transport == "tcp":
        sender = TCPSender(args.host, args.port)
        sender.connect()
    else:
        sender = UDPSender(args.host, args.port)

    interval = 1.0 / args.rate if args.rate > 0 else 1.0
    next_send = time.monotonic()

    try:
        while not _shutdown:
            now = time.monotonic()
            if now < next_send:
                time.sleep(next_send - now)

            idx = random.choices(range(len(names)), weights=weights, k=1)[0]
            msg = generate_message(names[idx], defs[idx])
            sender.send(msg)

            next_send += interval
            # Prevent drift accumulation if we fall behind
            if next_send < time.monotonic() - 1.0:
                next_send = time.monotonic()
    finally:
        sender.close()
        logger.info("Shutdown complete")


if __name__ == "__main__":
    main()
