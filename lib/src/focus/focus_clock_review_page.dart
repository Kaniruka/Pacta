import 'package:flutter/material.dart';

import 'focus_models.dart';
import 'focus_repository.dart';

/// User entry for clock-adjusted Focus Session intervals.
///
/// Deferring keeps the original wall-clock readings and the pending marker in
/// the synchronized Focus Session source. Resolving accepts the captured
/// monotonic estimate or retains only intervals whose duration is known.
class FocusClockReviewPage extends StatefulWidget {
  const FocusClockReviewPage({super.key, required this.repository});

  final FocusRepository repository;

  @override
  State<FocusClockReviewPage> createState() => _FocusClockReviewPageState();
}

class _FocusClockReviewPageState extends State<FocusClockReviewPage> {
  final Set<String> _busyCaseIds = {};

  Future<void> _defer(FocusClockReviewCase reviewCase) async {
    await _run(reviewCase, () async {
      await widget.repository.deferClockReviewCase(reviewCase.id);
      _showMessage('已暂缓核对；原始时间证据仍会保留并同步。');
    });
  }

  Future<void> _resolve(
    FocusClockReviewCase reviewCase,
    FocusClockReviewDecision decision,
  ) async {
    await _run(reviewCase, () async {
      await widget.repository.resolveClockReviewCase(
        caseId: reviewCase.id,
        decision: decision,
      );
      _showMessage('已更新专注统计和记录顺序。');
    });
  }

  Future<void> _run(
    FocusClockReviewCase reviewCase,
    Future<void> Function() action,
  ) async {
    if (_busyCaseIds.contains(reviewCase.id)) return;
    setState(() => _busyCaseIds.add(reviewCase.id));
    try {
      await action();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busyCaseIds.remove(reviewCase.id));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备时间核对')),
    body: StreamBuilder<List<FocusClockReviewCase>>(
      stream: widget.repository.watchClockReviewCases(),
      initialData: const [],
      builder: (context, snapshot) {
        final cases = snapshot.data ?? const <FocusClockReviewCase>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (cases.isEmpty) {
          return const Center(child: Text('当前没有待核对的设备时间记录'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: cases.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _reviewCard(context, cases[index]),
        );
      },
    ),
  );

  Widget _reviewCard(BuildContext context, FocusClockReviewCase reviewCase) {
    final interval = reviewCase.interval;
    final direction = switch (reviewCase.direction) {
      FocusClockChangeDirection.forward => '前跳',
      FocusClockChangeDirection.backward => '后跳',
    };
    final uncertainSeconds = reviewCase.uncertainSeconds;
    final busy = _busyCaseIds.contains(reviewCase.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '设备时钟$direction',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (reviewCase.isDeferred) const Chip(label: Text('已暂缓')),
              ],
            ),
            const SizedBox(height: 8),
            Text('专注记录：${reviewCase.sessionId}'),
            const SizedBox(height: 4),
            Text(
              '原始设备时间：${_formatDateTime(interval.observedStartedAt ?? interval.startedAt)}'
              ' → ${_formatDateTime(interval.observedEndedAt ?? interval.endedAt)}',
            ),
            const SizedBox(height: 4),
            Text('跳变前已确认 ${_formatDuration(reviewCase.reliableSeconds)}'),
            Text(
              uncertainSeconds == null
                  ? '跳变期间没有可比较的连续计时证据，暂不计入这段时间。'
                  : '跳变期间连续计时约 ${_formatDuration(uncertainSeconds)}；原始时间仍待核对。',
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (!busy)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _defer(reviewCase),
                    icon: const Icon(Icons.snooze),
                    label: const Text('稍后处理'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _resolve(
                      reviewCase,
                      reviewCase.canAcceptMonotonicEstimate
                          ? FocusClockReviewDecision.acceptMonotonicEstimate
                          : FocusClockReviewDecision.keepReliableTimeOnly,
                    ),
                    child: Text(
                      reviewCase.canAcceptMonotonicEstimate
                          ? '采用连续计时并核对顺序'
                          : '仅保留已确认时间',
                    ),
                  ),
                  if (reviewCase.canAcceptMonotonicEstimate)
                    TextButton(
                      onPressed: () => _resolve(
                        reviewCase,
                        FocusClockReviewDecision.keepReliableTimeOnly,
                      ),
                      child: const Text('排除这段不确定时间'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '未记录';
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}

String _formatDuration(int seconds) {
  final clamped = seconds.clamp(0, 1 << 31);
  final minutes = clamped ~/ 60;
  final remainingSeconds = clamped % 60;
  if (minutes == 0) return '$remainingSeconds秒';
  if (remainingSeconds == 0) return '$minutes分';
  return '$minutes分$remainingSeconds秒';
}
