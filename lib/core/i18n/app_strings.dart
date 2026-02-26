abstract final class AppStrings {
  static const String appTitle = 'AI First Local Productivity';

  static const String navTitle = '导航';
  static const String navSubtitle = '一级入口固定 3 个';
  static const String inbox = '收件箱';
  static const String library = '资料库';
  static const String focus = '专注';

  static const String loadingDb = '正在初始化本地数据库...';
  static const String dbInitFailed = '数据库初始化失败：';

  static const String inboxHint = '输入自然语言（M2 接入 AI Router）';
  static const String inboxDraftHint = '草稿队列占位：后续接入 inbox_drafts';
  static const String openAiProviderSettings = '打开 AI Provider 设置';
  static const String send = '发送';
  static const String sending = '发送中...';
  static const String draftListTitle = 'AI 失败草稿';
  static const String retry = '重试';
  static const String delete = '删除';
  static const String submitSuccess = '已执行动作并落库';
  static const String inboxNeedInput = '请输入内容';
  static const String inboxNeedModel = '请先在 AI Provider 设置中选择模型';
  static const String focusPlaceholder = '专注模块占位（M4 实现）';

  static const String todoTab = 'Todo';
  static const String noteTab = 'Note';
  static const String bookmarkTab = 'Bookmark';

  static const String debugMenuTooltip = '调试菜单';
  static const String debugSeed = '生成测试数据(1000)';
  static const String debugClear = '清空测试数据';
  static const String seedInProgress = '正在生成测试数据...';
  static const String seedDone = '已生成 1000 条测试数据';
  static const String clearInProgress = '正在清空测试数据...';
  static const String clearDone = '测试数据已清空';

  static const String emptyTodos = '暂无待办';
  static const String emptyNotes = '暂无笔记';
  static const String emptyBookmarks = '暂无收藏';

  static const String statusOpen = 'open';
  static const String statusDone = 'done';
  static const String tagCountPlaceholder = '标签 0';
  static const String noteOrganizedOnly = '整理版展示（原文隐藏）';

  static const String loadingMore = '加载中...';

  static const String aiProviderTitle = 'AI Provider 设置';
  static const String baseUrlLabel = 'Base URL';
  static const String apiKeyLabel = 'API Key';
  static const String selectedModelLabel = '模型';
  static const String save = '保存';
  static const String refreshModels = '刷新模型列表';
  static const String testConnection = '测试连接';
  static const String batchTestModels = '批量测试模型';
  static const String stopBatchTest = '停止批测';
  static const String clearCredential = '一键清除已保存凭据';
  static const String batchTesting = '批测进行中...';
  static const String batchStopped = '批测已停止';
  static const String batchDone = '批测完成';
  static const String saved = '保存成功';
  static const String cleared = '已清除保存凭据';
  static const String providerNeedFields = '请先填写 base_url 和 api_key';
  static const String modelListEmpty = '暂无模型，请先刷新模型列表';
  static const String riskTitle = '风险确认';
  static const String riskContent = '将以明文方式保存 API Key（按 PRD 要求），存在泄露风险。';
  static const String riskCheckbox = '我已知晓风险';
  static const String confirm = '确认';
  static const String cancel = '取消';
}
