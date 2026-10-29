#!/usr/bin/env python3
"""在本机直连 Cloudflare IP，保留域名和 TLS 证书校验。仅使用 Python 标准库。"""

import argparse
import http.client
import ipaddress
import json
import os
from pathlib import Path
import socket
import ssl
import statistics
import time

HOST = "speed.cloudflare.com"
DEFAULT_IPS = ["104.16.0.1", "104.17.0.1", "104.18.0.1", "104.19.0.1",
               "104.20.0.1", "172.64.0.1", "162.159.0.1", "188.114.96.1"]
# Cloudflare 公布的 IPv4 段；固定白名单，禁止把本地网络或任意服务器当探测目标。
NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"))
ATTEMPTS = 3
TIMEOUT = 5
DOWNLOAD_BYTES = 1_000_000


def parse_ips(value):
    values = value.replace(",", " ").split()
    if not values or len(values) > 32:
        raise ValueError("请输入 1–32 个 IPv4 地址，以空格或逗号分隔")
    result = []
    for value in values:
        ip = ipaddress.IPv4Address(value)
        if not any(ip in network for network in NETWORKS):
            raise ValueError("不在 Cloudflare IPv4 白名单中：" + str(ip))
        if str(ip) not in result:
            result.append(str(ip))
    return result


def request(ip, byte_count, context):
    start = time.monotonic()
    deadline = start + TIMEOUT
    raw = socket.create_connection((ip, 443), timeout=TIMEOUT)
    try:
        raw.settimeout(max(0.001, deadline - time.monotonic()))
        connection = context.wrap_socket(raw, server_hostname=HOST)
    except BaseException:
        raw.close()
        raise
    with connection:
        if connection.getpeername()[0] != ip:
            raise ValueError("实际远端 IP 与候选 IP 不符")
        connection.settimeout(max(0.001, deadline - time.monotonic()))
        connection.sendall(("GET /__down?bytes=%d HTTP/1.1\r\nHost: %s\r\n"
                            "Connection: close\r\nAccept-Encoding: identity\r\n"
                            "User-Agent: Cloudflare-IP-Probe/1\r\n\r\n"
                            % (byte_count, HOST)).encode("ascii"))
        response = http.client.HTTPResponse(connection)
        response.begin()
        if response.status != 200:
            raise ValueError("HTTP %d" % response.status)
        if response.getheader("Content-Encoding", "identity") != "identity":
            raise ValueError("响应意外压缩")
        received = 0
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("请求超过 5 秒")
            connection.settimeout(remaining)
            chunk = response.read(min(65536, byte_count + 1 - received))
            if not chunk:
                break
            received += len(chunk)
            if received > byte_count:
                raise ValueError("响应大小超过预期")
        if received != byte_count:
            raise ValueError("响应大小不符：%d/%d" % (received, byte_count))
        elapsed = time.monotonic() - start
        return elapsed * 1000, received, received * 8 / elapsed / 1_000_000


def probe(ip, context):
    latencies, speeds, errors = [], [], []
    received = 0
    successes = 0
    for attempt in range(ATTEMPTS):
        try:
            latency, _, _ = request(ip, 0, context)
            latencies.append(latency)
            successes += 1
        except (OSError, ValueError, http.client.HTTPException) as exc:
            errors.append("第 %d 轮延迟：%s: %s" % (attempt + 1, type(exc).__name__, exc))
        try:
            _, size, speed = request(ip, DOWNLOAD_BYTES, context)
            speeds.append(speed)
            received += size
            successes += 1
        except (OSError, ValueError, http.client.HTTPException) as exc:
            errors.append("第 %d 轮下载：%s: %s" % (attempt + 1, type(exc).__name__, exc))
    attempts = ATTEMPTS * 2
    return {"ip": ip, "successes": successes, "attempts": attempts,
            "failureRate": (attempts - successes) / attempts,
            "latencyMs": statistics.median(latencies) if latencies else None,
            "downloadMbps": statistics.median(speeds) if speeds else None,
            "bytes": received, "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ips", help="最多 32 个 Cloudflare IPv4，逗号或空格分隔")
    parser.add_argument("--interactive", action="store_true", help="运行后手动输入候选 IP")
    parser.add_argument("--defaults", action="store_true", help="使用默认 8 个 IP，无需交互")
    parser.add_argument("--output", help="结果 JSON 保存路径")
    args = parser.parse_args()
    value = args.ips
    if args.defaults and (args.ips or args.interactive):
        parser.error("--defaults 不能与 --ips 或 --interactive 一起使用")
    if args.interactive:
        value = input("输入候选 IPv4（留空使用默认 8 个）：").strip() or None
    try:
        ips = parse_ips(value) if value else DEFAULT_IPS
    except ValueError as exc:
        parser.error(str(exc))
    context = ssl.create_default_context()
    results = []
    for index, ip in enumerate(ips, 1):
        print("[%d/%d] 正在测试 %s" % (index, len(ips), ip), flush=True)
        result = probe(ip, context)
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    results.sort(key=lambda item: (item["failureRate"], item["latencyMs"]
                                  if item["latencyMs"] is not None else float("inf")))
    output = Path(args.output).expanduser() if args.output else Path.cwd() / "cf-results.json"
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(json.dumps({"results": results}, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    os.replace(temporary, output)
    print("结果已保存：%s；请回到网页上传此 JSON。" % output, flush=True)


if __name__ == "__main__":
    main()
