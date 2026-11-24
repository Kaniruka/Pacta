import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_grouped_list.dart';

/// 应用版本号：与 `pubspec.yaml` 的 `version:` 保持同一个值。
///
/// 仓库没有引入 `package_info_plus`，客户端也不从平台通道读取版本；这里只有
/// 一个常量，改版本时与 `pubspec.yaml` 一起改，界面不再各写一套。
const String pactaAppVersion = '0.3.1+4';

/// 方法论出处：用户提供的知乎原回答。
const String pactaTheorySourceUrl =
    'https://www.zhihu.com/question/19888447/answer/1930799480401293785';

/// 开源仓库主页。
const String pactaGithubRepoUrl = 'https://github.com/Kaniruka/Pacta';

/// 外部链接打开器签名；默认交给系统外部浏览器，测试可注入替身。
typedef PactaExternalUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunchExternalUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// 《关于 Pacta》：版本、方法论出处与字体／开源许可。
///
/// 只做三件事：报出当前版本、把理论出处与项目主页摆出来并支持点击直达浏览器、
/// 给出字体与开源许可入口。页面没有设置项，也没有次级动作，因此全是静态内容：
/// 品牌卡 + 两个 [PactaSectionHeader] 分组。
class AboutPactaPage extends StatelessWidget {
  const AboutPactaPage({
    super.key,
    this.launchExternalUrl = _defaultLaunchExternalUrl,
  });

  final PactaExternalUrlLauncher launchExternalUrl;

  Future<void> _openLink(BuildContext context, String url) async {
    var launched = false;
    try {
      launched = await launchExternalUrl(Uri.parse(url));
    } catch (_) {
      launched = false;
    }
    if (launched || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('无法打开浏览器，请检查系统默认浏览器设置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于 Pacta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: PactaSpacing.pageInsets(context, top: PactaSpacing.sm),
            children: [
              _brandCard(context),
              PactaSectionHeader(title: '理论出处'),
              PactaGroupedList(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PactaSpacing.lg,
                      PactaSpacing.lg,
                      PactaSpacing.lg,
                      PactaSpacing.lg,
                    ),
                    child: Text(
                      'Pacta 把「聚焦」当作可以训练的动作：先确定此刻唯一要做的事，'
                      '再用可回看的记录替代意志力。方法论灵感来自下面的知乎原回答。',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  PactaSettingsTile(
                    tileKey: const ValueKey('about-theory-source-entry'),
                    leadingIcon: Icons.menu_book_outlined,
                    title: '知乎原回答',
                    subtitle: pactaTheorySourceUrl,
                    trailing: Icon(
                      Icons.open_in_new_outlined,
                      size: PactaIconSizes.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _openLink(context, pactaTheorySourceUrl),
                  ),
                ],
              ),
              PactaSectionHeader(title: '字体与开源许可'),
              PactaGroupedList(
                children: [
                  PactaSettingsTile(
                    tileKey: const ValueKey('about-github-repo-entry'),
                    leadingIcon: Icons.code_outlined,
                    title: 'GitHub 项目主页',
                    subtitle: pactaGithubRepoUrl,
                    trailing: Icon(
                      Icons.open_in_new_outlined,
                      size: PactaIconSizes.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _openLink(context, pactaGithubRepoUrl),
                  ),
                  const PactaSettingsTile(
                    leadingIcon: Icons.text_fields_outlined,
                    title: '小米 MiSans 字体',
                    subtitle:
                        '界面与正文统一使用 MiSans；字体版权归小米所有，'
                        '按小米官方的 MiSans 字体许可使用。',
                    showChevron: false,
                  ),
                  PactaSettingsTile(
                    tileKey: const ValueKey('about-license-entry'),
                    leadingIcon: Icons.article_outlined,
                    title: '开放源代码许可',
                    subtitle: 'Flutter 与各依赖包的许可全文',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Pacta',
                      applicationVersion: pactaAppVersion,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PactaSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// 品牌卡：锚点徽标 + 应用名 + 版本胶囊，三者一条阅读线。
  Widget _brandCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PactaSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.anchor_rounded,
                size: PactaIconSizes.hero,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: PactaSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pacta', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: PactaSpacing.xxs),
                  Text(
                    '聚焦与自我调节的记录工具',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PactaSpacing.md),
            _versionPill(context),
          ],
        ),
      ),
    );
  }

  /// 版本胶囊：一眼可读的 `v0.3.1+4`，与开源许可页显示的版本同一个常量。
  Widget _versionPill(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const ValueKey('about-version-pill'),
      padding: const EdgeInsets.symmetric(
        horizontal: PactaSpacing.md,
        vertical: PactaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'v$pactaAppVersion',
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: PactaFonts.medium,
        ),
      ),
    );
  }
}
