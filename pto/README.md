# Hysteria PTO 版

每个官方正式版对应一份带 `-patched` 后缀的发布。程序显示 `v2.14.0-patched`，Git 标签沿用 Hysteria 的 `app/` 前缀。各平台的文件名与官方一致。使用现有运维流程的 Linux amd64 机器也可以继续下载 `hysteria-pto-linux-amd64` 和配套的四份校验、构建说明文件。[下载最新正式版](https://github.com/vertno/hysteria-pto/releases/latest)

## 传输与连接日志

本版调整 QUIC 的探测超时（PTO）。首次测得往返时间后，初始偏差取此次测量的四分之一。随后，探测等待时间使用平滑往返时间，加上一份偏差与定时器最小刻度中的较大值。在适用阶段再计入对端最大确认延迟。连续超时复用这个基准，不按次数翻倍。首次 RTT 样本到来前的基础定时、拥塞控制、探测包配额和防放大限制沿用所选官方版本。持续无响应时，这项修改会比官方更频繁地探测。[QUIC 恢复规范](https://www.rfc-editor.org/rfc/rfc9002.html#section-6.2)

服务端可用 `connectionAudit: true` 配合 info 或 debug 日志等级记录已认证的 TCP 转发流。每条流在出站返回连接时记录 open，结束时记录 close，两条记录共用 `flow_id`。字段包含当时的 QUIC 对端、本地监听地址、出站套接字两端、QUIC 连接与流编号及耗时，格式沿用 `hy2-flow-v1`。延迟拨号时，open 可暂缺出站地址，close 会再取一次。两条事件都走现有日志输出；数据读写仍走 Hysteria 自带的复制函数。UDP 转发、认证失败和拨号失败走官方已有的处理路径。

## 更新

程序的 `check-update` 和原有的后台更新提醒读取本仓库最新发布中的 `update.json`。客户端模式的后台检查走已建立的 HY2 隧道。Linux 服务端安装脚本的下载、版本检查和升级指向同一仓库。脚本跟随每个版本一起发布。[下载服务端安装脚本](https://github.com/vertno/hysteria-pto/releases/latest/download/install_server.sh) · [官方脚本用法](https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/)

GitHub Actions 每小时检查一次上游正式发布，也可手动运行。它按官方发布时间补齐缺少的版本，略过预发布、草稿和已经发布的版本。测试与构建使用该官方标签指向的同一提交，复用测试步骤、Hyperbole 编译器入口、平台列表和哈希生成。自定义流程负责准备 QUIC 补丁、生成更新元数据、向本仓库发布。测试与构建通过后才公开草稿。上游长时间没有新版本时，独立分支上的定期活动用于保持定时检查。[发布记录](https://github.com/vertno/hysteria-pto/actions/workflows/stable.yml)

## 本地构建

在已发布标签的完整克隆中，准备 Go、Python、Git 和 jq，再执行以下命令。临时 Go 工作区内使用官方锁定的 QUIC 版本并应用补丁，模块缓存中的源文件保持原样。Go 版本和交叉编译环境要求随官方版本更新。[官方构建文档](https://v2.hysteria.network/docs/developers/Build/)

```bash
work=$(mktemp -d)
bash pto/prepare-quic.sh "$work"
export GOWORK="$work/go.work"
go test github.com/apernet/quic-go/internal/{utils,ackhandler}
python3 hyperbole.py build -r
```
