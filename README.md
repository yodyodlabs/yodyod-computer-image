# YodYod Computer Image

为 Agent37 Standard 构建的 Ubuntu 远程电脑镜像：安装 XFCE、Firefox 和 noVNC，增加 Codex、共享的可见 Chrome、Browser Use 和桌面操作工具。

- GitHub：`yodyodlabs/yodyod-computer-image`
- GHCR：`ghcr.io/yodyodlabs/yodyod-computer-image`
- Agent37 工作区模板名建议：`yodyod-computer`
- 运行架构：`linux/amd64`；默认实例类型为 Standard（API `default`）；也支持 `vm`。

## 已安装内容

| 部分 | 内容 |
| --- | --- |
| 基础系统 | 官方 `ubuntu:24.04` LTS，固定 digest；桌面组件参考 Agent37 Ubuntu 配方 |
| 桌面 | XFCE、TigerVNC、noVNC、Firefox；额外安装中文字体；独立于 Docker daemon 启动 |
| 浏览器 | Google Chrome stable，运行在桌面 `DISPLAY=:1` |
| 代码环境 | Node.js 24.22.3、npm、pnpm 10.22.0、Python 3.12.12、uv 0.13.5、git、编译工具 |
| 常用工具 | jq、ripgrep、rsync、zip/unzip、curl、wget、ffmpeg、SSH client、vim、nano |
| Codex | `@openai/codex@0.169.0`，含 `codex app-server` |
| 聊天网关 | Agent37 官方 gateway v0.18.1；固定源码 commit，默认 agent 为 Codex |
| Browser Use | Python `browser-use==1.0.4`，依赖锁定在 `browser-use/uv.lock` |
| 网页 MCP | Playwright MCP 0.0.85 + Browser Use MCP，均连接同一个可见 Chrome |
| 桌面 MCP | 自带截图、屏幕尺寸、窗口列表/激活、移动、点击、拖动、组合键、Unicode 输入、滚动工具 |

浏览器自动化使用的是桌面里的同一个 Chrome，而非另一台云浏览器。用户可以在 noVNC 里观看和接管。Browser Use 的本地 MCP 由 Codex 自己调用，不需要额外购买 Browser Use Cloud；如果从 Python 代码运行 Browser Use 的独立 `Agent`，仍需为那个 agent 配置模型。

Chrome 在电脑启动时打开一次，手动关闭后保持关闭。XFCE 下方的浏览器快捷图标、桌面「网页浏览器」及 HTTP/HTTPS 链接都通过 `yodyod-browser` 打开同一持久 Chrome 配置；关闭浏览器不影响桌面健康。使用浏览器 MCP 前，先从快捷图标或终端 `yodyod-browser` 打开 Chrome。

该镜像不包含模型密钥、GitHub 凭据或任何人的登录数据。Codex 模型费用使用实例自己的 OpenAI 账户或 API Key。

## 发布到 GHCR

推送到 `main` 后，GitHub Actions 会：

1. 在原生 amd64 的 Ubuntu runner 上构建镜像。
2. 启动带独立持久 home 的测试容器，测试真实桌面、浏览器、三个 MCP 和 Codex app-server。
3. 重启容器，验证文件和 Chrome cookie 保留。
4. 只有全部通过才向 GHCR 推送镜像。

镜像标签：

- `sha-<完整 Git commit SHA>`：每次成功构建的固定版本，注册 Agent37 时使用它或 digest。
- `latest`：`main` 最近一次成功构建，便于开发试用。
- `0.1.0` 等：推送 `v0.1.0` Git tag 后生成的版本标签。

Actions 使用内置 `GITHUB_TOKEN`，只授予 `contents: read` 和 `packages: write`。无需配置个人 GitHub Token 才能发布。仓库为私有时，首个关联 package 默认也是私有；此工作流不会修改仓库或 package 的公开性。

GitHub → Actions → **Build, verify and publish computer image** → 最后一个步骤的 Summary 会显示已验证的 SHA 标签和 digest。

基础镜像、Node、Python、Codex、主要工具版本和依赖有锁定。Google Chrome stable 与 Ubuntu 的 apt 包有意在重建时获取更新，因此同一源码的未来重建不保证位级一致；每次发布后以 GHCR digest 为准。

## 注册 Agent37 模板

GHCR 镜像必须先注册为 workspace template，不能直接把镜像地址传入创建实例接口。注册会把镜像复制到 Agent37 的私有存储并固定 digest。

私有镜像需要一个可以读取组织 package 的 GitHub **PAT classic**，权限为 `read:packages`；如组织启用 SSO，还需授权该组织。`GHCR_USERNAME` 使用这个 Token 所属的 GitHub 用户名，不是组织名。

在终端里安全设置环境变量，然后执行：

```bash
export AGENT37_API_KEY='你的 Agent37 工作区 Key'
export GHCR_USERNAME='Token 所属的 GitHub 用户名'
read -rs GHCR_TOKEN
export GHCR_TOKEN

python3 scripts/register-template.py \
  --image 'ghcr.io/yodyodlabs/yodyod-computer-image:sha-完整提交SHA'
```

该脚本注册或更新 `yodyod-computer` 模板，设置默认网关端口 `3737`，只输出模板名、revision 和 digest。它**不会创建实例、修改已有电脑或触发应用切换**。模板名已存在时更新同一个模板；同一 image_ref 不重复更新。

如果你主动把 GHCR package 改为公开，注册时可以不提供 `GHCR_USERNAME` 和 `GHCR_TOKEN`。源代码仓库与 package 的公开性是两项独立设置。

Agent37 不保存注册时的 registry 登录凭据；下次导入新的私有镜像版本，需要再次提供。推送同一个 GHCR tag 不会自动更新 Agent37 模板。

### 直接在 Agent37 构建

也可上传本目录的构建上下文，由 Agent37 构建并发布同名模板，不需要 GHCR 读取凭据。GHCR 发布仍由上述 Actions 独立完成。

```bash
COPYFILE_DISABLE=1 npx agent37 templates build . \
  --name yodyod-computer --default-port 3737
```

`COPYFILE_DISABLE=1` 避免 macOS 打包时附带 `._*` AppleDouble 文件；这些元数据也已加入忽略规则。上传前检查 `.dockerignore`，不要把密钥或登录配置放进构建上下文。重复构建会增加模板 revision，已有实例需要显式更新才使用新镜像。

### 真实实例验证

Standard 不支持嵌套 user namespaces。Ubuntu 26.04 的 glycin 图标加载器依赖 bubblewrap，会导致 XFCE 因图标解码失败而退出；因此镜像使用 Ubuntu 24.04 LTS。桌面关闭合成效果，健康检查还会等待窗口管理器。Codex 按官方 Agent37 Codex 镜像的方式以实例为沙箱，在首次引导时补齐 `approval_policy="never"`、`sandbox_mode="danger-full-access"`；保留用户显式配置。

Actions 中的 smoke test 在普通 Docker 容器中运行，不能代替 Agent37 Standard/gVisor 的真实实例验证。模板注册成功或控制台显示 `running` 后，还需检查实例启动日志中的 `health.running`、实际执行 `/opt/yodyod/runtime/healthcheck.sh`，并确认桌面端口可访问。可通过 Agent37 exec 运行以下测试，不需要模型密钥或付费模型调用：

```bash
/opt/yodyod/runtime/healthcheck.sh
node /opt/yodyod/tools/tests/smoke.mjs
```

镜像必须从 `WORKDIR /` 启动。Agent37 挂载空数据盘后，镜像中的 `/root/workspace` 会被遮住；若把它设置为 `WORKDIR`，VM launcher 在执行入口前切换目录就会失败，日志却显示 `fork/exec /usr/bin/tini: no such file or directory`，后续 exec 同样报找不到 `sh`。入口脚本必须先能启动，再创建工作目录。CI 检查镜像 `WorkingDir=/`，并使用 `volume-nocopy` 的空 home 测试，避免 Docker 自动填充 volume 掩盖这类错误。

系统镜像修复后，使用 `POST /v1/instances/{id}/update` 更新原实例，保留 `/root` 数据盘；持久目录以外的系统改动会重置。不要删除实例来代替更新。

## 创建实例和接入 YodYod

Standard 在 API 中写作 `type: "default"`，仅支持 `us`，适用于桌面、Codex、浏览器和普通代码任务。VM 的计算费率为 Standard 的 2.5 倍；当前镜像不安装或启动 Docker daemon。需要嵌套 Docker/Kubernetes 时，应另建 VM 模板。

实例启用自动休眠，空闲阈值为 300 秒。Agent37 按实例 URL 的流量判定空闲，持续传输数据的桌面或终端连接可能推迟休眠。已有实例不能原地修改类型；从 VM 转为 Standard 需要新建实例并迁移持久数据，随后停止旧 VM。

注册后可创建测试实例，例如：

```bash
curl -X POST https://api.agent37.com/v1/instances \
  -H "Authorization: Bearer $AGENT37_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "template": "yodyod-computer@1",
    "type": "default",
    "region": "us",
    "resources": {"cpu": 2, "memory": 4, "disk": 30},
    "mount_path": "/root",
    "auto_sleep": true,
    "idle_timeout_seconds": 300
  }'
```

将 `@1` 替换成注册返回的 revision。上面会创建计费资源，请在真正需要实例时运行。2 CPU / 4 GB 可用于轻量任务，多个大型页面或编译任务建议 4 CPU / 8 GB。持久磁盘还要容纳项目依赖和浏览器配置。

YodYod 应用中对应配置：

```dotenv
AGENT37_TEMPLATE=yodyod-computer@1
AGENT37_INSTANCE_TYPE=default
AGENT37_DESKTOP_PORT=6080
AGENT37_WORKSPACE_PATH=/root/workspace
```

当前 YodYod 后端的创建逻辑把磁盘固定为 10 GB，需要在应用仓库另行调整到计划容量；这里的 README 示例不会改变应用行为。更换配置只影响新建实例，已有实例保留原来的模板和磁盘。

### 登录 Codex

在实例桌面终端执行：

```bash
codex login --device-auth
```

也可在创建实例的 `env` 中提供 `OPENAI_API_KEY` 或 `CODEX_API_KEY`。启动脚本会通过 `codex login --with-api-key` 完成登录，不会覆盖已有的有效 ChatGPT 登录。请通过你的服务端或 Agent37 管理界面传入密钥，永远不要把密钥写入 Dockerfile 或提交到仓库。

登录前，桌面、网页自动化和文件环境可正常使用，但 Codex 聊天请求不能完成；`/v1/health?agent=codex` 的 agent 健康状态会反映尚未登录。

### 访问端口

| 端口 | 用途 | 访问方式 |
| --- | --- | --- |
| 3737 | 官方 Codex gateway，提供 `/v1/responses`、sessions、files、health | 实例主 URL，走 Agent37 认证 |
| 6080 | noVNC 桌面和 `/websockify` | 服务端签发短效 signed URL |
| 9222 | Chrome DevTools/CDP | 仅实例 loopback，禁止配置 public port |
| 5900 | 官方 VNC | 仅实例 loopback |

Codex app-server 由 gateway 按需通过 stdio 启动，**不额外开放未经认证的 app-server WebSocket 端口**。本镜像没有占用 8080 或 7681；终端可用桌面里的 xfce4-terminal、Agent37 exec 或平台 SSH。

## 浏览器和桌面工具

首次启动时，`runtime/bootstrap.py` 把以下 MCP 配置加入持久化 `~/.codex/config.toml`：

- `yodyod_browser`：Playwright MCP，连接 `http://127.0.0.1:9222`。
- `yodyod_browser_use`：`browser-use --cli-mcp`，设置 `BU_CDP_URL` 连接同一个 Chrome。
- `yodyod_desktop`：本仓库的 stdio MCP，操作 `DISPLAY=:1`。

已有同名 MCP 配置会保留，不覆盖用户设置。默认指导写入 `/root/AGENTS.md`，也只在文件不存在时创建。工具和默认配置源文件安装在 `/opt`，不会被 `/root` 的持久磁盘遮住。

验证配置：

```bash
codex mcp list
browser-use --version
```

Browser Use CLI 示例（当前 1.x 接口，使用本地共享 Chrome）：

```bash
browser-use <<'PY'
new_tab('https://example.com')
print(page_info())
PY
```

桌面控制工具名：`desktop_screenshot`、`desktop_get_screen_size`、`desktop_list_windows`、`desktop_focus_window`、`desktop_move`、`desktop_click`、`desktop_drag`、`desktop_key`、`desktop_type`、`desktop_scroll`。坐标使用原始截图像素；中文和 Unicode 输入通过 clipboard 粘贴。输入前先激活目标窗口，并点击目标输入框；只设置网页 DOM 焦点不能把键盘焦点从浏览器地址栏移入页面。

浏览器和桌面工具应串行调用。应用的“用户接管”按钮还需要在应用层取消或暂停当前 agent 回合；镜像不会自动知道用户何时点击了前端按钮。

Chrome 以 root 运行在隔离实例中，启动参数含 `--no-sandbox`；CDP 不对外监听。每个用户使用独立实例。

## 本地构建与验证

```bash
docker buildx build --platform linux/amd64 --load -t yodyod-computer:test .
bash scripts/smoke-test.sh yodyod-computer:test
```

完整 smoke test 会启动一个临时普通容器和空 Docker volume，测试完成后清理。默认不启动 Docker daemon，桌面健康检查也不依赖它。

测试不调用模型、不创建 Agent37 实例、不使用任何业务凭据。它覆盖：

- `/root` 被空 volume 覆盖后，首次引导能补齐配置，且重复引导不覆盖用户配置。
- noVNC、Chrome CDP、官方 gateway 可用，启动不依赖 Docker daemon。
- Codex app-server JSON-RPC initialize 握手成功。
- Playwright MCP 能操作可见网页。
- 桌面 MCP 截图是有效 PNG，鼠标、组合键和中文粘贴可用。
- Browser Use MCP 在不提供云 Key 时连接同一个 Chrome。
- 重启后工作文件和浏览器持久 cookie 仍存在。

真实模型回合需要在测试实例上登录 Codex 后另行验证；CI 不会使用用户的 OpenAI 账户。

## 官方依据

- [Agent37 自定义镜像](https://www.agent37.com/docs/agents-api/custom-image)
- [Agent37 模板注册、版本和更新](https://www.agent37.com/docs/agents-api/templates)
- [Agent37 VM 与 Ubuntu](https://www.agent37.com/docs/agents-api/vm-instances)
- [官方 Ubuntu Dockerfile 和启动脚本](https://github.com/agent37-platform/templates/tree/main/images/vm/ubuntu)
- [Agent37 官方 Codex 镜像](https://www.agent37.com/docs/agents-api/codex)
- [OpenAI Codex app-server](https://developers.openai.com/codex/app-server/)
- [Browser Use CLI](https://docs.browser-use.com/open-source/browser-use-cli)
- [Browser Use MCP](https://docs.browser-use.com/open-source/mcp)
- [Playwright MCP](https://github.com/microsoft/playwright-mcp)

## 目录

```text
Dockerfile                    镜像及官方 gateway 构建
package.json / package-lock.json  Codex、Playwright 和 MCP SDK 锁定
browser-use/                  Browser Use Python 环境及 uv.lock
config/                       首次启动的 Codex MCP 和 agent 指导
runtime/                      首次引导、服务启动、Chrome、健康检查
tools/desktop-mcp.mjs          桌面操作 MCP
tests/                        配置、协议和真实桌面/浏览器验证
scripts/smoke-test.sh          完整容器 smoke test
scripts/register-template.py   手动注册/更新 Agent37 模板
.github/workflows/publish.yml  先测试、后发布 GHCR
```
