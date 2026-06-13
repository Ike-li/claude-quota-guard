# Development Guide

本指南介绍如何高效开发和调试 Claude Quota Guard。

---

## 开发模式设置

### 推荐：符号链接 + 本地配置

这是**最快**的开发模式，改代码立即生效。

#### 1. 克隆到开发目录

```bash
# 克隆到你的开发目录（不是 .claude/skills/）
git clone https://github.com/raylee/claude-quota-guard ~/code/claude-quota-guard
cd ~/code/claude-quota-guard
```

#### 2. 创建符号链接

```bash
# 创建符号链接到 .claude/skills/
ln -s ~/code/claude-quota-guard ~/.claude/skills/quota-guard

# 验证
ls -la ~/.claude/skills/quota-guard
# 应该显示: quota-guard -> /Users/你的用户名/code/claude-quota-guard
```

#### 3. 配置 settings.json

```bash
# 运行安装（会自动使用符号链接路径）
cd ~/code/claude-quota-guard
/quota-guard setup
```

**验证配置**：
```bash
jq '.statusLine.command' ~/.claude/settings.json
# 应该显示: bash /Users/.../code/claude-quota-guard/statusline-command.sh
```

---

## 开发工作流

### 日常开发（推荐）

```bash
# 1. 编辑代码
vim statusline-command.sh

# 2. 语法检查（可选）
bash -n statusline-command.sh

# 3. 重启 Claude Code
# （文件菜单 → Restart 或 Cmd+Q 重启）

# 4. 验证改动
/quota-guard doctor
```

**无需重新安装！** 符号链接自动指向最新代码。

---

### 调试 Bash 脚本

#### 方法 1：手动测试

```bash
# 测试 statusline
echo '{"context_window":{"used_percentage":50}}' | \
  bash statusline-command.sh

# 测试 guard
bash hooks/guard.sh

# 测试 collect
echo '{"context_window":{"used_percentage":50}}' | \
  bash hooks/collect.sh
```

#### 方法 2：启用调试输出

在脚本开头添加：
```bash
set -x  # 打印每条执行的命令
```

或者运行时启用：
```bash
bash -x statusline-command.sh
```

#### 方法 3：查看日志

```bash
# 实时查看日志
tail -f ~/.claude/quota-guard.log

# 最近 50 条
tail -50 ~/.claude/quota-guard.log
```

---

### 调试 CLI（TypeScript）

```bash
cd cli

# 开发模式（自动重编译）
npm run dev

# 手动编译
npm run build

# 测试 CLI
../bin/quota-guard query
../bin/quota-guard watch

# 类型检查
npm run type-check

# 运行测试
npm test
```

---

## 快速验证

### 验证 Hooks 是否生效

```bash
# 1. 检查配置
/quota-guard doctor

# 2. 检查 snapshot 是否更新
watch -n 1 'ls -lh ~/.claude/.quota-now* | head -5'
# 应该看到时间戳每 10 秒更新

# 3. 手动触发 guard
bash hooks/guard.sh
# 如果超过阈值，会输出信号
```

---

## 调试技巧

### 1. 模拟高额度场景

```bash
# 创建假的 90% 使用率 snapshot
echo -e "90\t90\t0\t0\t0\t90\t0\t0" > ~/.claude/.quota-now

# 运行 guard，应该看到信号
bash hooks/guard.sh
```

### 2. 降低阈值快速测试

```bash
/quota-guard config
# 编辑: "ctxHalt": 30  (从 85 改到 30)

# 现在正常使用 Claude Code
# 上下文达到 30% 就会触发信号
```

### 3. 测试不同终端颜色支持

```bash
# 强制 16 色模式
unset COLORTERM
export TERM=xterm

# 强制 truecolor
export COLORTERM=truecolor

# 重启 Claude Code 后查看 statusline
```

### 4. 隔离测试（不影响真实配置）

```bash
# 使用临时配置目录
export CLAUDE_CONFIG_DIR=/tmp/test-claude
mkdir -p $CLAUDE_CONFIG_DIR

# 运行测试
bash hooks/collect.sh < test-input.json
```

---

## 测试清单

**每次改动后运行**：

```bash
# 1. 语法检查
bash -n hooks/collect.sh
bash -n hooks/guard.sh
bash -n statusline-command.sh
bash -n skill/quota-guard.sh

# 2. CLI 编译
cd cli && npm run build

# 3. 运行 doctor
/quota-guard doctor

# 4. 查看 statusline（重启 Claude Code 后）
# 目视检查底部状态栏

# 5. 运行测试套件
bash test/test_guard.sh
cd cli && npm test
```

---

## 发布前检查

准备发布时：

```bash
# 1. 更新版本号
vim plugin.json  # 修改 version
vim CHANGELOG.md  # 添加新版本

# 2. 完整测试
bash test/test_guard.sh
cd cli && npm test

# 3. 文档检查
# 确保 README, getting-started, troubleshooting 是最新的

# 4. 提交
git add -A
git commit -m "chore: bump version to x.y.z"
git tag v1.0.0
git push origin main --tags
```

---

## 生产模式（用户安装）

用户通过以下方式安装：

```bash
# 方式 1: 手动克隆（当前推荐）
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard
/quota-guard setup

# 方式 2: Claude plugin（未来）
claude plugin install quota-guard
```

---

## 多环境管理

### 场景：同时维护多个版本

```bash
# 开发版（符号链接）
ln -s ~/code/claude-quota-guard ~/.claude/skills/quota-guard-dev

# 稳定版（真实目录）
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard

# 在配置中切换
# ~/.claude/settings.json:
{
  "statusLine": {
    "command": "bash ~/.claude/skills/quota-guard-dev/statusline-command.sh"
    // 或
    "command": "bash ~/.claude/skills/quota-guard/statusline-command.sh"
  }
}
```

---

## 常见问题

### Q: 改了代码但没生效？

**A**: 忘记重启 Claude Code。Bash 脚本在每次运行时重新加载，但需要重启才能让 hooks 重新注册。

### Q: 符号链接断了？

**A**: 检查目标目录是否存在：
```bash
ls -la ~/.claude/skills/quota-guard
# 如果显示红色或 "No such file"，重新创建：
rm ~/.claude/skills/quota-guard
ln -s ~/code/claude-quota-guard ~/.claude/skills/quota-guard
```

### Q: 如何回到稳定版？

**A**: 
```bash
# 删除符号链接
rm ~/.claude/skills/quota-guard

# 重新克隆稳定版
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard

# 重新安装
/quota-guard setup
```

---

## 贡献指南

准备提交 PR？

1. Fork 仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 使用符号链接本地测试（上述开发模式）
4. 运行所有测试：`bash test/test_guard.sh && cd cli && npm test`
5. 更新文档（如果改了用户可见功能）
6. 提交 PR

更多详见：[CONTRIBUTING.md](CONTRIBUTING.md)（待创建）

---

## 工具链

**推荐开发工具**：

- **编辑器**: VS Code + ShellCheck 扩展
- **调试**: `bash -x` + `set -x`
- **测试**: 内置测试脚本（`test/test_guard.sh`）
- **CI**: GitHub Actions（待配置）

---

## 参考

- [Getting Started](getting-started.md) - 用户安装指南
- [Architecture](architecture.md) - 技术架构（待创建）
- [Troubleshooting](troubleshooting.md) - 常见问题
