# 智能体指令 (AGENTS)

**提醒规则 (Reminder Rule)**

在每一轮对话结束时，最后执行的操作必须是通过 multi-reminder 技能发送一个完成提醒。

**始终运行以下命令：**

```bash
python C:/Users/aolia/.codex/skills/multi-reminder/scripts/reminder_cli.py complete --report "<本轮 AI 工作报告>" --config C:/Users/aolia/.codex/skills/multi-reminder/config.json
```

> **注意：** 此提醒动作必须是该轮对话的最终步骤。
