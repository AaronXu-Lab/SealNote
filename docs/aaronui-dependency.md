# AaronUI 依赖来源切换

当前 Seal Note 的 iOS 与 macOS Target 共用本地 Swift Package：
`../AaronUI-SwiftUI`。路径相对于 Seal Note 项目根目录，两个仓库放在同一父目录即可：

```text
GitHub/
├── SealNote/
└── AaronUI-SwiftUI/
    └── Package.swift
```

直接修改本地 AaronUI 源码后，重新构建 Seal Note 即可使用，包括尚未提交的库改动。
不需要先发布 GitHub 版本，也不需要复制源码。正在运行的 App 需要重新构建并启动；
这不是运行时热更新。AaronUI 的其他远程依赖仍由 SPM 管理。

## 使用本地库

在 Seal Note 根目录执行：

```sh
python3 script/aaronui_dependency.py local
```

其他存放位置可传入 `--path`，推荐使用相对路径：

```sh
python3 script/aaronui_dependency.py local --path ../AaronUI-SwiftUI
```

脚本会先确认目标目录存在 `Package.swift`。切换后正常构建，Xcode 会重新解析依赖。
当前项目配置和 Package.resolved 已切换；无需每次构建前运行脚本。

## 切回 GitHub

组件库完成后，指定已发布版本作为最低版本，例如：

```sh
python3 script/aaronui_dependency.py github --version 0.5.0
```

不传 `--version` 会恢复原来的 `0.4.2` 最低版本要求。版本策略沿用原项目的
`upToNextMajorVersion`，并由 `Package.resolved` 记录实际解析的版本。
切换后可直接构建，或只重新解析依赖：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -resolvePackageDependencies -project SealNote.xcodeproj -scheme SealNote
```

脚本只切换 AaronUI 的包来源，保留产品引用和两个 Target 的链接关系。
分享工程或在其他机器构建时，本地模式也需要同样的相邻目录布局；
恢复 GitHub 后不再需要本地组件库仓库。

## 验证记录（2026-10-19）

- SPM 解析结果为 `AaronUI: ../AaronUI-SwiftUI @ local`，远程 AaronUI pin 已移除。
- `./script/verify.sh ios-build`、`./script/verify.sh mac-build` 均通过；构建日志确认编译本地库源码。
- 本地 → GitHub → 本地切换检查通过，项目文件往返一致。
- 构建仍报告 Seal Note 存储层的 actor isolation 等警告；本次未改动应用业务代码。
