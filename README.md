# 《全明星杀》（All Star Kill）

《全明星杀》是一款二次元学园风的单机横屏策略卡牌游戏。以星樱坂学园为舞台，玩家可以与电脑对手进行身份博弈、同盟对战和残局挑战。游戏使用 **Godot 4.3.stable** 与 GDScript 开发，包含 19 名原创角色及其立绘与配音。

**[下载已发布的 Android APK](https://github.com/snlyj/quanmingxingsha/releases/latest)**

公开安装包及发行说明以 GitHub Releases 为准。下文介绍 `main` 分支的源码功能。

<img src="game/assets/lobby_art/sakura.webp" alt="《全明星杀》海边樱花插画" width="480">

## 对战玩法

- **5 人身份场** — 主公、忠臣、反贼、内奸各有获胜条件，可标记其他角色的推测身份并选择三档 AI 难度。
- **3 人斗地主** — 叫分、明牌、加倍和欢斗豆结算。农民共享手牌信息，模式内含「攻守兼备」「进退自如」「继往开来」等专属卡牌。
- **欢乐 2v2** — 四人同盟对战。可查看队友手牌，队友阵亡后存活队友可摸牌。
- **魔王挑战 3v1** — 三人联军对抗 8 点体力的魔王。
- **单挑对决 1v1** — 可自选先手或后手。
- **残局与教学** — 两章共 15 道残局，另设新手教学关。

19 名角色拥有各自的技能组合，机制涵盖限定技、转换技、觉醒技、主公技、拼点、护甲和改判。卡牌图鉴收录 **55 种卡牌**，常规牌堆 197 张，斗地主牌堆 203 张，包含火、雷、冰属性和应变词条。规则设计参考了《三国杀》移动版与无名杀 v1.10.9。

## 当前源码

- 大厅、牌桌和图鉴采用奶白、浅蓝、薰衣草色与樱玫色。大厅右侧轮播三幅原创全幅插画，分别呈现海边樱花、午后图书馆和灯笼夜祭。
- 对局可以点选手牌与目标后确认，也可以拖拽出牌。手牌较多时可横向滑动或翻页，大量响应选项可滚动查看。长按卡牌、角色或技能可查阅说明。
- 游戏有 95 条角色语音、24 种音效和两套背景音乐。角色详情支持互动、赠礼和好感誓约，每日社团委托提供欢斗豆与角色好感奖励。开启「减少动态效果」后，大厅插画可用圆点手动切换。
- 多目标「突击」按目标分别响应和结算。欢乐 2v2 与魔王挑战中，首位角色阵亡后仍会推进轮次。救援 AI 依阵营行动，「星樱号令」会在忠臣使用「补给」救起主公时发放摸牌奖励。主动技能的选择与执行共用封技和目标校验。

## 本地运行与测试

安装 **Godot 4.3.stable** Standard 版，导入 `game/project.godot`。按 `F5` 运行，基准横屏分辨率为 `1920×1080`。

从仓库根目录运行全套测试。可用 `G=/path/to/godot4.3` 指定 Godot 程序。

```bash
STRESS_N=300 UIPLAY=15 bash 工具脚本/alltests.sh
```

测试覆盖脚本语法、规则断言、AI 对战、模式结算以及点选、拖拽和技能交互。已验证的一轮全套测试中，**420 项回归断言、300 局规则压测、15 局模拟操作全部通过**。每次运行生成独立日志目录，导入失败、超时、断言失败或缺少完整报告时以非零状态退出。

## Android APK 打包与签名

Android 包名为 `com.jonathan.quanmingxingsha`。从构建机密钥库或 CI Secrets 注入下列 Godot 4.3 环境变量。

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` 指向仓库外的密钥文件。
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER` 是密钥别名。
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 由密钥库注入。

安装对应的 Godot Android 导出模板、JDK 17 和 Android SDK 34，然后在仓库根目录导出并验签。

```bash
mkdir -p builds
godot --headless --path game --import
godot --headless --path game --export-release "Android" ../builds/qmxs-release.apk
apksigner verify --print-certs builds/qmxs-release.apk
```

历史发布密钥曾公开，现有版本的更新兼容性取决于安装渠道与签名证书。发布替换前，在现有安装上测试覆盖升级。若使用 Google Play App Signing，在 Play Console 确认暴露的是上传密钥还是应用签名密钥，再按对应流程重置或升级。直接分发 APK 时，先验证目标 Android 版本是否接受签名轮换，否则需安排存档迁移和重新安装。

升级版本号时同步修改 `game/project.godot` 的 `config/version` 与 `game/export_presets.cfg` 的 `version/code`、`version/name`。

## 目录结构

```text
├── game/                   # Godot 4.3 主工程
│   ├── Main.tscn           # 入口场景
│   ├── project.godot       # 工程配置与版本号真源
│   ├── export_presets.cfg  # Android 导出预设
│   ├── scripts/
│   │   ├── engine.gd       # 规则引擎（六阶段、触发结算、AI 推测、全部模式机制）
│   │   ├── battle.gd       # 对局桌UI（手牌拖拽、按钮操作栏、CV播放、特效、结算、设置）
│   │   ├── main.gd         # 外壳大厅（首页、插画轮播、委托、图鉴、详情、残局、战绩、测试入口）
│   │   ├── lobby_carousel.gd # 大厅插画轮播及减少动态效果支持
│   │   ├── ui_palette.gd   # 大厅和牌桌通用配色
│   │   ├── skill_lib.gd    # 角色技能定义库
│   │   ├── meta.gd         # 本地存档、战绩/成就、好感誓约、禁用池、每日委托
│   │   ├── intro.gd        # 长按说明浮窗（卡牌/角色/技能高亮百科）
│   │   ├── art.gd          # CG 裁切、卡牌框色、竖排名牌与角标绘制
│   │   ├── audio.gd        # 音效/CV 资源映射与播放控制
│   │   ├── music.gd        # 双套 BGM 管理器与紧张局势淡入淡出
│   │   └── selftest.gd     # 自动化回归测试与 UI 验证（regtest）
│   ├── data/               # 角色表（characters.gd）、牌堆表（cards.gd）、残局（puzzles.gd）、帮助（help.gd）
│   └── assets/             # 大厅插画、背景、立绘、卡图、缩略图、字体与音频
├── 工具脚本/               # 自动化全测脚本（alltests.sh）、无头运行（t.sh）、截图脚本（shots.sh）
├── docs/                   # 历代规则对照与美术/UI 设计规范文档
├── 全明星杀_V1设计稿.md    # 核心角色技能与玩法设计稿
└── 交接说明.md             # 详细工程交接与避坑指南
```

详细工程注意事项、历史版本演进与编码铁律请继续阅读 [`交接说明.md`](交接说明.md)。
