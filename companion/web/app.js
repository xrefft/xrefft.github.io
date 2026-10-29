'use strict';
const $ = (id) => document.getElementById(id);
let token = '', controller = null, report = null;
const status = (message) => { $('status').textContent = message; };
function render(results) {
  $('results').replaceChildren();
  for (const r of results) {
    const tr = document.createElement('tr');
    const values = [r.ip, `${r.successes}/${r.attempts}`, `${(r.failureRate * 100).toFixed(0)}%`, r.latencyMs == null ? '—' : `${r.latencyMs.toFixed(1)} ms`, r.downloadMbps == null ? '—' : `${r.downloadMbps.toFixed(2)} Mbps`, r.errors.length ? r.errors.join('；') : '有效响应'];
    for (const value of values) { const td = document.createElement('td'); td.textContent = value; tr.append(td); }
    $('results').append(tr);
  }
}
async function connect() {
  try {
    const response = await fetch('/api/info', {cache: 'no-store'});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const info = await response.json(); token = info.token;
    $('version').textContent = `执行器 ${info.version}`;
    status('本机执行器已就绪。测速会产生所选下载流量。');
  } catch (error) { status(`无法连接执行器：${error.message}。请重新打开测速工具。`); $('start').disabled = true; }
}
$('probe-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const ips = [...new Set($('ips').value.trim().split(/[\s,;]+/).filter(Boolean))];
  if (!ips.length || ips.length > 64) return status('请输入 1–64 个 Cloudflare IPv4 地址。');
  controller = new AbortController(); report = null;
  $('start').disabled = true; $('stop').disabled = false; $('export').disabled = true;
  $('results').replaceChildren();
  status(`正在测量 ${ips.length} 个 IP；每个请求最多等待 5 秒。请保持当前网络稳定。`);
  try {
    const response = await fetch('/api/test', {method: 'POST', headers: {'Content-Type': 'application/json', 'X-Session-Token': token}, body: JSON.stringify({ips, host: 'speed.cloudflare.com', samples: Number($('samples').value), downloadBytes: Number($('download').value)}), signal: controller.signal});
    if (!response.ok) throw new Error((await response.text()).slice(0, 400));
    report = await response.json(); report.measuredAt = new Date().toISOString(); report.measurement = 'local HTTPS to fixed Cloudflare IP; not ICMP';
    render(report.results); $('export').disabled = false;
    const valid = report.results.filter(r => r.latencyMs != null).length;
    status(valid ? `测速完成：${valid}/${ips.length} 个 IP 获得有效 HTTPS 响应。已按失败率、耗时排序。` : '没有获得有效结果。请检查网络或更换候选 IP；失败耗时不会参与优选。');
  } catch (error) { status(error.name === 'AbortError' ? '已停止测速。未完成的数据不会作为结果。' : `测速未完成：${error.message}`); }
  finally { controller = null; $('start').disabled = false; $('stop').disabled = true; }
});
$('stop').addEventListener('click', () => controller?.abort());
$('export').addEventListener('click', () => {
  if (!report) return;
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], {type: 'application/json'}));
  const a = document.createElement('a'); a.href = url; a.download = 'cf-results.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
});
connect();
