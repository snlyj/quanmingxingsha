# 《全明星杀》（All Star Kill）

基于 **Godot 4.3.stable**（纯 GDScript，横屏 `1920×1080`）开发的二次元学园风策略卡牌对战手游，核心玩法对标《三国杀》移动版 / 无名杀（v1.10.9 规则重构），内置 19 名全原创角色、完整配音音效与自动化回归测试套件。

> 当前最新版本：**V0.44.1**（`versionCode=51`，包名 `com.jonathan.quanmingxingsha`）
> 下载最新安装包：[GitHub Releases](https://github.com/snlyj/quanmingxingsha/releases)

---

## 核心特性（截至 V0.44.1）

- **多元对战模式**：
  - **5 人身份场**（主公 / 忠臣 / 反贼 / 内奸，三档 AI 难度、AI 身份推测与标记猜身份）
  - **3 人斗地主**（叫分 1~3 倍、明牌、加倍、农民手牌互通、专属卡牌攻守兼备/进退自如/继往开来与欢斗豆结算）
  - **欢乐 2v2**（4 人同盟排位，队友手牌互通、阵亡抚恤摸牌）
  - **魔王挑战 3v1**（联军合战 8 血魔王）
  - **单挑对决 1v1**（先手/后手选择）
  - **残局闯关**（共 2 章 `p01`~`p15` 15 关可解残局与成就）+ **新手教学关**
- **19 名全原创角色 & 55 种卡牌**：
  - 全原创二次元学园角色（`hina` ~ `mafuyu` 共 19 人，全部配有 `.webp` 原创 CG 立绘与面部焦点裁切）
  - 技能覆盖限定技、转换技、觉醒技、主公技、拼点、护甲、通用标记与判定改判
  - 卡牌图鉴共 55 种（常规 197 张 / 斗地主 203 张，含火/雷/冰属性与应变词条）
- **二次元视听与互动养成**：
  - **95 条角色 CV 语音（`.ogg`）**：覆盖详情页多部位触碰试听，以及对局攻击/受击/回复/技能/濒死/阵亡/丢花应援与高优先级打断保护
  - **24 种音效 + 双套 BGM**：樱华国风 / 经典交响实时切换，含濒死/残局紧张切歌
  - **好感度羁绊 & 每日社团委托**：伪 Live2D 待机呼吸与点击 Q 弹粒子、欢斗豆送礼、Lv.5 誓约解锁、每日 4 项社团委托

---

## 快速上手与测试（接手开发必看）

### 1. 环境准备
- 下载并安装 **Godot 4.3.stable**（Standard GDScript 版即可，无需 Mono/C#）。
- 直接在 Godot 中导入 `game/project.godot` 即可编辑与按 `F5` 运行调试。

### 2. 运行全套自动化自测（改代码后必跑）
```bash
# 使用系统 PATH 中的 godot（或通过 G=/path/to/godot4.3 指定二进制路径）
STRESS_N=300 bash 工具脚本/alltests.sh
```
测试包含：
1. 全 16 个 `.gd` 脚本 `--check-only` 静态语法/类型检查
2. `--ybtest`（规则断言）、`--engtest`（身份 AI 对战）、`--modetest=doudizhu|duel`、`--uitest`（自动 UI 游玩）
3. `--regtest`（定向回归）与 `--stress`（身份场、斗地主、单挑、欢乐 2v2、魔王挑战）
4. 可加 `UIPLAY=10` 模拟点选、拖拽和技能操作。每次运行生成独立日志目录。导入失败、超时、断言失败或缺少完整报告时，脚本以非零状态退出。

### 3. Android APK 打包与签名

从构建机密钥库或 CI Secrets 注入 Godot 4.3 的三个环境变量：

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` 指向仓库外的密钥文件。
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER` 是密钥别名。
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 由密钥库注入。

使用 Godot Android 导出模板、JDK 17 和 Android SDK 34 导出：

```bash
mkdir -p builds
godot --headless --path game --export-release "Android" ../builds/qmxs_v0.44.1.apk
apksigner verify --print-certs builds/qmxs_v0.44.1.apk
```

历史发布密钥曾公开，现有版本的更新兼容性取决于安装渠道与签名证书。发布替换前，在现有安装上测试覆盖升级。若使用 Google Play App Signing，在 Play Console 确认暴露的是上传密钥还是应用签名密钥，再按对应流程重置或升级。直接分发 APK 时，先验证目标 Android 版本是否接受签名轮换，否则需安排存档迁移和重新安装。

升级版本号时同步修改 `game/project.godot` 的 `config/version` 与 `game/export_presets.cfg` 的 `version/code`、`version/name`。

---

## 目录结构

```text
├── game/                   # Godot 4.3 主工程（全部 16 个脚本共 22,542 行）
│   ├── Main.tscn           # 入口场景
│   ├── project.godot       # 工程配置与版本号真源
│   ├── export_presets.cfg  # Android 导出预设
│   ├── scripts/
│   │   ├── engine.gd       # 规则引擎（六阶段、触发结算、AI 推测、全部模式机制）
│   │   ├── battle.gd       # 对局桌UI（手牌拖拽、按钮操作栏、CV播放、特效、结算、设置）
│   │   ├── main.gd         # 外壳大厅（首页、插画轮播、委托、图鉴、详情、残局、战绩、测试入口）
│   │   ├── skill_lib.gd    # 角色技能定义库
│   │   ├── meta.gd         # 本地存档、战绩/成就、好感誓约、禁用池、每日委托
│   │   ├── intro.gd        # 长按说明浮窗（卡牌/角色/技能高亮百科）
│   │   ├── art.gd          # CG 裁切、卡牌框色、竖排名牌与角标绘制
│   │   ├── audio.gd        # 音效/CV 资源映射与播放控制
│   │   ├── music.gd        # 双套 BGM 管理器与紧张局势淡入淡出
│   │   └── selftest.gd     # 自动化回归测试与 UI 验证（regtest）
│   ├── data/               # 角色表（characters.gd）、牌堆表（cards.gd）、残局（puzzles.gd）、帮助（help.gd）
│   └── assets/             # bg(2) / bgm(6) / cards(55+) / cg(19) / fonts / sfx(24) / ui / voice(95)
├── 工具脚本/               # 自动化全测脚本（alltests.sh）、无头运行（t.sh）、截图脚本（shots.sh）
├── docs/                   # 历代规则对照与美术/UI 设计规范文档
├── 全明星杀_V1设计稿.md    # 核心角色技能与玩法设计稿
└── 交接说明.md             # 详细工程交接与避坑指南
```

详细工程注意事项、历史版本演进与编码铁律请继续阅读 [`交接说明.md`](交接说明.md)。
