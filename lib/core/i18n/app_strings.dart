abstract final class AppStrings {
  static const String appTitle = 'AI First Local Productivity';

  static const String navTitle = '导航';
  static const String navSubtitle = '一级入口固定 3 个';
  static const String inbox = '收件箱';
  static const String library = '资料库';
  static const String focus = '专注';
  static const String search = '搜索';
  static const String syncAndBackup = '同步/备份';

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
  static const String focusModeCountdown = '倒计时';
  static const String focusModeCountup = '正计时';
  static const String focusDurationLabel = '专注时长';
  static const String focusMinuteUnit = '分钟';
  static const String focusPhaseIdle = '空闲';
  static const String focusPhaseFocus = '专注中';
  static const String focusPhaseBreak = '休息中';
  static const String focusStart = '开始';
  static const String focusPause = '暂停';
  static const String focusResume = '继续';
  static const String focusStop = '结束';
  static const String focusSkipBreak = '跳过休息';
  static const String focusNotificationSelfCheck = '通知自检（10秒）';
  static const String focusSelfCheckQueued = '已安排 10 秒后提醒';
  static const String focusErrorPrefix = '专注状态错误：';

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
  static const String noteViewRaw = '查看原文';
  static const String noteReorganize = '重新整理';
  static const String noteDetailTitle = '笔记详情';

  static const String loadingMore = '加载中...';
  static const String bookmarkSelectMode = '多选';
  static const String bookmarkSelectAll = '全选';
  static const String bookmarkExitSelect = '退出多选';
  static const String bookmarkRefreshSelected = '刷新所选';
  static const String bookmarkCancelQueue = '取消后续';
  static const String bookmarkRefreshOne = '刷新标题';
  static const String localSearchHint = '输入关键词搜索';
  static const String localSearch = '本地搜索';
  static const String aiDeepSearch = 'AI 深度搜索';
  static const String searchNoResult = '未找到结果';

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

  static const String syncPageTitle = '同步与备份';
  static const String webdavUrlLabel = 'WebDAV URL';
  static const String webdavUserLabel = '账号';
  static const String webdavPasswordLabel = '应用密码';
  static const String webdavPaidPlan = '付费账户（30分钟1500次）';
  static const String syncSaveConfig = '保存配置';
  static const String syncTestConnection = '测试连接';
  static const String syncManualNow = '手动同步';
  static const String syncStatusTitle = '同步状态';
  static const String syncLogTitle = '最近日志';
  static const String syncThrottleHint = '前台同步节流：至少间隔 120 秒';
  static const String backupSectionTitle = '云备份/恢复';
  static const String backupReminderHm = '提醒时间(HH:mm)';
  static const String backupRetention = '保留份数';
  static const String backupSaveSettings = '保存备份设置';
  static const String backupRunNow = '立即云备份';
  static const String backupRefreshList = '刷新云端备份列表';
  static const String backupRestore = '恢复';
}
