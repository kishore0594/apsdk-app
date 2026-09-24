/// Holds one live database stream per screen and only creates a new one
/// when its inputs change (e.g. a different day on Sales).
///
/// Writing `stream: _db.watchSomething()` directly inside build() made a
/// brand-new database listener on EVERY redraw — re-querying, flickering,
/// and online sometimes briefly dropping data while it reconnected.
class KeyedStream<T> {
  Object? _key;
  Stream<T>? _stream;

  Stream<T> get(Object key, Stream<T> Function() create) {
    if (_stream == null || key != _key) {
      _key = key;
      _stream = create();
    }
    return _stream!;
  }
}
