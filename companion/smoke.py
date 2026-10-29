#!/usr/bin/env python3
"""启动真实执行器并向 Cloudflare 发真实 HTTPS 请求；无 mock 或替代响应。"""
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = 'http://127.0.0.1:38479'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def fetch(path, payload=None, token='', origin=BASE):
    headers = {'Origin': origin}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers.update({'Content-Type': 'application/json', 'X-Session-Token': token})
    request = urllib.request.Request(BASE + path, data=data, headers=headers)
    with opener.open(request, timeout=40) as response:
        return json.load(response)


with socket.socket() as preflight:
    if sys.platform != 'win32':
        preflight.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    preflight.bind(('127.0.0.1', 38479))
process = subprocess.Popen([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    for attempt in range(100):
        if process.poll() is not None:
            raise RuntimeError(process.stdout.read().decode(errors='replace'))
        try:
            info = fetch('/api/info')
            break
        except (OSError, urllib.error.URLError):
            if process.poll() is not None:
                raise RuntimeError(process.stdout.read().decode(errors='replace'))
            time.sleep(0.1)
    else:
        raise RuntimeError('执行器未就绪')
    assert info['app'] == 'cf-speed' and len(info['token']) == 64
    payload = {'ips': ['104.16.0.1'], 'host': 'speed.cloudflare.com', 'samples': 1, 'downloadBytes': 1000000}
    for test_origin, token in [('https://example.com', info['token']), (BASE, 'invalid')]:
        try:
            fetch('/api/test', payload, token, test_origin)
            raise AssertionError('跨站/错误 token 请求未被拒绝')
        except urllib.error.HTTPError as error:
            assert error.code == 403
    try:
        fetch('/api/test', dict(payload, ips=['127.0.0.1']), info['token'])
        raise AssertionError('本地网络候选未被拒绝')
    except urllib.error.HTTPError as error:
        assert error.code == 400
    # 尝试两个真实候选；任何成功必须来自服务端实际响应且完整读取 1MB。
    evidence = []
    for ip in ['104.16.0.1', '162.159.140.220']:
        response = fetch('/api/test', dict(payload, ips=[ip]), info['token'])
        result = response['results'][0]
        evidence.append(result)
        if result['latencyMs'] is not None and result['downloadMbps'] is not None and result['bytes'] == 1000000:
            print(json.dumps({'realNetworkEvidence': evidence}, ensure_ascii=False))
            break
    else:
        raise RuntimeError('真实 Cloudflare 测试无有效下载：' + json.dumps(evidence, ensure_ascii=False))
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
