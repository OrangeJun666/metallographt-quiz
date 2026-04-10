# 金相大会刷题原型

一个可在电脑和手机浏览器运行的金相题库刷题工具，支持顺序刷题、随机刷题、错题重练、图片题显示和本地进度保存。

## 功能概览

- 支持单选/多选自动判题
- 支持题目配图显示（从 docx 自动提取）
- 支持选项范围 A-G
- 支持错题本与正确率统计
- 支持离线缓存（PWA）
- 支持一键启动/停止本地服务

## 项目结构

- `index.html`：页面结构
- `styles.css`：样式
- `app.js`：刷题逻辑（含进度本地存储）
- `manifest.webmanifest`：PWA 配置
- `service-worker.js`：离线缓存
- `data/question_bank.cleaned.json`：清洗后的题库数据
- `data/clean_report.txt`：数据清洗报告
- `assets/images/`：从题库中提取的图片资源
- `scripts/clean_question_bank.py`：题库清洗脚本
- `start_quiz.ps1` / `start_quiz.bat`：启动脚本
- `stop_quiz.ps1` / `stop_quiz.bat`：停止脚本

## 环境要求

- Windows + PowerShell
- Python 3.10+

## 本地运行

### 方式 1：双击启动（推荐）

直接双击：`start_quiz.bat`

启动后访问：

- 本机：`http://127.0.0.1:8000/index.html`
- 手机（同一 Wi-Fi）：`http://你的局域网IP:8000/index.html`

### 方式 2：PowerShell 启动

```powershell
.\start_quiz.ps1
```

可选参数：

```powershell
.\start_quiz.ps1 -Port 8000 -NoBrowser
```

## 停止服务

### 方式 1：双击停止

直接双击：`stop_quiz.bat`

### 方式 2：PowerShell 停止

```powershell
.\stop_quiz.ps1
```

可选参数：

```powershell
.\stop_quiz.ps1 -Port 8000 -Force
```

## 题库清洗

当前脚本会直接读取 `金相大会题库.docx`，并自动生成：

- `data/question_bank.cleaned.json`
- `data/clean_report.txt`
- `assets/images/`（图片提取）

执行命令：

```powershell
e:/AAA工作/大三/下学期学校/金相大会/code/.venv/Scripts/python.exe scripts/clean_question_bank.py
```

## 进度保存说明

- 做题进度保存于浏览器 `localStorage`
- 不同设备、不同浏览器的进度不共享
- 清理浏览器站点数据后进度会丢失

## GitHub Pages 远程访问（公网）

1. 将项目推送到 GitHub 仓库（建议 Public）
2. 打开仓库 `Settings -> Pages`
3. `Source` 选择 `Deploy from a branch`
4. 分支选 `main`，目录选 `/(root)`
5. 保存后等待 1-3 分钟，访问：

`https://你的用户名.github.io/你的仓库名/`

## 常见问题

### 1. 页面打不开/拒绝连接

- 确认服务是否已启动（先运行 `start_quiz.bat`）
- 确认端口是否是 8000
- 手机访问必须用局域网 IP，不能用 127.0.0.1

### 2. 图片不显示

- 先重新执行一次清洗脚本
- 检查 `assets/images/` 是否有图片文件
- 强制刷新浏览器（Ctrl+F5）

### 3. GitHub Pages 显示旧版本

- 等待部署完成
- 刷新缓存（Ctrl+F5）

## 备注

本项目定位为备考刷题工具原型，可在此基础上继续扩展：导入导出进度、账号同步、模拟考试等功能。
使用AI工具制作~
