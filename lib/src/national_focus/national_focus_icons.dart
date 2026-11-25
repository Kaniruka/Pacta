import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';

/// 国策卡自定义图标的四套离线矢量图标库。
///
/// 每套图标都来自开源字体包，随 App 一起打包，不联网、不缓存远端资源：
/// - 默认（Lucide）：lucide_icons_flutter，前缀 'lucide:'
/// - Tabler：flutter_tabler_icons，前缀 'tabler:'
/// - Material：Flutter 内置 Icons，前缀 'material:'
/// - Cupertino：Flutter 内置 CupertinoIcons，前缀 'cupertino:'
///
/// 键是对图标常量的 kebab-case 投影（如 'lucide:book-open'），存储的是这段
/// 短字符串而不是字体码位，跨端同步与换包升级都不会把图标读成私用区豆腐块。
const String nationalFocusIconPrefixLucide = 'lucide:';
const String nationalFocusIconPrefixTabler = 'tabler:';
const String nationalFocusIconPrefixMaterial = 'material:';
const String nationalFocusIconPrefixCupertino = 'cupertino:';

/// 未设图标时的默认图标：Lucide 灯泡。
const IconData nationalFocusDefaultIcon = LucideIcons.lightbulb;

/// 「恢复默认」在 [showNationalFocusIconPicker] 的返回值里用空串表达。
const String nationalFocusIconResetSelection = '';

/// 一枚可选图标：稳定键、中文标签与真实 [IconData]。
class NationalFocusIconOption {
  const NationalFocusIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

/// 一套图标库：分页标题、键前缀与全部选项。
class NationalFocusIconSet {
  const NationalFocusIconSet({
    required this.id,
    required this.title,
    required this.prefix,
    required this.options,
  });

  final String id;
  final String title;
  final String prefix;
  final List<NationalFocusIconOption> options;
}

/// 四套分页图标库；顺序即选择器的页签顺序。
const List<NationalFocusIconSet> nationalFocusIconSets = [
  NationalFocusIconSet(
    id: 'lucide',
    title: '默认',
    prefix: nationalFocusIconPrefixLucide,
    options: [
      NationalFocusIconOption(
        key: 'lucide:book-open',
        label: '阅读',
        icon: LucideIcons.bookOpen,
      ),
      NationalFocusIconOption(
        key: 'lucide:sunrise',
        label: '晨间',
        icon: LucideIcons.sunrise,
      ),
      NationalFocusIconOption(
        key: 'lucide:pen-line',
        label: '写作',
        icon: LucideIcons.penLine,
      ),
      NationalFocusIconOption(
        key: 'lucide:notebook-pen',
        label: '日记',
        icon: LucideIcons.notebookPen,
      ),
      NationalFocusIconOption(
        key: 'lucide:calendar-check',
        label: '计划',
        icon: LucideIcons.calendarCheck,
      ),
      NationalFocusIconOption(
        key: 'lucide:list-checks',
        label: '待办',
        icon: LucideIcons.listChecks,
      ),
      NationalFocusIconOption(
        key: 'lucide:target',
        label: '专注',
        icon: LucideIcons.target,
      ),
      NationalFocusIconOption(
        key: 'lucide:graduation-cap',
        label: '学习',
        icon: LucideIcons.graduationCap,
      ),
      NationalFocusIconOption(
        key: 'lucide:brain',
        label: '记忆',
        icon: LucideIcons.brain,
      ),
      NationalFocusIconOption(
        key: 'lucide:languages',
        label: '语言',
        icon: LucideIcons.languages,
      ),
      NationalFocusIconOption(
        key: 'lucide:code-xml',
        label: '编程',
        icon: LucideIcons.codeXml,
      ),
      NationalFocusIconOption(
        key: 'lucide:calculator',
        label: '计算',
        icon: LucideIcons.calculator,
      ),
      NationalFocusIconOption(
        key: 'lucide:flask-conical',
        label: '实验',
        icon: LucideIcons.flaskConical,
      ),
      NationalFocusIconOption(
        key: 'lucide:eye',
        label: '观察',
        icon: LucideIcons.eye,
      ),
      NationalFocusIconOption(
        key: 'lucide:dumbbell',
        label: '力量',
        icon: LucideIcons.dumbbell,
      ),
      NationalFocusIconOption(
        key: 'lucide:footprints',
        label: '跑步',
        icon: LucideIcons.footprints,
      ),
      NationalFocusIconOption(
        key: 'lucide:waves',
        label: '游泳',
        icon: LucideIcons.waves,
      ),
      NationalFocusIconOption(
        key: 'lucide:person-standing',
        label: '站立',
        icon: LucideIcons.personStanding,
      ),
      NationalFocusIconOption(
        key: 'lucide:heart-pulse',
        label: '健康',
        icon: LucideIcons.heartPulse,
      ),
      NationalFocusIconOption(
        key: 'lucide:moon',
        label: '睡眠',
        icon: LucideIcons.moon,
      ),
      NationalFocusIconOption(
        key: 'lucide:alarm-clock',
        label: '起床',
        icon: LucideIcons.alarmClock,
      ),
      NationalFocusIconOption(
        key: 'lucide:droplet',
        label: '喝水',
        icon: LucideIcons.droplet,
      ),
      NationalFocusIconOption(
        key: 'lucide:coffee',
        label: '咖啡',
        icon: LucideIcons.coffee,
      ),
      NationalFocusIconOption(
        key: 'lucide:salad',
        label: '饮食',
        icon: LucideIcons.salad,
      ),
      NationalFocusIconOption(
        key: 'lucide:chef-hat',
        label: '烹饪',
        icon: LucideIcons.chefHat,
      ),
      NationalFocusIconOption(
        key: 'lucide:sparkles',
        label: '整理',
        icon: LucideIcons.sparkles,
      ),
      NationalFocusIconOption(
        key: 'lucide:spray-can',
        label: '清洁',
        icon: LucideIcons.sprayCan,
      ),
      NationalFocusIconOption(
        key: 'lucide:washing-machine',
        label: '洗衣',
        icon: LucideIcons.washingMachine,
      ),
      NationalFocusIconOption(
        key: 'lucide:home',
        label: '家务',
        icon: LucideIcons.home,
      ),
      NationalFocusIconOption(
        key: 'lucide:sprout',
        label: '植物',
        icon: LucideIcons.sprout,
      ),
      NationalFocusIconOption(
        key: 'lucide:sun',
        label: '阳光',
        icon: LucideIcons.sun,
      ),
      NationalFocusIconOption(
        key: 'lucide:wind',
        label: '呼吸',
        icon: LucideIcons.wind,
      ),
      NationalFocusIconOption(
        key: 'lucide:clipboard-check',
        label: '打卡',
        icon: LucideIcons.clipboardCheck,
      ),
      NationalFocusIconOption(
        key: 'lucide:refresh-ccw',
        label: '复盘',
        icon: LucideIcons.refreshCcw,
      ),
      NationalFocusIconOption(
        key: 'lucide:flag',
        label: '目标',
        icon: LucideIcons.flag,
      ),
      NationalFocusIconOption(
        key: 'lucide:flame',
        label: '坚持',
        icon: LucideIcons.flame,
      ),
      NationalFocusIconOption(
        key: 'lucide:gift',
        label: '奖励',
        icon: LucideIcons.gift,
      ),
      NationalFocusIconOption(
        key: 'lucide:piggy-bank',
        label: '储蓄',
        icon: LucideIcons.piggyBank,
      ),
      NationalFocusIconOption(
        key: 'lucide:wallet',
        label: '理财',
        icon: LucideIcons.wallet,
      ),
      NationalFocusIconOption(
        key: 'lucide:phone-off',
        label: '远离手机',
        icon: LucideIcons.phoneOff,
      ),
      NationalFocusIconOption(
        key: 'lucide:cigarette-off',
        label: '戒烟',
        icon: LucideIcons.cigaretteOff,
      ),
      NationalFocusIconOption(
        key: 'lucide:candy-off',
        label: '少糖',
        icon: LucideIcons.candyOff,
      ),
      NationalFocusIconOption(
        key: 'lucide:users',
        label: '家人',
        icon: LucideIcons.users,
      ),
      NationalFocusIconOption(
        key: 'lucide:message-circle',
        label: '沟通',
        icon: LucideIcons.messageCircle,
      ),
      NationalFocusIconOption(
        key: 'lucide:heart-handshake',
        label: '感恩',
        icon: LucideIcons.heartHandshake,
      ),
      NationalFocusIconOption(
        key: 'lucide:clock',
        label: '时间',
        icon: LucideIcons.clock,
      ),
      NationalFocusIconOption(
        key: 'lucide:music',
        label: '音乐',
        icon: LucideIcons.music,
      ),
      NationalFocusIconOption(
        key: 'lucide:palette',
        label: '绘画',
        icon: LucideIcons.palette,
      ),
      NationalFocusIconOption(
        key: 'lucide:film',
        label: '电影',
        icon: LucideIcons.film,
      ),
      NationalFocusIconOption(
        key: 'lucide:trees',
        label: '自然',
        icon: LucideIcons.trees,
      ),
      NationalFocusIconOption(
        key: 'lucide:plane',
        label: '旅行',
        icon: LucideIcons.plane,
      ),
      NationalFocusIconOption(
        key: 'lucide:bell',
        label: '提醒',
        icon: LucideIcons.bell,
      ),
      NationalFocusIconOption(
        key: 'lucide:lightbulb',
        label: '灵感',
        icon: LucideIcons.lightbulb,
      ),
    ],
  ),
  NationalFocusIconSet(
    id: 'tabler',
    title: 'Tabler',
    prefix: nationalFocusIconPrefixTabler,
    options: [
      NationalFocusIconOption(
        key: 'tabler:book',
        label: '阅读',
        icon: TablerIcons.book,
      ),
      NationalFocusIconOption(
        key: 'tabler:sunrise',
        label: '晨间',
        icon: TablerIcons.sunrise,
      ),
      NationalFocusIconOption(
        key: 'tabler:pencil',
        label: '写作',
        icon: TablerIcons.pencil,
      ),
      NationalFocusIconOption(
        key: 'tabler:notebook',
        label: '日记',
        icon: TablerIcons.notebook,
      ),
      NationalFocusIconOption(
        key: 'tabler:calendar-check',
        label: '计划',
        icon: TablerIcons.calendar_check,
      ),
      NationalFocusIconOption(
        key: 'tabler:list-check',
        label: '待办',
        icon: TablerIcons.list_check,
      ),
      NationalFocusIconOption(
        key: 'tabler:target',
        label: '专注',
        icon: TablerIcons.target,
      ),
      NationalFocusIconOption(
        key: 'tabler:school',
        label: '学习',
        icon: TablerIcons.school,
      ),
      NationalFocusIconOption(
        key: 'tabler:brain',
        label: '记忆',
        icon: TablerIcons.brain,
      ),
      NationalFocusIconOption(
        key: 'tabler:language',
        label: '语言',
        icon: TablerIcons.language,
      ),
      NationalFocusIconOption(
        key: 'tabler:code',
        label: '编程',
        icon: TablerIcons.code,
      ),
      NationalFocusIconOption(
        key: 'tabler:calculator',
        label: '计算',
        icon: TablerIcons.calculator,
      ),
      NationalFocusIconOption(
        key: 'tabler:flask',
        label: '实验',
        icon: TablerIcons.flask,
      ),
      NationalFocusIconOption(
        key: 'tabler:eye',
        label: '观察',
        icon: TablerIcons.eye,
      ),
      NationalFocusIconOption(
        key: 'tabler:barbell',
        label: '力量',
        icon: TablerIcons.barbell,
      ),
      NationalFocusIconOption(
        key: 'tabler:run',
        label: '跑步',
        icon: TablerIcons.run,
      ),
      NationalFocusIconOption(
        key: 'tabler:swimming',
        label: '游泳',
        icon: TablerIcons.swimming,
      ),
      NationalFocusIconOption(
        key: 'tabler:yoga',
        label: '瑜伽',
        icon: TablerIcons.yoga,
      ),
      NationalFocusIconOption(
        key: 'tabler:heart-rate-monitor',
        label: '健康',
        icon: TablerIcons.heart_rate_monitor,
      ),
      NationalFocusIconOption(
        key: 'tabler:moon',
        label: '睡眠',
        icon: TablerIcons.moon,
      ),
      NationalFocusIconOption(
        key: 'tabler:alarm',
        label: '起床',
        icon: TablerIcons.alarm,
      ),
      NationalFocusIconOption(
        key: 'tabler:droplet',
        label: '喝水',
        icon: TablerIcons.droplet,
      ),
      NationalFocusIconOption(
        key: 'tabler:coffee',
        label: '咖啡',
        icon: TablerIcons.coffee,
      ),
      NationalFocusIconOption(
        key: 'tabler:salad',
        label: '饮食',
        icon: TablerIcons.salad,
      ),
      NationalFocusIconOption(
        key: 'tabler:chef-hat',
        label: '烹饪',
        icon: TablerIcons.chef_hat,
      ),
      NationalFocusIconOption(
        key: 'tabler:sparkles',
        label: '整理',
        icon: TablerIcons.sparkles,
      ),
      NationalFocusIconOption(
        key: 'tabler:spray',
        label: '清洁',
        icon: TablerIcons.spray,
      ),
      NationalFocusIconOption(
        key: 'tabler:wash-machine',
        label: '洗衣',
        icon: TablerIcons.wash_machine,
      ),
      NationalFocusIconOption(
        key: 'tabler:home',
        label: '家务',
        icon: TablerIcons.home,
      ),
      NationalFocusIconOption(
        key: 'tabler:plant',
        label: '植物',
        icon: TablerIcons.plant,
      ),
      NationalFocusIconOption(
        key: 'tabler:sun',
        label: '阳光',
        icon: TablerIcons.sun,
      ),
      NationalFocusIconOption(
        key: 'tabler:wind',
        label: '呼吸',
        icon: TablerIcons.wind,
      ),
      NationalFocusIconOption(
        key: 'tabler:clipboard-check',
        label: '打卡',
        icon: TablerIcons.clipboard_check,
      ),
      NationalFocusIconOption(
        key: 'tabler:refresh',
        label: '复盘',
        icon: TablerIcons.refresh,
      ),
      NationalFocusIconOption(
        key: 'tabler:flag',
        label: '目标',
        icon: TablerIcons.flag,
      ),
      NationalFocusIconOption(
        key: 'tabler:flame',
        label: '坚持',
        icon: TablerIcons.flame,
      ),
      NationalFocusIconOption(
        key: 'tabler:gift',
        label: '奖励',
        icon: TablerIcons.gift,
      ),
      NationalFocusIconOption(
        key: 'tabler:pig-money',
        label: '储蓄',
        icon: TablerIcons.pig_money,
      ),
      NationalFocusIconOption(
        key: 'tabler:wallet',
        label: '理财',
        icon: TablerIcons.wallet,
      ),
      NationalFocusIconOption(
        key: 'tabler:device-mobile-off',
        label: '远离手机',
        icon: TablerIcons.device_mobile_off,
      ),
      NationalFocusIconOption(
        key: 'tabler:smoking-no',
        label: '戒烟',
        icon: TablerIcons.smoking_no,
      ),
      NationalFocusIconOption(
        key: 'tabler:candy-off',
        label: '少糖',
        icon: TablerIcons.candy_off,
      ),
      NationalFocusIconOption(
        key: 'tabler:users',
        label: '家人',
        icon: TablerIcons.users,
      ),
      NationalFocusIconOption(
        key: 'tabler:message-circle',
        label: '沟通',
        icon: TablerIcons.message_circle,
      ),
      NationalFocusIconOption(
        key: 'tabler:heart-handshake',
        label: '感恩',
        icon: TablerIcons.heart_handshake,
      ),
      NationalFocusIconOption(
        key: 'tabler:clock',
        label: '时间',
        icon: TablerIcons.clock,
      ),
      NationalFocusIconOption(
        key: 'tabler:music',
        label: '音乐',
        icon: TablerIcons.music,
      ),
      NationalFocusIconOption(
        key: 'tabler:palette',
        label: '绘画',
        icon: TablerIcons.palette,
      ),
      NationalFocusIconOption(
        key: 'tabler:movie',
        label: '电影',
        icon: TablerIcons.movie,
      ),
      NationalFocusIconOption(
        key: 'tabler:tree',
        label: '自然',
        icon: TablerIcons.tree,
      ),
      NationalFocusIconOption(
        key: 'tabler:plane',
        label: '旅行',
        icon: TablerIcons.plane,
      ),
      NationalFocusIconOption(
        key: 'tabler:bell',
        label: '提醒',
        icon: TablerIcons.bell,
      ),
    ],
  ),
  NationalFocusIconSet(
    id: 'material',
    title: 'Material',
    prefix: nationalFocusIconPrefixMaterial,
    options: [
      NationalFocusIconOption(
        key: 'material:menu-book',
        label: '阅读',
        icon: Icons.menu_book,
      ),
      NationalFocusIconOption(
        key: 'material:wb-twilight',
        label: '晨间',
        icon: Icons.wb_twilight,
      ),
      NationalFocusIconOption(
        key: 'material:edit-note',
        label: '写作',
        icon: Icons.edit_note,
      ),
      NationalFocusIconOption(
        key: 'material:auto-stories',
        label: '日记',
        icon: Icons.auto_stories,
      ),
      NationalFocusIconOption(
        key: 'material:event-available',
        label: '计划',
        icon: Icons.event_available,
      ),
      NationalFocusIconOption(
        key: 'material:checklist',
        label: '待办',
        icon: Icons.checklist,
      ),
      NationalFocusIconOption(
        key: 'material:gps-fixed',
        label: '专注',
        icon: Icons.gps_fixed,
      ),
      NationalFocusIconOption(
        key: 'material:school',
        label: '学习',
        icon: Icons.school,
      ),
      NationalFocusIconOption(
        key: 'material:psychology',
        label: '记忆',
        icon: Icons.psychology,
      ),
      NationalFocusIconOption(
        key: 'material:translate',
        label: '语言',
        icon: Icons.translate,
      ),
      NationalFocusIconOption(
        key: 'material:code',
        label: '编程',
        icon: Icons.code,
      ),
      NationalFocusIconOption(
        key: 'material:calculate',
        label: '计算',
        icon: Icons.calculate,
      ),
      NationalFocusIconOption(
        key: 'material:science',
        label: '实验',
        icon: Icons.science,
      ),
      NationalFocusIconOption(
        key: 'material:visibility',
        label: '观察',
        icon: Icons.visibility,
      ),
      NationalFocusIconOption(
        key: 'material:fitness-center',
        label: '健身',
        icon: Icons.fitness_center,
      ),
      NationalFocusIconOption(
        key: 'material:directions-run',
        label: '跑步',
        icon: Icons.directions_run,
      ),
      NationalFocusIconOption(
        key: 'material:pool',
        label: '游泳',
        icon: Icons.pool,
      ),
      NationalFocusIconOption(
        key: 'material:self-improvement',
        label: '冥想',
        icon: Icons.self_improvement,
      ),
      NationalFocusIconOption(
        key: 'material:monitor-heart',
        label: '健康',
        icon: Icons.monitor_heart,
      ),
      NationalFocusIconOption(
        key: 'material:bedtime',
        label: '睡眠',
        icon: Icons.bedtime,
      ),
      NationalFocusIconOption(
        key: 'material:alarm',
        label: '起床',
        icon: Icons.alarm,
      ),
      NationalFocusIconOption(
        key: 'material:water-drop',
        label: '喝水',
        icon: Icons.water_drop,
      ),
      NationalFocusIconOption(
        key: 'material:coffee',
        label: '咖啡',
        icon: Icons.coffee,
      ),
      NationalFocusIconOption(
        key: 'material:lunch-dining',
        label: '饮食',
        icon: Icons.lunch_dining,
      ),
      NationalFocusIconOption(
        key: 'material:soup-kitchen',
        label: '烹饪',
        icon: Icons.soup_kitchen,
      ),
      NationalFocusIconOption(
        key: 'material:auto-awesome',
        label: '整理',
        icon: Icons.auto_awesome,
      ),
      NationalFocusIconOption(
        key: 'material:cleaning-services',
        label: '清洁',
        icon: Icons.cleaning_services,
      ),
      NationalFocusIconOption(
        key: 'material:local-laundry-service',
        label: '洗衣',
        icon: Icons.local_laundry_service,
      ),
      NationalFocusIconOption(
        key: 'material:home',
        label: '家务',
        icon: Icons.home,
      ),
      NationalFocusIconOption(
        key: 'material:eco',
        label: '植物',
        icon: Icons.eco,
      ),
      NationalFocusIconOption(
        key: 'material:wb-sunny',
        label: '阳光',
        icon: Icons.wb_sunny,
      ),
      NationalFocusIconOption(
        key: 'material:air',
        label: '呼吸',
        icon: Icons.air,
      ),
      NationalFocusIconOption(
        key: 'material:assignment-turned-in',
        label: '打卡',
        icon: Icons.assignment_turned_in,
      ),
      NationalFocusIconOption(
        key: 'material:replay',
        label: '复盘',
        icon: Icons.replay,
      ),
      NationalFocusIconOption(
        key: 'material:flag',
        label: '目标',
        icon: Icons.flag,
      ),
      NationalFocusIconOption(
        key: 'material:local-fire-department',
        label: '坚持',
        icon: Icons.local_fire_department,
      ),
      NationalFocusIconOption(
        key: 'material:card-giftcard',
        label: '奖励',
        icon: Icons.card_giftcard,
      ),
      NationalFocusIconOption(
        key: 'material:savings',
        label: '储蓄',
        icon: Icons.savings,
      ),
      NationalFocusIconOption(
        key: 'material:account-balance-wallet',
        label: '理财',
        icon: Icons.account_balance_wallet,
      ),
      NationalFocusIconOption(
        key: 'material:phone-disabled',
        label: '远离手机',
        icon: Icons.phone_disabled,
      ),
      NationalFocusIconOption(
        key: 'material:smoke-free',
        label: '戒烟',
        icon: Icons.smoke_free,
      ),
      NationalFocusIconOption(
        key: 'material:no-food',
        label: '少糖',
        icon: Icons.no_food,
      ),
      NationalFocusIconOption(
        key: 'material:family-restroom',
        label: '家人',
        icon: Icons.family_restroom,
      ),
      NationalFocusIconOption(
        key: 'material:chat-bubble',
        label: '沟通',
        icon: Icons.chat_bubble,
      ),
      NationalFocusIconOption(
        key: 'material:volunteer-activism',
        label: '公益',
        icon: Icons.volunteer_activism,
      ),
      NationalFocusIconOption(
        key: 'material:schedule',
        label: '时间',
        icon: Icons.schedule,
      ),
      NationalFocusIconOption(
        key: 'material:music-note',
        label: '音乐',
        icon: Icons.music_note,
      ),
      NationalFocusIconOption(
        key: 'material:palette',
        label: '绘画',
        icon: Icons.palette,
      ),
      NationalFocusIconOption(
        key: 'material:movie',
        label: '电影',
        icon: Icons.movie,
      ),
      NationalFocusIconOption(
        key: 'material:park',
        label: '自然',
        icon: Icons.park,
      ),
      NationalFocusIconOption(
        key: 'material:flight',
        label: '旅行',
        icon: Icons.flight,
      ),
      NationalFocusIconOption(
        key: 'material:notifications',
        label: '提醒',
        icon: Icons.notifications,
      ),
      NationalFocusIconOption(
        key: 'material:lightbulb',
        label: '灵感',
        icon: Icons.lightbulb,
      ),
    ],
  ),
  NationalFocusIconSet(
    id: 'cupertino',
    title: 'Cupertino',
    prefix: nationalFocusIconPrefixCupertino,
    options: [
      NationalFocusIconOption(
        key: 'cupertino:book',
        label: '阅读',
        icon: CupertinoIcons.book,
      ),
      NationalFocusIconOption(
        key: 'cupertino:sunrise',
        label: '晨间',
        icon: CupertinoIcons.sunrise,
      ),
      NationalFocusIconOption(
        key: 'cupertino:pencil',
        label: '写作',
        icon: CupertinoIcons.pencil,
      ),
      NationalFocusIconOption(
        key: 'cupertino:square-pencil',
        label: '日记',
        icon: CupertinoIcons.square_pencil,
      ),
      NationalFocusIconOption(
        key: 'cupertino:calendar',
        label: '计划',
        icon: CupertinoIcons.calendar,
      ),
      NationalFocusIconOption(
        key: 'cupertino:list-bullet',
        label: '待办',
        icon: CupertinoIcons.list_bullet,
      ),
      NationalFocusIconOption(
        key: 'cupertino:scope',
        label: '专注',
        icon: CupertinoIcons.scope,
      ),
      NationalFocusIconOption(
        key: 'cupertino:book-solid',
        label: '学习',
        icon: CupertinoIcons.book_solid,
      ),
      NationalFocusIconOption(
        key: 'cupertino:lightbulb',
        label: '灵感',
        icon: CupertinoIcons.lightbulb,
      ),
      NationalFocusIconOption(
        key: 'cupertino:textformat',
        label: '语言',
        icon: CupertinoIcons.textformat,
      ),
      NationalFocusIconOption(
        key: 'cupertino:chevron-left-slash-chevron-right',
        label: '编程',
        icon: CupertinoIcons.chevron_left_slash_chevron_right,
      ),
      NationalFocusIconOption(
        key: 'cupertino:number',
        label: '计算',
        icon: CupertinoIcons.number,
      ),
      NationalFocusIconOption(
        key: 'cupertino:lab-flask',
        label: '实验',
        icon: CupertinoIcons.lab_flask,
      ),
      NationalFocusIconOption(
        key: 'cupertino:eye',
        label: '观察',
        icon: CupertinoIcons.eye,
      ),
      NationalFocusIconOption(
        key: 'cupertino:sportscourt',
        label: '运动',
        icon: CupertinoIcons.sportscourt,
      ),
      NationalFocusIconOption(
        key: 'cupertino:bolt',
        label: '冲刺',
        icon: CupertinoIcons.bolt,
      ),
      NationalFocusIconOption(
        key: 'cupertino:drop',
        label: '喝水',
        icon: CupertinoIcons.drop,
      ),
      NationalFocusIconOption(
        key: 'cupertino:heart',
        label: '健康',
        icon: CupertinoIcons.heart,
      ),
      NationalFocusIconOption(
        key: 'cupertino:moon',
        label: '睡眠',
        icon: CupertinoIcons.moon,
      ),
      NationalFocusIconOption(
        key: 'cupertino:alarm',
        label: '起床',
        icon: CupertinoIcons.alarm,
      ),
      NationalFocusIconOption(
        key: 'cupertino:flame',
        label: '坚持',
        icon: CupertinoIcons.flame,
      ),
      NationalFocusIconOption(
        key: 'cupertino:sparkles',
        label: '整理',
        icon: CupertinoIcons.sparkles,
      ),
      NationalFocusIconOption(
        key: 'cupertino:wand-stars',
        label: '清洁',
        icon: CupertinoIcons.wand_stars,
      ),
      NationalFocusIconOption(
        key: 'cupertino:house',
        label: '家务',
        icon: CupertinoIcons.house,
      ),
      NationalFocusIconOption(
        key: 'cupertino:leaf-arrow-circlepath',
        label: '植物',
        icon: CupertinoIcons.leaf_arrow_circlepath,
      ),
      NationalFocusIconOption(
        key: 'cupertino:sun-max',
        label: '阳光',
        icon: CupertinoIcons.sun_max,
      ),
      NationalFocusIconOption(
        key: 'cupertino:wind',
        label: '呼吸',
        icon: CupertinoIcons.wind,
      ),
      NationalFocusIconOption(
        key: 'cupertino:doc-checkmark',
        label: '打卡',
        icon: CupertinoIcons.doc_checkmark,
      ),
      NationalFocusIconOption(
        key: 'cupertino:arrow-counterclockwise',
        label: '复盘',
        icon: CupertinoIcons.arrow_counterclockwise,
      ),
      NationalFocusIconOption(
        key: 'cupertino:flag',
        label: '目标',
        icon: CupertinoIcons.flag,
      ),
      NationalFocusIconOption(
        key: 'cupertino:gift',
        label: '奖励',
        icon: CupertinoIcons.gift,
      ),
      NationalFocusIconOption(
        key: 'cupertino:creditcard',
        label: '记账',
        icon: CupertinoIcons.creditcard,
      ),
      NationalFocusIconOption(
        key: 'cupertino:phone',
        label: '手机',
        icon: CupertinoIcons.phone,
      ),
      NationalFocusIconOption(
        key: 'cupertino:person-2',
        label: '家人',
        icon: CupertinoIcons.person_2,
      ),
      NationalFocusIconOption(
        key: 'cupertino:bubble-left',
        label: '沟通',
        icon: CupertinoIcons.bubble_left,
      ),
      NationalFocusIconOption(
        key: 'cupertino:hand-thumbsup',
        label: '鼓励',
        icon: CupertinoIcons.hand_thumbsup,
      ),
      NationalFocusIconOption(
        key: 'cupertino:clock',
        label: '时间',
        icon: CupertinoIcons.clock,
      ),
      NationalFocusIconOption(
        key: 'cupertino:music-note',
        label: '音乐',
        icon: CupertinoIcons.music_note,
      ),
      NationalFocusIconOption(
        key: 'cupertino:paintbrush',
        label: '绘画',
        icon: CupertinoIcons.paintbrush,
      ),
      NationalFocusIconOption(
        key: 'cupertino:film',
        label: '电影',
        icon: CupertinoIcons.film,
      ),
      NationalFocusIconOption(
        key: 'cupertino:tree',
        label: '自然',
        icon: CupertinoIcons.tree,
      ),
      NationalFocusIconOption(
        key: 'cupertino:airplane',
        label: '旅行',
        icon: CupertinoIcons.airplane,
      ),
      NationalFocusIconOption(
        key: 'cupertino:bell',
        label: '提醒',
        icon: CupertinoIcons.bell,
      ),
      NationalFocusIconOption(
        key: 'cupertino:bed-double',
        label: '休息',
        icon: CupertinoIcons.bed_double,
      ),
      NationalFocusIconOption(
        key: 'cupertino:star',
        label: '星星',
        icon: CupertinoIcons.star,
      ),
      NationalFocusIconOption(
        key: 'cupertino:headphones',
        label: '听书',
        icon: CupertinoIcons.headphones,
      ),
      NationalFocusIconOption(
        key: 'cupertino:device-laptop',
        label: '电脑',
        icon: CupertinoIcons.device_laptop,
      ),
      NationalFocusIconOption(
        key: 'cupertino:checkmark-circle',
        label: '完成',
        icon: CupertinoIcons.checkmark_circle,
      ),
      NationalFocusIconOption(
        key: 'cupertino:search',
        label: '检索',
        icon: CupertinoIcons.search,
      ),
      NationalFocusIconOption(
        key: 'cupertino:car',
        label: '通勤',
        icon: CupertinoIcons.car,
      ),
      NationalFocusIconOption(
        key: 'cupertino:bus',
        label: '公交',
        icon: CupertinoIcons.bus,
      ),
      NationalFocusIconOption(
        key: 'cupertino:book-fill',
        label: '精读',
        icon: CupertinoIcons.book_fill,
      ),
    ],
  ),
];

/// 全部选项的按键索引；未知键查不到，安全回落默认图标。
final Map<String, NationalFocusIconOption> nationalFocusIconOptionsByKey = {
  for (final set in nationalFocusIconSets)
    for (final option in set.options) option.key: option,
};

/// 解析图标键；空值、未知前缀或未知键一律返回 null。
NationalFocusIconOption? nationalFocusIconOption(String? iconKey) {
  final normalized = iconKey?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return nationalFocusIconOptionsByKey[normalized];
}

/// 渲染用图标：空值/未知键回落 [nationalFocusDefaultIcon]（Lucide 灯泡）。
IconData nationalFocusIconData(String? iconKey) =>
    nationalFocusIconOption(iconKey)?.icon ?? nationalFocusDefaultIcon;

/// 图标键对应的中文标签；未设图标时返回「默认」。
String nationalFocusIconLabel(String? iconKey) =>
    nationalFocusIconOption(iconKey)?.label ?? '默认';

/// 打开四套分页图标选择器。
///
/// 返回值：选中的图标键；点「恢复默认」返回
/// [nationalFocusIconResetSelection]（空串，调用方据此把 iconKey 置空）；
/// 直接关闭返回 null，表示不改变当前选择。
Future<String?> showNationalFocusIconPicker(
  BuildContext context, {
  String? selectedKey,
}) {
  final platform = Theme.of(context).platform;
  final useSheet =
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.fuchsia;
  final picker = _NationalFocusIconPicker(selectedKey: selectedKey);
  if (useSheet) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(height: height, child: picker),
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(PactaSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: SizedBox(width: 520, height: 520, child: picker),
      ),
    ),
  );
}

class _NationalFocusIconPicker extends StatefulWidget {
  const _NationalFocusIconPicker({required this.selectedKey});

  final String? selectedKey;

  @override
  State<_NationalFocusIconPicker> createState() =>
      _NationalFocusIconPickerState();
}

class _NationalFocusIconPickerState extends State<_NationalFocusIconPicker> {
  late final String? _selectedKey = widget.selectedKey;

  void _commit(String key) => Navigator.of(context).pop(key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DefaultTabController(
      length: nationalFocusIconSets.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PactaSpacing.lg,
              PactaSpacing.xs,
              PactaSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('选择图标', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  key: const ValueKey('national-focus-icon-reset'),
                  onPressed: () => _commit(nationalFocusIconResetSelection),
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ),
          TabBar(
            // 四套库的名字长短不一（默认 / Tabler / Material / Cupertino）：
            // 可滚动页签让窄屏也不把 Cupertino 截成省略号，宽屏仍能一次看全。
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: PactaSpacing.md,
            ),
            tabs: [
              for (final set in nationalFocusIconSets) Tab(text: set.title),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final set in nationalFocusIconSets)
                  _NationalFocusIconGrid(
                    set: set,
                    selectedKey: _selectedKey,
                    onSelect: _commit,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PactaSpacing.lg,
              PactaSpacing.xs,
              PactaSpacing.lg,
              PactaSpacing.sm,
            ),
            child: Text(
              '全部图标随 App 离线内置，不联网加载。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NationalFocusIconGrid extends StatelessWidget {
  const _NationalFocusIconGrid({
    required this.set,
    required this.selectedKey,
    required this.onSelect,
  });

  final NationalFocusIconSet set;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return GridView.builder(
      key: ValueKey('national-focus-icon-grid-${set.id}'),
      padding: const EdgeInsets.all(PactaSpacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 84,
        mainAxisExtent: 84,
        crossAxisSpacing: PactaSpacing.sm,
        mainAxisSpacing: PactaSpacing.sm,
      ),
      itemCount: set.options.length,
      itemBuilder: (context, index) {
        final option = set.options[index];
        final selected = option.key == selectedKey;
        return InkWell(
          key: ValueKey('national-focus-icon-${option.key}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelect(option.key),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? colors.primary : colors.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      option.icon,
                      size: PactaIconSizes.md,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    if (selected)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(
                          Icons.check_circle,
                          size: PactaIconSizes.micro,
                          color: colors.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: PactaSpacing.xxs),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
