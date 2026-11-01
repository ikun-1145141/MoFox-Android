import 'package:mofox_android/app/router/app_router.dart';

/// FAQ 条目内的页内跳转动作（跳到设置里的相关修复入口）。
class TroubleshootingJump {
  const TroubleshootingJump({required this.label, required this.route});

  final String label;
  final String route;
}

/// 一条常见问题：症状（标题）+ 可能原因 + 自助步骤 + 可选跳转。
///
/// 内容为随 App 内置的静态数据，条目来自真实踩坑案例，更新随版本走。
class TroubleshootingEntry {
  const TroubleshootingEntry({
    required this.title,
    required this.causes,
    required this.steps,
    this.jump,
  });

  final String title;
  final List<String> causes;
  final List<String> steps;
  final TroubleshootingJump? jump;
}

const List<TroubleshootingEntry> troubleshootingEntries =
    <TroubleshootingEntry>[
  TroubleshootingEntry(
    title: 'SnowLuma WebUI 打不开（提示地址尚未就绪）',
    causes: <String>[
      'WebUI 服务（5099 端口）还在冷启动',
      'node 运行时缺失或版本不达标',
      'SnowLuma 配置文件丢失',
    ],
    steps: <String>[
      '等待 1 分钟后重试',
      '仍打不开：回到实例页点「SnowLuma 重启」',
      '查看「报错汇总」里的 WebUI 自检行，确认 node 与配置文件状态',
    ],
  ),
  TroubleshootingEntry(
    title: '一直显示「等待扫描」',
    causes: <String>[
      'QQ 停在快捷登录窗口，没有人点登录',
      'QQ 已登录但 hook 引擎未接管，登录事件未上报',
    ],
    steps: <String>[
      '点扫码面板里的「点击登录」按钮（发送回车触发快捷登录）',
      'QQ 已进入主界面仍不消失：重启 SnowLuma 后重新登录',
    ],
  ),
  TroubleshootingEntry(
    title: 'bot 不回消息 / 假死',
    causes: <String>[
      'bot 或 SnowLuma 进程未在运行',
      'QQ 登录态失效，OneBot 未上线',
    ],
    steps: <String>[
      '在实例页确认「Bot 主程序」和「SnowLuma」都是运行中',
      '先重启 SnowLuma，等它运行起来后再重启 Bot 主程序（顺序不要反）',
      '给 bot 发一条消息验证是否恢复',
    ],
  ),
  TroubleshootingEntry(
    title: 'SnowLuma 安装失败或反复重装',
    causes: <String>[
      '下载 SnowLuma / QQ 安装包时网络不通或加速代理失效',
      '设备存储空间不足',
    ],
    steps: <String>[
      '确认网络可访问 GitHub 或其加速镜像，稍后重试',
      '到「SnowLuma 管理目录」手动检查与安装',
    ],
    jump: TroubleshootingJump(label: '去 SnowLuma 管理目录', route: AppRoute.snowlumaManage),
  ),
  TroubleshootingEntry(
    title: '向导 / 实例安装失败',
    causes: <String>[
      '克隆仓库或下载依赖时网络超时',
      '所选镜像源临时不可用',
    ],
    steps: <String>[
      '检查网络后重试安装（支持断点续装）',
      '更换镜像源（GitHub 加速）后重试',
    ],
  ),
  TroubleshootingEntry(
    title: '锁屏后 bot 被杀',
    causes: <String>['系统省电策略清理了后台进程'],
    steps: <String>[
      '开启「锁屏保活」，并按保活体检页的指引把 App 加入电池白名单',
    ],
    jump: TroubleshootingJump(label: '去保活体检', route: AppRoute.keepaliveStatus),
  ),
  TroubleshootingEntry(
    title: '点 WebUI 提示无法打开系统浏览器',
    causes: <String>['设备没有可用的浏览器应用'],
    steps: <String>[
      '安装或启用任一浏览器后重试',
      '手动复制地址到浏览器打开',
    ],
  ),
  TroubleshootingEntry(
    title: '虚拟屏幕黑屏 / 截不到图',
    causes: <String>[
      '虚拟显示（Xvfb）尚未就绪',
      '上次会话残留显示锁',
    ],
    steps: <String>[
      '启动后 15 秒内属正常，稍等即可',
      '持续黑屏：重启 SnowLuma',
    ],
  ),
];
