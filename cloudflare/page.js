'use strict';
document.getElementById('cf-file').addEventListener('change', async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const status = document.getElementById('cf-status');
  const table = document.getElementById('cf-results'); table.replaceChildren();
  try {
    if (file.size > 1024 * 1024) throw new Error('文件不能超过 1 MB。');
    const report = JSON.parse(await file.text());
    if (!Array.isArray(report.results) || !report.results.length || report.results.length > 64) throw new Error('需要包含 1–64 条 results 的执行器 JSON。');
    const finite = (n) => typeof n === 'number' && Number.isFinite(n) && n >= 0;
    const rows = report.results;
    for (const r of rows) {
      if (typeof r.ip !== 'string' || !/^(?:\d{1,3}\.){3}\d{1,3}$/.test(r.ip) || r.ip.split('.').some(n => Number(n) > 255) || !Number.isInteger(r.attempts) || r.attempts < 1 || r.attempts > 30 || !Number.isInteger(r.successes) || r.successes < 0 || r.successes > r.attempts || !finite(r.failureRate) || r.failureRate > 1 || Math.abs(r.failureRate - (1 - r.successes / r.attempts)) > 0.0001 || (r.latencyMs !== null && !finite(r.latencyMs)) || (r.downloadMbps !== null && !finite(r.downloadMbps)) || (r.successes === 0 && r.latencyMs !== null) || !Array.isArray(r.errors) || r.errors.length > 30 || r.errors.some(e => typeof e !== 'string' || e.length > 2000)) throw new Error('文件含无效测量字段；请选择执行器原始导出文件。');
    }
    rows.sort((a, b) => (a.latencyMs === null) - (b.latencyMs === null) || a.failureRate - b.failureRate || (a.latencyMs ?? Infinity) - (b.latencyMs ?? Infinity));
    for (const r of rows) {
      const tr = document.createElement('tr');
      const values = [r.ip, `${r.successes}/${r.attempts}`, `${(r.failureRate * 100).toFixed(0)}%`, r.latencyMs === null ? '—' : `${r.latencyMs.toFixed(1)} ms`, r.downloadMbps === null ? '—' : `${r.downloadMbps.toFixed(2)} Mbps`, r.errors.length ? r.errors.join('；') : '有效响应'];
      for (const value of values) { const td = document.createElement('td'); td.textContent = value; tr.append(td); }
      table.append(tr);
    }
    const count = rows.filter(r => r.latencyMs !== null).length;
    status.textContent = `已导入 ${rows.length} 个候选，其中 ${count} 个有有效 HTTPS 耗时。来源为你选择的文件，网页未重新测量。`;
  } catch (error) { status.textContent = `无法导入：${error.message}`; }
});

for (const button of document.querySelectorAll('[data-copy-target]')) {
  button.addEventListener('click', async () => {
    const output = document.getElementById('cf-copy-status');
    try {
      await navigator.clipboard.writeText(document.getElementById(button.dataset.copyTarget).textContent);
      output.textContent = '已复制。请在对应系统的终端中粘贴并运行，等待脚本报告服务就绪。';
    } catch (_) {
      output.textContent = '浏览器未允许复制，请手动选择上方整段命令。';
    }
  });
}
