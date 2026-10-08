class ClockGuard {
  ClockGuard({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final Stopwatch _elapsed = Stopwatch()..start();
  Duration offset = Duration.zero;
  DateTime? _wallAnchor;
  Duration _elapsedAnchor = Duration.zero;
  bool suspect = false;

  DateTime get correctedNow {
    final wall = _now().toUtc();
    final anchor = _wallAnchor;
    if (anchor != null) {
      final expected = anchor.add(_elapsed.elapsed - _elapsedAnchor);
      if (wall.difference(expected).abs() > const Duration(minutes: 10) ||
          wall.isBefore(anchor.subtract(const Duration(seconds: 2)))) {
        suspect = true;
      }
    }
    return wall.add(offset);
  }

  void restore(Duration savedOffset, DateTime lastWall) {
    offset = savedOffset;
    _wallAnchor = _now().toUtc();
    _elapsedAnchor = _elapsed.elapsed;
    if (_wallAnchor!.isBefore(lastWall.subtract(const Duration(minutes: 10)))) {
      suspect = true;
    }
  }

  void calibrate(DateTime server, DateTime requestStart, DateTime requestEnd) {
    final midpoint = requestStart.add(requestEnd.difference(requestStart) ~/ 2);
    offset = server.difference(midpoint);
    _wallAnchor = requestEnd.toUtc();
    _elapsedAnchor = _elapsed.elapsed;
    suspect = offset.abs() > const Duration(minutes: 10);
  }
}
