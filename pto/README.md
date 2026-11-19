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

工作流产物保留 30 天。正式版本另存于仓库的 [Releases](https://github.com/vertno/hysteria-pto/releases)，可以长期下载。

## 自动跟进官方稳定版

在本仓库选择 **Watch → Custom → Releases**，即可订阅自己的修改版。GitHub Actions 每六小时检查一次官方已公开的 Hysteria 2 正式版，从中选出版本号最高的一个。新版本发布到分支的检查可能因 GitHub 排队稍有延迟。可以在 [Publish official stable updates](https://github.com/vertno/hysteria-pto/actions/workflows/stable.yml) 点 **Run workflow** 立即检查。

工作流在临时分支合并官方 Release 对应的提交，保留本仓库的构建脚本和工作流。它按新源码的要求选择 Go 版本，核对 QUIC 模块校验和，应用两份补丁，运行 RTT 与丢包恢复测试，最后用编好的两个 HY2 进程在本机回环上传 128 KiB 随机数据并核对回执。全部通过后才推进 `pto`、创建版本标签、上传 Linux amd64 程序和校验清单；GitHub 端的附件摘要核对通过后才公开发布。

发布标签形如 `pto-v2.14.0-1`。重复检查已发布版本会跳过编译。源码合并、补丁或测试失败时，上一份公开版本继续可用；在自动发布记录里可查看原因。上传途中失败时，下一次会用同一标签重试并补齐草稿。需要人工解决合并冲突时，维护者可用 `bash pto/update.sh app/vX.Y.Z` 准备更新分支。

GitHub 会暂停长期无仓库活动的公开项目的定时任务。若已有版本持续 35 天以上，工作流会在独立的 `automation/stable-check` 分支记录一次活动，保持定时检查，不产生新 Release。[GitHub 定时任务说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

## 本地构建

持续集成沿用官方测试流程的格式检查和三组 Go 测试：核心传输 `core`、扩展功能 `extras`、命令行及代理入口 `app`。三组都在已替换 QUIC 依赖的 Go 工作区内运行。Python 辅助程序使用上游 `uv.lock` 中的依赖。另外单独运行 QUIC 定时器回归测试和编译产物的回环传输测试。官方针对多个系统与架构打包，本分支发布部署使用的 Linux amd64 程序。[上游测试流程](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/.github/workflows/test.yml) · [上游构建流程](https://github.com/HyNetworks/hysteria/blob/app/v2.14.0/.github/workflows/build-common.yml)

在 Linux x86-64 上安装 `pto/go-version` 指定的 Go，以及 Git、Bash、Python 3 和 GNU coreutils。在干净的完整克隆中运行：

```bash
git fetch https://github.com/apernet/hysteria.git 'refs/tags/app/v*:refs/tags/app/v*'
bash pto/build.sh
./pto-out/hysteria-pto-linux-amd64 version
```

本地和 Actions 共用这个入口。脚本核对所选 QUIC 模块与上游 `core/go.sum` 的校验和，在临时目录打补丁，运行 RTT 与丢包恢复两个包的单元测试，然后检查最终二进制是否链接到打过补丁的模块。直接执行上游原来的 `go build` 会使用原版 QUIC 依赖。[Go 模块与工作区文档](https://go.dev/ref/mod)
