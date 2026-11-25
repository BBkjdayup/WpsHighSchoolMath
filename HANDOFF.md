# WPS 高中数学工具 0.9.1 交接

文字与演示加载项均可完全免费离线使用。升级前先在两个旧编辑器导出收藏，复制到文本文件，再关闭 WPS。

| 事项 | 入口 |
| --- | --- |
| 安装、卸载、构建、签名 | [开发与发行说明](docs/DEVELOPMENT.md) |
| 本次验证和发布产物 | [0.9.1 修复验收](specs/free-edition-0.9.0/verification-0.9.1.md) |
| 加载顺序、图像和收藏兼容约束 | [项目约定](CLAUDE.md) |
| 双宿主完整性与安装回滚 | `scripts/payload-integrity.ps1`、`scripts/offline-install.ps1`、`tests/offline-install-transaction.test.ps1` |
| 编辑器与宿主操作 | `ui/function-plot.html`、`js/taskpane.js`、`js/function-plot-document.js` |
| 后续版本范围 | [实施方案](specs/free-edition-0.9.0/proposal.md) |

发布包位于 `release/`，EXE 和 ZIP 对应同一套文件。历史发行代码可通过 Git 追溯。源码交接脚本从当前源码构建，按本版本文件名收集发布物。
