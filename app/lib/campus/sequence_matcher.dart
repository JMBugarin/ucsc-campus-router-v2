/// How alike two strings are, from 0 to 1, by the same rule as Python's `difflib.SequenceMatcher.ratio`
/// (repeated longest common blocks), so typo matching scores the way the data was tuned.
double similarity(String a, String b) {
  final total = a.length + b.length;
  if (total == 0) return 1;
  return 2 * _matched(a, 0, a.length, b, 0, b.length) / total;
}

int _matched(String a, int alo, int ahi, String b, int blo, int bhi) {
  if (alo >= ahi || blo >= bhi) return 0;
  var besti = alo, bestj = blo, size = 0;
  var lengths = <int, int>{};
  for (var i = alo; i < ahi; i++) {
    final next = <int, int>{};
    for (var j = blo; j < bhi; j++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(j)) continue;
      final k = (lengths[j - 1] ?? 0) + 1;
      next[j] = k;
      if (k > size) {
        besti = i - k + 1;
        bestj = j - k + 1;
        size = k;
      }
    }
    lengths = next;
  }
  if (size == 0) return 0;
  return size +
      _matched(a, alo, besti, b, blo, bestj) +
      _matched(a, besti + size, ahi, b, bestj + size, bhi);
}
