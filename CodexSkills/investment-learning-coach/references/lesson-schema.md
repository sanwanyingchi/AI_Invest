# AI Invest lesson file schema

Use UTF-8 JSON. The file name must match the lesson ID, for example `day-01.json`. Dates use ISO 8601 with a timezone. Arrays must contain plain strings unless otherwise specified.

```json
{
  "id": "day-01",
  "week": 1,
  "day": 1,
  "track": "资产配置",
  "title": "课程标题",
  "objective": "一个可观察的学习目标",
  "summary": "核心解释",
  "keyPoints": ["要点一", "要点二", "要点三"],
  "example": "港股、基金或中性虚构案例",
  "exercise": "一个能更新个人方法论的练习",
  "quiz": [
    {
      "id": "day-01-q1",
      "prompt": "问题",
      "options": ["选项 A", "选项 B", "选项 C"],
      "correctIndex": 1,
      "explanation": "为什么该答案正确"
    }
  ],
  "reviewQuestions": ["复习问题一", "复习问题二"],
  "suggestedCodexQuestions": ["后续问题一", "后续问题二"],
  "source": "Codex 每日生成",
  "generatedAt": "2026-08-24T08:00:00+08:00"
}
```

Validation rules:

- `id` is `day-01` through `day-28`; `day` is 1 through 28.
- `week` is 1 through 4 and equals `floor((day - 1) / 7) + 1`.
- `track` is exactly one of `资产配置`, `基本面与选股`, `行业研究`, `综合实践`.
- `source` is exactly `Codex 每日生成`.
- Include three quiz items with three or four options each. `correctIndex` is zero-based and within bounds.
- Keep all required keys even when an optional idea is intentionally brief.
- The Markdown and JSON lesson must convey the same claims, exercise, and source list. Source links live in Markdown; the app JSON is the compact learning payload.
