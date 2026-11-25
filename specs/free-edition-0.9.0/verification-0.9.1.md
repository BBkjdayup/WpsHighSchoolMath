# WPS 高中数学工具 0.9.1 完全免费版修复验收

2026-11-24 在 Windows 上复验了 0.9.0 审查列出的 9 项问题。修复版使用新版本号 0.9.1，可从 0.8.1 或 0.9.0 直接升级。文字和演示的全部功能继续免费离线使用，无需账号或激活。[原始审查](review-2026-11-24.md)

本页列出的原始日志按文件名保存在验收工作区的 `output/verify-0.9.1/` 下。源码仓库提供测试和构建脚本供复核。[统一测试入口](../../scripts/run-tests.ps1)

## 交付文件

| 文件 | 大小 | SHA-256 |
| --- | ---: | --- |
| [Windows 离线安装器](https://github.com/BBkjdayup/WpsHighSchoolMath/releases/download/v0.9.1/WpsHighSchoolMath-0.9.1-offline.exe) | 274,432 字节 | `6b1cbaa7cdda142a45a8bf8ec09458459b86b0a540393ce44c3dd27b61cb56ab` |
| [完整离线 ZIP](https://github.com/BBkjdayup/WpsHighSchoolMath/releases/download/v0.9.1/WpsHighSchoolMath-0.9.1-offline.zip) | 142,712 字节 | `886f6e706f3d05572b6721119e5f9d799023eca9305e20d1de4c8ba4b9097a21` |

EXE 按内部通道构建，Windows Authenticode 状态为 `NotSigned`。独立解出 EXE 内的 CAB 后，启动脚本、引导脚本和内嵌 ZIP 均通过比对，内嵌 ZIP 与单独交付的 ZIP 逐字节一致。[SHA-256 清单](https://github.com/BBkjdayup/WpsHighSchoolMath/releases/download/v0.9.1/WpsHighSchoolMath-0.9.1-checksums.sha256) · [发行清单](https://github.com/BBkjdayup/WpsHighSchoolMath/releases/download/v0.9.1/WpsHighSchoolMath-0.9.1-release-manifest.json) · 解包记录 `cab-final.log`

升级前，若旧编辑器里有收藏，先在文字和演示中分别导出备份。保存文档，等后台任务结束并完全退出 WPS，再运行 EXE。使用 ZIP 时先完整解压，再双击 `install.cmd`。[安装与升级说明](../../docs/DEVELOPMENT.md)

## 逐项复验

| 审查项 | 修复与复验结果 |
| --- | --- |
| 1 · P1　后台 WPS 持有未保存文档 | 安装和卸载使用同一进程检查。创建一份没有窗口、没有保存的真实 WPS 课件后，检查按预期中止维护，原课件仍可读回刚写入的文字。可见窗口与无窗口两种情况均有回归。实机记录 `headless-final.log` · [进程回归](../../tests/offline-wps-process-detection.test.ps1) |
| 2 · P1　其他加载项被误删 | 清理时检查完整产品名、版本目录和清单或注册身份。同前缀的独立插件 `WpsHighSchoolMath_Notes` 在安装和卸载后均可读回原数据与注册。另一个占用相似版本目录的插件也保留了原清单。[安装回归](../../tests/offline-install-transaction.test.ps1) · [卸载回归](../../tests/offline-uninstall.test.ps1) |
| 3 · P1　中断升级导致双宿主失效 | 跨版本升级并排准备新载荷，注册并校验成功后清理旧版。分别从实际 0.8.1、0.9.0 包升级，在第一份新载荷移入后让安装子进程直接退出，当场检查文字、演示的旧注册均能找到原清单，重试后均升级成功。同版修复、登记 Windows 卸载入口及中断期间另一插件新注册的场景也已纳入回归。0.8.1 实测 `upgrade-081.log` · 0.9.0 实测 `upgrade-090.log` · [事务回归](../../tests/offline-install-transaction.test.ps1) |
| 4 · P2　旧卸载进程误删重装后的卸载入口 | 待清理目录在维护锁内改为本次卸载独有的名称。先完成新注册，再放行旧清理进程，0.9.0 卸载后安装 0.9.1、0.9.1 卸载后立即重装两种顺序均保留了有效的 Windows 卸载命令。时序实测 `cleanup-race.log` |
| 5 · P2　更新课件绘图丢失旋转和图层 | 更新前将图旋转 30°，在图上叠放标注。更新参数、保存并重开 PPTX 后，旋转仍为 30°，函数图在第 1 层，标注在第 2 层，总数仍为两个对象。模拟宿主拒绝调整层级时，旧图也能保留。演示实测 `ppt-final.log` · [文档回归](../../tests/function-plot-document.logic.test.js) |
| 6 · P2　无定义的算式出现曲线或交点 | 运算中产生的无定义值会继续传递到外层表达式。包内绘图器在 `[-4,-1]` 为 `sqrt(x)^0` 生成零条曲线路径，在对称和非对称区间均排除了 `1/(1/x)` 在原点的虚假交点。成品绘图实测 `math.log` |
| 7 · P2　非对称区间漏标相切点 | 在 `[-1,2]` 上，`x^2` 找到一个与横轴相切的点，数值横坐标距 0 小于 `1e-19`，SVG 有一个交点标记。同区间的 `x^2+1e-20` 返回零个交点和标记。成品绘图实测 `math.log` · [正反例](../../tests/plot-analysis.logic.test.js) |
| 8 · P2　根式曲线漏标自然端点 | `sqrt(x)` 在 `[-5,5]` 找到原点，上半圆 `sqrt(1-x^2)` 在 `[-2,2]` 找到 `(-1,0)` 和 `(1,0)`。不对齐采样网格的 `sqrt(x-0.3)` 也找到端点。交点列表和 SVG 标记数量逐项相符，开端点与间断点反例通过。成品绘图实测 `math.log` · [定义域回归](../../tests/plot-analysis.logic.test.js) |
| 9 · P3　页眉符号未套用数学字体 | 文字插件从实际选区所在的文本区域定位新字符。在正文、页眉分别插入 `∩`，保存并重开 DOCX 后符号仍为 Cambria Math，邻近原文保持 Courier New。页眉符号的西文、东亚和其他字体属性均已读回。文字实测 `writer-final.log` · [符号回归](../../tests/ribbon.logic.test.js) |

## 其他验证和实测范围

- 两个宿主都用全新配置、旧试用中、旧试用已过期、旧版已激活四种配置启动。符号和绘图可直接使用，文字中的试题模板和排版命令也正常执行。测试确认这些入口没有读写旧试用或激活记录。[文字入口回归](../../tests/ribbon.logic.test.js) · [演示入口回归](../../tests/ppt.logic.test.js)
- 统一测试通过 13 组 JavaScript 和 12 组 Windows PowerShell 回归，并完成 42 个 JavaScript 文件、43 个 PowerShell 文件的语法检查及 120 个文本文件的 UTF-8 和项目结构检查。完整回归日志 `full-tests.log`
- 在隔离的安装目录和临时注册表子项内，对两个旧版本分别注入可捕获的安装故障。回滚后，0.8.1 的 73 个文件和 0.9.0 的 44 个文件均与升级前逐一匹配。同版重装的 45 个文件也通过相同比对。独立子进程直接退出的测试另行执行，这次验证覆盖进程中断，物理断电尚未实测。0.8.1 安装记录 `upgrade-081.log` · 0.9.0 安装记录 `upgrade-090.log`
- WPS 文字和演示实测版本为 `12.1.0.29690`。两个宿主分别插入 V1–V4 四种格式的图，保存、重开、更新并再次保存重开，参数和尺寸回读通过。课件位置、文字锚点及跨文档更新保护也通过。测试使用临时 DOCX 和 PPTX，其他 WPS 版本及用户日常配置的首次信任提示尚未实测。文字兼容性 `compat-writer.log` · 演示兼容性 `compat-presentation.log`
- 对两个打包编辑器分别用 Chrome 检查 3 种窄窗尺寸及 2 个滚动位置，共执行 24 次按钮点击，并检查收藏导出与本地资源加载。离线包从干净源码目录构建，最终发布校验通过，文字和演示清单各含 20 个载荷文件。浏览器记录 `browser.log` · 构建记录 `clean-build.log` · 成品发布校验 `release-final.log`
- 复核了审查记录中的 PowerShell 摘要差异。新清单使用序数排序，旧清单验完每个文件后按原清单顺序复算。Windows PowerShell 5.1 和 PowerShell 7.6.9 均核验通过 0.9.0 和 0.9.1 的文字、演示载荷，四份摘要逐一一致。5.1 记录 `digest51.log` · 7.6.9 记录 `digest7.log` · [摘要回归](../../tests/payload-integrity.test.ps1)
