# HY2 PTO 维护指南

这个分支基于官方 Hysteria 2。它在编译时对 HY2 选用的 `github.com/apernet/quic-go` 应用两份补丁，一份改运行代码，一份调整对应的测试。服务端使用此版本时，普通 HY2 和 Mihomo 客户端仍可连接。探测计时由发送端独立计算，部署在服务端只改变服务端的计时。

| 计算位置 | 本分支的行为 |
|---|---|
| 第一个有效 RTT 样本 | 初始往返时间偏差取样本的四分之一 |
| 有 RTT 样本时的基础探测超时（PTO） | 平滑 RTT 加上偏差与 1 ms 中的较大值，按协议阶段决定是否再加对端最大 ACK 延迟 |
| 连续探测超时 | 每轮使用当前基础 PTO，保留原有 60 秒上限 |

取消探测间隔倍增是一项有意的本地策略。持续失联时可能增加无效探测。基础 PTO 也参与密钥和连接状态的保留期限计算。Brutal 上传速率仍由客户端配置，例如 Mihomo HY2 节点的 `up: "40 Mbps"`，调整速率无需重编译。[运行补丁](patches/quic-go-pto.patch) · [回归测试补丁](patches/quic-go-pto-tests.patch) · [RFC 9002 探测定时器](https://www.rfc-editor.org/rfc/rfc9002#section-6.2)

## 在线编译与下载

1. 进入 **Actions → Build PTO edition → Run workflow**，选择 `pto` 分支。向该分支推送提交、向它发起拉取请求，也会触发同一套测试和构建。
2. 打开已成功的运行，在 **Artifacts** 下载 `hysteria-pto-linux-amd64`。解压后执行 `sha256sum -c SHA256SUMS`。GitHub 的工作流压缩包会丢失 Unix 可执行位，使用前执行 `chmod +x hysteria-pto-linux-amd64`。
3. 运行 `./hysteria-pto-linux-amd64 version` 可查看源码提交和版本。`build-info.txt` 记录官方版本、实际 QUIC 依赖、Go 版本和补丁摘要，`modules.txt` 记录最终链接的 Go 模块。

工作流产物保留 30 天。想长期保留某个通过测试的版本，可以给 `pto` 上选好的提交打专用标签，例如 `git tag pto-v2.14.0-1` 并执行 `git push origin pto-v2.14.0-1`。工作流会针对标签重新测试、编译，校验后将**同一份二进制**和清单放入一个 Release 草稿。确认后在 GitHub 点 **Publish release** 即可公开下载。回退时可从先前发布的 Release 取回该版二进制并核对摘要。[GitHub 手动运行说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

## 跟进官方稳定版

日常开发使用 `pto` 分支。可以在上游仓库点击 **Watch → Custom → Releases** 订阅正式版本。收到新版通知后，在本仓库的完整 Git 克隆中执行以下命令。把示例版本替换为上游已经发布的实际标签。

```bash
git switch pto
git pull --ff-only origin pto
bash pto/update.sh app/v2.14.1
git push -u origin update/v2.14.1
```

脚本先从官方仓库获取指定标签；当前分支已经包含该版本时直接退出。发现新版本则在独立分支合并相应提交。接着在**自己的 fork** 创建 PR，目标设为 `pto`。审查 QUIC 更新、补丁和构建结果，使用 **Create a merge commit** 合并，保留官方提交的祖先关系。如果上游改变了相关代码，导致补丁无法应用或测试未通过，工作流会失败并显示出错的位置。即使测试通过，升级 QUIC 时也应检查上游是否改变了超时算法的调用方式。未来上游要求更高的 Go 版本时，同一 PR 更新 `pto/go-version`。

## 本地构建

在 Linux x86-64 上安装 `pto/go-version` 指定的 Go，以及 Git、Bash、Python 3 和 GNU coreutils。在干净的完整克隆中运行：

```bash
git fetch https://github.com/apernet/hysteria.git 'refs/tags/app/v*:refs/tags/app/v*'
bash pto/build.sh
./pto-out/hysteria-pto-linux-amd64 version
```

本地和 Actions 共用这个入口。脚本核对所选 QUIC 模块与上游 `core/go.sum` 的校验和，在临时目录打补丁，运行 RTT 与丢包恢复两个包的单元测试，然后检查最终二进制是否链接到打过补丁的模块。直接执行上游原来的 `go build` 会使用原版 QUIC 依赖。[Go 模块与工作区文档](https://go.dev/ref/mod)
