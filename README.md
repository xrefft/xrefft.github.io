# 一页障目

中文静态博客，使用 Jekyll 4.4 和自有轻量模板，由 GitHub Actions 构建并发布到 https://xrefft.github.io。

## 本地预览

安装 Ruby 3.4（版本管理器可以读取 `.ruby-version`）和 Bundler，然后运行：

```sh
script/bootstrap
script/server
```

打开 http://localhost:4000。修改 `_config.yml` 后需要重启服务。
脚本显式使用 UTF-8，确保中文文件名在不同终端区域设置下正常构建。

## 构建与检查

```sh
script/cibuild
```

此命令执行生产构建，并检查所有生成的 HTML 页面、本地链接、图片、目录锚点及 RSS。开发文件不会发布到 `_site`。
`Gemfile.lock` 锁定依赖版本，包含 macOS 和 Linux 平台；CI 自动缓存 Bundler 依赖。

## 发布

1. 在仓库 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。
2. 将改动提交到 `master`。也可在 Actions 中选择 `master` 手动运行工作流。
3. 在 **Build and deploy GitHub Pages** 工作流中查看构建、检查和部署结果。

拉取请求只进行构建和检查，不部署。只有 `master` 可以发布；部署通过 `github-pages` 环境和 GitHub 的 OIDC 凭据完成，不需要个人访问令牌。部署权限仅授予部署任务。

这里使用 Actions 自行构建 Jekyll 4，而不是 GitHub Pages 的旧 `github-pages` gem 依赖集；因此必须使用 GitHub Actions 发布来源。

## 写作与维护

- 原文章继续位于 `_posts`，中文文件名和已有文章 URL 保留。
- 图片位于 `image`；文章正文、图片文件保持原样。
- 新文章建议使用 `YYYY-MM-DD-title.md` 命名，并添加 `layout: post`、`title` 等 YAML front matter。
- 无 front matter 的旧文章通过兼容插件正常生成标题并使用文章模板。
- 模板位于 `_layouts` 和 `_includes`；样式为 `assets/site.css`，无外部字体、前端构建工具或 JavaScript 依赖。
- 页面支持手机布局、系统深色模式、键盘焦点和跳到正文链接。
- RSS 位于 `/feed.xml`，站点地图位于 `/sitemap.xml`。
- 模板修复旧读书笔记中的一个失效锚点，不修改源文章。

Dependabot 每月检查 Ruby 依赖和 Actions。手动更新时运行 `bundle update` 和 `script/cibuild`，检查页面后提交 `Gemfile.lock`。

## 许可

保留仓库原有 MIT 许可证和 Minima 版权声明，见 `LICENSE.txt`。
