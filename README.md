# Open-Pro-Installer

## 多源启动入口

新增 `launch.sh`，并行从五条指定 GitHub 加速线路及 raw 直连获取启动脚本。下载完整、SHA256 与固定提交一致并通过 sh 语法检查后，采用最快有效响应并取消其他请求。脚本不跳过或改变邮箱及支付验证。

首次将本仓库的 `launch.sh` 下载或上传到路由器，例如 `/root/opi-launch.sh`，然后运行：

```sh
# 邮箱验证版（默认）
sh /root/opi-launch.sh email
# 支付验证版
sh /root/opi-launch.sh payment
```

再次启动可直接复用此启动器；每次仍重新竞速下载对应的固定版本 bootstrap。当前固定提交为 `b639a7667949543ec9bed05d5220414ff6302c4e`。升级 bootstrap 时需同步启动器中的提交与两个 SHA256。主程序归档仍沿用 bootstrap 原有下载和验证流程。

每条请求连接超时 10 秒、总超时 30 秒，竞速等待上限 35 秒；包含取消和清理的实际退出耗时可能略长。进度写入 stderr，失败不执行下载内容。需要 curl、sha256sum 及常见 Shell 工具；保留 TLS 校验。

原 `curl https://auth.12334123.xyz/bootstrap.sh | sh` 命令仍是单源下载，不会自动切换到此入口。首次获取启动器本身也需要一个可达的下载源，或使用已登录的 SSH 文件上传。

## 验证边界

sh/dash 语法检查、邮箱/支付模式、最快有效响应、错误 HTML 拒绝及全部失败不执行的模拟测试通过。路由器实机竞速、认证流程及中断清理仍需验证；仓库变更不包含授权服务器或 Worker 部署。
