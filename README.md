# caddy-build

自动检查 Caddy 是否有更新；若有更新，自动用指定插件重新编译 Caddy 二进制。
插件清单维护在单独文件中，当前包含：
- 端口转发（Layer 4）插件：`github.com/mholt/caddy-l4`
- Cloudflare DNS-01 证书插件：`github.com/caddy-dns/cloudflare`

## 功能
- 拉取 Caddy 最新稳定版标签
- 对比本地记录版本，发现更新后自动编译
- 使用 `plugins.txt` 统一维护插件列表
- 产出二进制到 `bin/`，并记录版本到 `state/`

## 依赖
- Go 1.21+（建议）
- `xcaddy`
- `git`, `curl`

安装 `xcaddy`（示例）：
```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
```

## 使用

1) 编辑插件列表（可按需增删）：
```
plugins.txt
```

2) 运行自动检查并编译：
```bash
./scripts/check_and_build.sh
```

3) 仅手动编译当前最新（或指定版本）：
```bash
./scripts/build.sh
```

## Alpine 一键安装脚本
适用于 Alpine/OpenRC 环境，从本仓库 GitHub Release 下载预编译的 musl 二进制（插件固定为本仓库构建配置），并可自动安装/更新 OpenRC 服务。

使用 curl 直接执行（需要 root）：
```bash
curl -fsSL https://raw.githubusercontent.com/weidix/caddy-build/main/scripts/install.sh | sh
```

注意：
- 当前 Release 仅提供 `amd64` 预编译包，如需其他架构请自行编译或扩展 CI。
- 运行时可选择 `musl` 或 `glibc` 版本；也可通过环境变量指定：`CADDY_VARIANT=musl|glibc`

## 插件清单
`plugins.txt` 一行一个插件模块路径（可带版本）：
```
github.com/caddy-dns/cloudflare
github.com/mholt/caddy-l4
```

## Cloudflare DNS 插件示例
在 Caddyfile 中使用 Cloudflare DNS 进行 ACME 验证：
```caddyfile
{
    email you@example.com
}

example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    respond "hello"
}
```

## 目录结构
```
.
├── README.md
├── plugins.txt           # 插件列表
├── scripts/
│   ├── build.sh          # 手动编译
│   └── check_and_build.sh# 检查更新并编译
├── bin/                  # 输出二进制（自动生成）
└── state/                # 版本记录（自动生成）
```

## 定时检查（可选）
使用 cron 每天检查一次：
```bash
0 3 * * * /path/to/caddy-build/scripts/check_and_build.sh >> /path/to/caddy-build/state/cron.log 2>&1
```

## GitHub Actions 自动编译
仓库内置工作流：每天定时检查 Caddy 最新版本。若发现新版本且当前仓库 Release 未包含该版本标签，将自动编译并发布 Release。

触发方式：
- 定时触发（每天 UTC 03:00）
- 手动触发（workflow_dispatch）

输出：
- Release 标签与 Caddy 版本一致
- Release 附件：
  - `caddy-glibc` / `caddy-<version>-glibc`
  - `caddy-musl` / `caddy-<version>-musl`
  - `SHA256SUMS.txt`

## 备注
- 若出现 GitHub API 限速，可在环境变量中提供 `GITHUB_TOKEN`。
- 如需固定版本构建：设置 `CADDY_VERSION` 环境变量。
