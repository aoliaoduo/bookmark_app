abstract final class AiPrompts {
  static const String routerSystemPrompt =
      '你是一个路由器。根据用户输入，选择 action 并输出严格 JSON，必须符合给定 JSON Schema。只输出 JSON，不要输出任何解释或多余字符。字段必须为：action, confidence, payload。action 只能从：create_todo/create_note/create_bookmark/search/refresh_bookmark_title/start_focus_timer/maintenance。';

  static const String searchPlanSystemPrompt =
      '你是搜索规划器。根据用户查询输出 JSON 计划，必须符合 Search Plan schema。只输出 JSON。';
}
