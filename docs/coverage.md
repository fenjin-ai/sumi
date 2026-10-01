# 覆盖率与 PR 报告

`scripts/test.sh` 对所有 `Sources/Sumi` 和 `Sources/SumiCore` 的唯一可执行源码行执行 80% 门槛，包含原生界面，不包含测试本身或生成的测试启动代码。功能测试运行真实编辑器、WKWebView 和 Tinymist；小型边界测试覆盖协议和文本范围。

`scripts/coverage.py` 同时输出本地 HTML、原始 LLVM 数据和用于 Codecov 的 `build/coverage/codecov.lcov`。后者按文件和行去重，使用仓库相对路径，并与本地门槛使用完全相同的生产代码范围。Codecov 上传关闭额外报告搜索、自动生成报告和源码行修正，避免上传测试自身的覆盖率或改变分母。

## GitHub 和 Codecov

- main 与 PR 的 Apple Silicon CI 都上传报告；即使覆盖率低于门槛，只要报告已经生成，仍上传用于诊断。
- 同仓库构建使用 GitHub OIDC 短期身份，不需要 `CODECOV_TOKEN`。公开仓库的 fork PR 使用 Codecov 官方支持的免 token 上传。
- `codecov.yml` 配置整体覆盖率与新增/修改行覆盖率各 80% 的状态检查，并在 PR 内更新一条包含整体变化、差异覆盖率和文件明细的评论。
- README 徽章和 [Codecov 仓库页](https://app.codecov.io/github/fenjin-ai/sumi) 显示 main 分支覆盖率。原始报告和 HTML 仍保存在 GitHub Actions 的 `coverage-macos-15` artifact。

Codecov GitHub App 需要仅授权 `fenjin-ai/sumi`，才能读取提交、更新检查状态并发布 PR 评论。安装应用与报告上传是两个步骤；成功上传后，还应在真实 PR 上核对 Codecov 评论和检查是否出现。首次接入尚无 main 基线时，评论可先展示当前报告；合入 main 并上传基线后，后续 PR 可显示完整覆盖率变化。

## 接入验证

2026-10-01 已将 Codecov GitHub App 的仓库权限限定为 `fenjin-ai/sumi`。[首次接入 PR](https://github.com/fenjin-ai/sumi/pull/1) 的 CI 通过 GitHub OIDC 上传，未配置 Codecov 长期 token。平台报告与从 GitHub artifact 下载的 LCOV 独立核验一致：21 个生产代码文件，2,107 / 2,442 个唯一可执行源码行，覆盖率 86.28%。这次比较验证的是同一次运行的两个输出；后续版本的比例以对应提交的报告为准。

初次 PR 缺少 main 基线时，Codecov 会发接入欢迎评论。合入 main 后的上传建立比较基线，后续 PR 才会显示完整数字报告及状态检查。

参考：[官方 Action 的 OIDC 配置](https://github.com/codecov/codecov-action#using-oidc)、[公开仓库上传](https://docs.codecov.com/docs/codecov-tokens)、[状态检查](https://docs.codecov.com/docs/commit-status)、[PR 评论](https://docs.codecov.com/docs/pull-request-comments)。
