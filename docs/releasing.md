# 发布版本

在仓库根目录执行，无需 AI、Skill 或额外 Python 依赖。需要已登录的 GitHub CLI（`gh auth login`）、Git、Python 3 、Xcode Beta、Developer ID Application 证书及私钥，以及已保存的 notarytool 钥匙串凭据。

```bash
# 只预览下一版本，不修改文件、不访问网络
python3 script/release.py minor --dry-run

# 配置一次；可放进本机 shell 配置，不要提交密码
export NOTARY_PROFILE="你的钥匙串 profile 名称"

# 提前提交本次要发布的改动，然后执行发布
python3 script/release.py minor
```

`minor` 将 SealNote 和 SealNoteMac 的 Debug / Release 版本统一从 `X.Y.Z` 升到 `X.(Y+1).0`，build 加 1；测试和 CLI Target 的独立版本不变。也接受历史的 `X.Y` 格式。

脚本要求处于 `main` 且工作区干净，检查 GitHub 登录状态、远程 main 与版本一致性，然后校验工程文件、提交版本变更、创建 annotated tag、原子推送 main 与 tag，再构建 universal macOS archive、导出 Developer ID App、公证并 staple App 与 DMG，通过签名与 Gatekeeper 检查后上传 DMG 和 SHA256 校验文件，最后发布 GitHub Release。发布说明取自上一 tag 以来的 Git 提交记录，不调用 AI，因此提交标题应明确表达变更。

这条命令发布源码及 macOS 安装包，不上传 App Store。输出与构建中间文件位于已忽略的 `dist/<版本>/`。iOS 验证可在发布前运行 `./script/verify.sh ios-build`。打包流程也可单独调用 `bash script/package_macos.sh VERSION BUILD`。脚本启动时先检查签名、公证凭据；缺失则在版本变更前停止。

如果已产生 `Release v… (build …)` 提交，但推送或发布被网络问题打断，保持 HEAD 在该提交并执行：

```bash
python3 script/release.py resume
```

`resume` 不再次增加版本；会确认已有 tag 指向当前提交，重试推送，并跳过已发布的 Release。若已有同名草稿则停止，交由人工检查。若中断发生在提交之前，先检查并提交版本修改（提交标题按上述格式），再 resume；不要直接再次 minor。

## 无证书的非正式版本

```bash
python3 script/release.py minor --unsigned
# 失败后恢复时保留相同参数
python3 script/release.py resume --unsigned
```

此模式不需要 Developer ID 或公证凭据，构建未签名、未公证的 universal DMG，校验镜像并上传 SHA256，标为 GitHub prerelease，发布说明注明 Gatekeeper 限制。不会覆盖正式 Latest。首次打开可能被 macOS 拦截；确认来源可信后可在系统设置的“隐私与安全性”中允许打开。
