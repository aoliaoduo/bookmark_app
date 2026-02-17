import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  String _versionLabel = '-';

  static const List<_ChangelogEntry> _entries = <_ChangelogEntry>[
    _ChangelogEntry(
      version: 'v0.5.20',
      notes: <String>[
        '输入网址区域改为单层轻玻璃容器，移除重纹理外壳，解决“框中框”观感',
        '输入区整体瘦身：输入框与收藏按钮高度下调，主操作区更紧凑',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.19',
      notes: <String>[
        '输入区视觉重构：去掉整行外层玻璃壳，改为“左侧输入框 + 右侧收藏按钮”独立结构',
        '修复“玻璃框里还有一层框”的观感问题，主操作区层级更简洁直接',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.18',
      notes: <String>[
        '修复 Windows 端启动后无响应问题：玻璃按钮在顶栏的布局约束已改为安全模式',
        '移除导致无界约束冲突的按钮内部展开布局，保证 AppBar 与窄宽度场景稳定渲染',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.17',
      notes: <String>[
        '首页关键按钮升级为实体玻璃按键：增加高光、阴影、渐变与按压反馈，点击质感更清晰',
        '顶部“收藏/回收站”切换重绘为胶囊玻璃分段按钮，色调与背景统一，不再有漂浮感',
        '列表行内操作按钮与搜索清空按钮统一玻璃风格，圆角、深浅层级和纹理细节保持一致',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.16',
      notes: <String>[
        '全局视觉升级：统一卡片、输入框、按钮圆角与阴影层级，整体观感更干净',
        '首页面板重绘：输入区、搜索区、信息栏改为统一玻璃感面板，信息密度更合理',
        '列表卡片与行内按钮样式重做：标题/链接/时间层级更清晰，操作按钮更精致',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.15',
      notes: <String>[
        '首页顶栏升级为“收藏/回收站”分段切换，替代单独回收站按钮，减少空白并提升切换效率',
        '顶栏新增轻量同步状态胶囊（同步中/已同步/同步失败/未配置），状态感知更直观',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.14',
      notes: <String>[
        '首页普通模式顶部标题已移除，不再显示“粮仓”或“收藏”文字',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.13',
      notes: <String>[
        '首页顶部标题改为通用“收藏”，不再显示应用名“粮仓”',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.12',
      notes: <String>[
        '更新日志列表不再展示具体日期，统一按版本号查看历史变更',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.11',
      notes: <String>[
        '本地数据写入链路加固：单条新增/更新标题/删除/恢复统一为“数据写入 + 同步出站入列”原子事务',
        '新增事务回归测试：覆盖 outbox 写入失败时整单回滚，避免本地状态与同步队列不一致',
        '控制层 loading 改为计数模型，修复并发操作下 loading 状态提前复位导致的交互抖动',
        '新增同步与备份并发保护：同步进行中禁止启动云备份，避免云侧操作竞态',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.10',
      notes: <String>[
        '新增 Markdown 导出：支持导出全部/导出已选为 .md 文件',
        'Markdown 导出格式为 [标题](链接)，并在每条之间保留一个空行',
        '导出文件选择与自动补全后缀逻辑已覆盖 MD 格式',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.9',
      notes: <String>[
        '首页排序新增持久化记忆：用户选择的排序方式会保存到本地配置',
        '应用重启后继续沿用上次排序（如“按最近添加”），无需重复切换',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.8',
      notes: <String>[
        '同步诊断弹窗新增“复制诊断”按钮，可一键复制完整诊断文本到剪贴板',
        '复制内容包含状态、时间、耗时、重试次数、上传下载统计与错误信息，便于快速排障',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.7',
      notes: <String>[
        '同步诊断统计拆分“过滤同设备”和“过滤重复操作”，避免混合计数造成误解',
        '同步诊断中的开始/结束时间显示精确到秒，便于排查短时同步问题',
        '新增本次结果总结文案：明确提示“本次无本地数据变更”或“已应用 X 条变更”',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.6',
      notes: <String>[
        '新增同步诊断面板：可查看最近一次同步的开始/结束时间、耗时、重试次数与失败原因',
        '同步统计增强：展示上传/下载数量、应用更新/删除数量、过滤重复与过期操作数量',
        '同步结果提示升级：手动和启动自动同步完成后会显示本次上传/下载与重试摘要',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.5',
      notes: <String>[
        '新增删除墓碑机制：本地记录被删除后会保存墓碑时间，阻止远端旧 upsert 将已删除链接“复活”',
        '同步冲突判定升级：每个链接只应用最新远端状态，并按本地状态与墓碑时间跳过过期操作',
        '数据库升级到 v2，新增墓碑表并支持升级迁移；瘦身清理支持回收过期墓碑',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.4',
      notes: <String>[
        '新增同步一致性回归测试矩阵，覆盖“删除防复活、远端旧删除忽略、远端恢复生效、同时间戳冲突”等场景',
        '同步引擎改为按“每个书签只应用最新远端操作”进行收敛，降低乱序批次导致的数据回退风险',
        '拉取应用前先对比本地逻辑时间，自动跳过落后于本地状态的远端旧操作',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.3',
      notes: <String>[
        '本地数据库启用更稳健的持久化配置（WAL、FULL、busy_timeout），降低异常中断下的数据损坏风险',
        '云同步与云备份新增网络超时与瞬时故障重试策略，弱网下成功率更高',
        '云备份新增完整性校验（bookmarkCount + SHA-256 digest），恢复前可识别损坏文件',
        '同步引擎新增远端操作去重和同设备操作忽略，避免重复应用造成状态抖动',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.2',
      notes: <String>[
        '首页列表新增时间信息展示：添加时间、更新时间',
        '回收站条目补充时间信息展示：添加时间、更新时间、删除时间',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.1',
      notes: <String>[
        '首页新增排序功能，可按最近更新/最近添加/标题 A-Z/网址 A-Z 切换',
        '排序对收藏与回收站列表都生效，并兼容搜索结果',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.5.0',
      notes: <String>[
        '操作逻辑全面升级：新增“启动自动同步”和“变更后自动同步”两项设置开关',
        '同步状态可视化：正在同步、最近成功时间、失败可重试提示统一展示',
        '手动/自动同步反馈统一，成功与失败都会给出清晰提示',
        '单条删除支持“撤销”，交互逻辑对齐主流应用习惯',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.13',
      notes: <String>[
        '恢复“单条删除”入口：每条收藏右侧增加直接“删除到回收站”按钮',
        '保持列表无“更多”菜单，单条常用操作固定为打开/复制/删除',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.12',
      notes: <String>[
        '启动自动云同步新增可视反馈，显示“正在自动云同步...”动画提示',
        '云同步结果统一提示：成功与失败都会弹出明确反馈',
        '移除每条链接的“更多”按钮，保留常用“打开网址/复制链接”操作，列表更简洁',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.11',
      notes: <String>[
        '列表项“打开网址 / 复制链接 / 更多”操作改为紧贴右侧并统一图标交互尺寸',
        '“云同步”从“更多功能”中独立为顶栏主按钮（桌面与移动端一致）',
        '应用启动时若 WebDAV 配置完整会自动执行一次云同步，贴近主流产品同步逻辑',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.10',
      notes: <String>[
        '修复“只下载不上传”的同步问题：删除操作会正常上传',
        '跨设备删除改为直接删除本地记录，避免把回收站状态同步到其他设备',
        '补充同步引擎回归测试，覆盖删除上传与远端删除落地场景',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.9',
      notes: <String>[
        '修复手机端“瘦身清理”执行 WAL checkpoint 报错导致流程中断',
        '数据库维护改为按能力执行：PRAGMA 统一走 rawQuery，非 WAL 场景自动跳过 checkpoint',
        '即使个别维护指令失败也会降级继续，避免用户一键瘦身直接失败',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.8',
      notes: <String>[
        '回收站改为本地状态：删除/恢复不再参与云同步',
        '同步拉取 JSON 改为按字节+编码解码，修复手机端中文字段（标题/备注等）乱码',
        '网页标题抓取新增 charset 识别（含 GBK/GB2312），提升中文站点标题识别准确性',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.7',
      notes: <String>[
        '修复 WebDAV Base URL 含 /dav 时拉取路径重复拼接导致“同步无报错但拉不到数据”',
        '同步拉取新增路径规范化，自动去除服务端 href 的 basePath 前缀',
        '补充回归测试，覆盖 /dav 前缀场景并防止出现 /dav/dav 重复路径',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.6',
      notes: <String>[
        '输入框提示简化为“输入网址”，移除示例 URL 文案',
        '新增“清空全部数据”功能，可一键重置收藏与同步配置',
        '每条收藏支持一键复制链接地址',
        '合并部分按钮到菜单，减少顶部与条目操作区的拥挤，风格更统一',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.5',
      notes: <String>[
        '修复 Android release 包缺少网络权限导致的云同步/备份域名解析失败',
        '主清单补充 INTERNET 权限，手机端同步与备份可正常访问 WebDAV',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.4',
      notes: <String>[
        '修复手机端顶部操作栏按钮过多导致右侧被遮挡的问题',
        '窄屏自动切换为“核心按钮 + 更多菜单”，所有功能都可点到',
        '批量模式顶部操作同样支持窄屏菜单收纳',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.3',
      notes: <String>[
        '修复 Windows 中文文字深浅不一致问题，统一中文字体渲染',
        '统一“外观模式”与主按钮文字样式，避免局部样式混用造成观感差异',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.2',
      notes: <String>[
        '修复云同步在 WebDAV 返回 409 时直接中断的问题（改为按空目录处理）',
        '云同步拉取兼容历史 ussers 目录路径，避免旧目录结构导致报错',
        'WebDAV Base URL 自动剥离 /BookmarksApp 子路径，减少配置误填影响',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.1',
      notes: <String>[
        '修复外观模式选项样式不统一，改为统一单选样式展示',
        '修复 Windows 目录切换导致的数据/配置丢失，新增旧目录自动迁移',
        '修复 Windows 标题栏中文名显示乱码',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.4.0',
      notes: <String>[
        '应用品牌升级为“粮仓”，首页标题与桌面窗口名同步调整',
        '新增深色模式（跟随系统/浅色/深色）并支持在设置页切换',
        '链接标题抓取失败时，列表中会显示错误提示并提供处理入口',
        '优化圆角阴影样式，卡片阴影与圆角边界保持一致',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.5',
      notes: <String>[
        '首页标题从“网址收藏”调整为“链接收藏”',
        '新增输入区按钮高度对齐，收藏按钮与输入框视觉统一',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.4',
      notes: <String>[
        '修复搜索栏双层边框样式问题，统一为单层输入框视觉',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.3',
      notes: <String>[
        'CI 调整为仅在 PR 场景自动取消进行中的旧任务',
        'main 分支推送任务不再被新推送自动中断，减少误判失败',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.2',
      notes: <String>[
        '修复搜索框展开时的位置冲突问题，改为固定位置展示',
        '搜索框视觉样式进一步弱化，避免抢占主流程注意力',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.1',
      notes: <String>[
        '搜索区域改为默认收起，视觉权重下调，避免干扰主操作',
        '回收站不再单独占用 Tab，改为主页内模式切换',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.3.0',
      notes: <String>[
        '同步游标改为基于 WebDAV 服务端时间，修复多设备时钟差导致的漏同步风险',
        'WebDAV 路径段统一做 URL 编码，提升特殊字符场景稳定性',
        'WebDAV 密码迁移到安全存储（含旧版明文配置自动迁移）',
        '快照备份文件名升级为时间戳格式，避免同日多次备份互相覆盖',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.2',
      notes: <String>[
        'Windows 端记住上次窗口尺寸，重启后自动恢复',
        '应用版本格式统一为纯语义版本（移除 +build 展示）',
        '统一主页/设置/关于/更新日志的视觉风格',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.1',
      notes: <String>[
        '修复导出时取消需要点两次的问题（现在点一次取消即可）',
        '优化导出路径选择交互一致性',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.2.0',
      notes: <String>[
        '新增回收站、清空回收站、批量操作、实时进度条',
        '新增去重（重复/相似）与一键标题更新',
        '新增导出、搜索、瘦身（仅清理无用数据）',
        '新增关于页与应用内更新日志页',
      ],
    ),
    _ChangelogEntry(
      version: 'v0.1.0',
      notes: <String>[
        '首版上线：本地优先收藏、WebDAV 云备份/同步',
        '支持自动抓取网页标题与按周期更新',
        '支持 Android / Windows 构建与运行',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = 'v${info.version}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionLabel = 'v0.5.20';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: const Text('当前应用版本'),
              subtitle: Text(_versionLabel),
            ),
          ),
          const SizedBox(height: 12),
          for (final _ChangelogEntry entry in _entries)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.version,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final String note in entry.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $note'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  const _ChangelogEntry({
    required this.version,
    required this.notes,
  });

  final String version;
  final List<String> notes;
}
