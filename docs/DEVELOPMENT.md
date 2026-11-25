# 开发、安装与发行说明

## 0.9.1 免费版

Windows 桌面版 WPS 文字与演示共用本地绘图页面。文字另有试卷模板和排版工具。全部功能长期免费，直接从功能区「高中数学」打开。

### 安装与升级

1. 若旧版 WPS 仍开着，在文字和演示的函数编辑器分别展开「我的绘图收藏 → 迁移备份与撤销 → 导出备份文字」，把文字复制到文件。收藏可能随旧会话结束而消失。
2. 保存文档和课件，等自动化任务完成后，完全退出 WPS 文字和演示。安装器检测到后台 WPS 进程时也会提示稍后重试。运行离线 EXE，或解压完整 ZIP 后双击 `install.cmd`。
3. 重启两个宿主。若 WPS 询问是否信任此加载项，确认来源后按 WPS 提示处理。在新版「我的绘图收藏」中粘贴备份并「合并导入」。旧文档中的插件图也可以选中、载入并重新收藏。
4. Windows 设置的「已安装的应用」或开始菜单可卸载，ZIP 中的 `uninstall.cmd` 是备用入口。安装故障日志在 `%LOCALAPPDATA%\WpsHighSchoolMath\Logs`。

## 函数图像

- 0.8.1 将“更新预览”和“插入新图像／更新所选图像”移到独立的底部操作栏；滚动设置、展开分析或添加多条函数时始终可见。成功或错误提示也在底部显示，操作栏不遮挡表单，窄窗格下按钮自动分行。
- 0.8.0 新增“交点与切线”：勾选“标注交点”，选择两条曲线并设置搜索范围；第二条可选 x 轴来查找零点。搜索范围留空时使用当前横坐标范围，曲线自己的定义域和开闭端点仍有效。
- 勾选“显示切线和切点”，选择曲线，输入切点横坐标，例如 `1` 或 `a`。界面显示切点、斜率与切线方程，图片标注交点坐标和切线；拖动参数会自动重新计算。
- 交点与切线为数值近似。交点最多标注 20 个，可能遗漏相切或密集交点，可缩小搜索区间复核；重合区间不逐点标注。本版只计算定义域内部的有限斜率切线，尖点、间断点、端点及精度不足时会提示调整位置。
- 新分析设置以 V4 随图片保存，旧图 V1/V2/V3 继续可读；包含分析设置的收藏使用 V2 备份格式。0.7.0 及更早版本无法编辑 V4 图片或导入 V2 收藏，但可以显示生成的 SVG 图片。
- 0.7.0 新增 a、b、c 参数滑块；点击“参数示例”追加 `ax^2+bx+c`，展开“参数滑块”拖动或输入数值，可在“调整范围与步长”中设置滑动范围。手动输入的数值不会因步长自动取整；图例同时显示所用参数的当前值。
- “横竖辅助线”支持每行输入 `x=2`、`y=1` 等，最多 20 条；也可写 `x=-b/(2*a)`、`y=c`，辅助线随参数一起变化。参数导致位置无定义时会明确报错，例如 a=0 时不能使用 `-b/(2*a)`。
- “我的绘图收藏”可命名保存完整方案，最多 50 个；支持载入、删除、恢复上次收藏列表，以及备份文字导入导出。同名但内容不同的导入方案会自动改名，不覆盖已有方案。
- 收藏优先保存到当前 WPS 的 PluginStorage，独立浏览器使用本地存储；不同宿主、电脑或版本环境间请用“导出备份文字”和“合并导入”迁移。备份文字需复制到文本文件自行保存。
- 0.6.0 新增每条曲线独立的定义域、端点开闭、颜色、线型与显示开关；展开每行下方的“定义域与样式”设置。定义域两端留空表示不限制。
- 多行表达式可组合分段函数；“分段示例”会追加 `x<0` 时的 `x^2` 和 `x≥0` 时的 `x+1`。需要单独查看示例时，可先删除其他曲线。
- 在“坐标与显示设置”中勾选“黑白打印”，曲线与图例使用黑色及不同线型；取消勾选可恢复原来的颜色和线型。
- “坐标点标注”支持每行输入 `名称,横坐标,纵坐标`，例如 `A,0,1`。最多支持 30 个点，范围外的点不显示但保留参数。
- 表达式错误和无效定义域会标记对应行。最多 12 条曲线；过于密集的函数会提示缩小范围，避免长时间占用 WPS。
- 未启用分析的参数与辅助线仍使用 V3；本版原生快捷输入回退会保留含新版设置的图像，并提示使用完整编辑器。
- 更新图像时先创建新图并验证编辑参数，再移除旧图；添加失败不会先删除旧图。新增图像使用折叠插入范围，保留选中文本。若 WPS 无法确认旧图删除结果，则保留新图并提示检查多余图像。
- 离线安装后点击 `函数编辑器`，WPS 会直接打开版本化的本地函数绘图页；插件不启动本地服务、不监听端口、不连接 localhost，也不启动外部页面助手。
- 编辑器可添加多条函数、按回车新增函数，或重复点击预设追加曲线。
- 支持 `+ - * / ^`、隐式乘法 `2x`、括号以及 `sin`、`cos`、`tan`、`sqrt`、`abs`、`ln`、`log`、`exp` 等函数。
- 根号可写 `√x`、`√2`；根号后接函数或复杂表达式请写成 `√(sin(x))`、`√(x+1)`。
- 支持 `π`、`x²`、`x³`，并提供二次函数、绝对值、反比例、sin、cos、指数、对数预设。
- 坐标范围默认保持为横纵坐标 `-10` 到 `10`，点击预设不会修改范围。
- 完整编辑器可逐项开关刻度数字、网格、边框和函数表达式图例；原生回退流程默认全部显示。
- 函数图像面板支持窄任务窗格；坐标和显示选项默认收起，设置与图像预览在上方滚动，底部操作按钮始终可用。
- 插入的图像带有版本化绘图配置；选中插件生成的函数图后再次打开编辑器，可恢复表达式、范围和显示选项并原位更新。
- PPT 新插入的函数图会扫描当前页形状，优先选择零重叠的最大区域；页面拥挤时才逐级缩小并选择重叠最少的位置。
- 图像完全在本地生成，以 SVG 格式插入 WPS 文字或 WPS 演示，不依赖网络。

## 构建与验证

从根目录运行以下 PowerShell 命令。开发使用 Node.js，安装和使用插件只需 Windows 与 WPS。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-offline.ps1 -BuildMode Internal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-commercial-release.ps1
```

`release` 中生成离线 EXE、ZIP、SHA-256 和 JSON 发布清单。跨版本升级先并排准备两份新载荷，完成 WPS 与 Windows 注册后才清理原版本。进程异常退出后，重新运行安装包会在同一维护锁下读取事务记录并恢复。卸载进程只延迟清理已经改名的旧卸载目录。`publish.xml` 管理注册，`authaddin.json` 管理 WPS 加载项信任。用 ZIP 内的 `validate-installed.ps1` 可以复核已安装的两份载荷。

`Internal` 是内部发行通道，发布清单记录实际 Authenticode 签名状态。正式签名通道沿用脚本参数 `-BuildMode Commercial`，需要可信的代码签名证书及时间戳，可用 `validate-commercial-release.ps1 -RequireSignature` 复核。两个通道均构建同一套免费功能。

### 复用入口（2026-11-24）

- `js/plot-config.js`、`js/plotter.js` 和 `js/plot-analysis.js` 负责配置、表达式、坐标轴与数值分析。`js/function-plot-document.js` 复用原有 V1–V4 元数据。
- `js/taskpane.js` 复用 WPS 的 `CreateTaskPane` 和 `PluginStorage`，就绪凭据按宿主、页面和版本隔离。`js/plot-library.js` 沿用 V1/V2 备份格式。收藏区直接提示实际存储期限。[WPS PluginStorage 文档](https://open.wps.cn/documents/app-integration-dev/wps365/client/wpsoffice/jsapi/addin-api/PluginStorage/obj)
- 两个宿主同步加载相应 Ribbon。打包只包含项目自有前端和系统脚本，复用 Windows IExpress、PowerShell 和 SHA-256。发布校验逐页解析本地引用。
- 文档操作复用 WPS 的 Range 和 Shape 接口。文字在所选正文或页眉的 Range 内设置符号字体，演示更新先恢复旋转和相对层级，再移除旧图。2026-11-24 在 WPS 12.1.0.29690 复核。[Range.Duplicate](https://learn.microsoft.com/en-us/office/vba/api/word.range.duplicate) · [Shape.ZOrder](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.shape.zorder)
- 安装恢复使用同卷目录移动、原子文件替换和既有维护锁。`scripts/addin-maintenance.ps1` 供两个入口共用。载荷聚合摘要使用序数排序，旧清单按已逐项核验的原顺序读取。[Directory.Move](https://learn.microsoft.com/en-us/dotnet/api/system.io.directory.move)
- 版本验收和测试环境见[0.9.1 修复记录](../specs/free-edition-0.9.0/verification-0.9.1.md)和[0.9.0 免费版基线](../specs/free-edition-0.9.0/implementation.md)。

实机能力探针复用 Windows 进程快照读取父子关系和程序名，并以有限查询权限读取候选程序路径。采样间隔上限为 100 毫秒，超限会记录间隔和丢样数。此探针仅用于开发验收。[Microsoft QueryFullProcessImageNameW 文档](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew)
