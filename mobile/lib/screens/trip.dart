import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// A location fix: where you are, and how sure the phone is (metres).
typedef Fix = ({double lat, double lng, double acc});

/// Your location while you share it, after asking permission. Tests replace this.
Stream<Fix> Function() locationStream = () async* {
  if (!await Geolocator.isLocationServiceEnabled()) throw ApiError('Turn on your phone\'s location, then try again.');
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
    throw ApiError(p == LocationPermission.deniedForever
        ? 'Stall can\'t see your location. Allow it in your phone\'s Settings → Apps → Stall → Permissions.'
        : 'Allow location to share where you are.');
  }
  yield* Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10))
      .map((x) => (lat: x.latitude, lng: x.longitude, acc: x.accuracy));
};

/// Map tiles from OpenStreetMap (off in tests, which have no network).
bool showMapTiles = true;

/// The live map for an order on its way: the meeting spot, and where the person travelling is.
/// The traveller (the seller on deliveries, the buyer on pickups) can share their location while this is open;
/// the other side sets the meeting spot.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.order, required this.seller, this.poll = const Duration(seconds: 5)});
  final Order order;

  /// Opened from the seller's side of the order.
  final bool seller;
  final Duration poll;
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _map = MapController();
  Map<String, dynamic>? _t;
  Timer? _timer;
  StreamSubscription<Fix>? _share;
  int _lastSent = 0;
  bool _placing = false, _busy = false;

  /// How many points (meeting spot, live position) the camera last fitted, so a new one brings both into view.
  int _fitted = 0;
  LatLng? _newPin;
  String? _msg;
  late Api _api; // kept, because dispose() can't look up the session

  Order get o => widget.order;
  bool get _delivery => o.method == 'delivery';
  bool get _iMove => widget.seller == _delivery;
  bool get _iPin => !_iMove;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = SessionScope.of(context).api;
    if (_timer == null) {
      _load();
      _timer = Timer.periodic(widget.poll, (_) => _load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Sharing is only while this screen is open: never in the background.
    if (_share != null) {
      _share!.cancel();
      _api.post('orders/live/stop', {'id': o.id}).catchError((_) => <String, dynamic>{});
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await SessionScope.of(context).api.get('orders/track', {'id': '${o.id}'});
      if (!mounted) return;
      setState(() => _t = r);
      if (r['open'] != true && _share != null) _stopShare(quiet: true);
      final pts = [?_point(r['live']), ?_point(r['pin'])];
      if (pts.length > _fitted && !_placing) {
        _fitted = pts.length;
        try {
          pts.length == 1
              ? _map.move(pts.first, 16)
              : _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(60), maxZoom: 17));
        } catch (_) {}
      }
    } catch (_) {}
  }

  LatLng? _point(Object? v) => v is Map && v['lat'] is num ? LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble()) : null;

  Future<void> _post(String path, Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      await SessionScope.of(context).api.post(path, {'id': o.id, ...body});
      if (!mounted) return;
      toast(context, done);
      await _load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startShare() {
    final api = SessionScope.of(context).api;
    setState(() => _msg = 'Finding you…');
    _share = locationStream().listen((f) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSent < 4000) return;
      _lastSent = now;
      try {
        final r = await api.post('orders/live', {'id': o.id, 'lat': f.lat, 'lng': f.lng, 'acc': f.acc});
        if (!mounted) return;
        setState(() => _msg = r['weak'] == true ? 'Your location is rough right now. Step outside or turn on GPS for a better fix.' : null);
        _load();
      } on ApiError catch (e) {
        if (!mounted) return;
        // The order moved on, or sharing hit its 90-minute limit.
        if (e.data['closed'] == true || e.data['stopped'] == true) _stopShare(quiet: true);
        setState(() => _msg = e.message);
      }
    }, onError: (Object e) {
      if (!mounted) return;
      _stopShare(quiet: true);
      setState(() => _msg = e is ApiError ? e.message : 'Couldn\'t get your location.');
    });
    setState(() {});
  }

  void _stopShare({bool quiet = false}) {
    _share?.cancel();
    _share = null;
    if (!quiet) SessionScope.of(context).api.post('orders/live/stop', {'id': o.id}).catchError((_) => <String, dynamic>{});
    if (mounted) setState(() => _msg = quiet ? _msg : null);
  }

  String _status(Map<String, dynamic> t) {
    final who = (t['who'] ?? '').toString().split(' ').first;
    final them = _iMove ? 'You' : (who.isEmpty ? 'They' : who);
    if (t['here'] == true) return _iMove ? 'You\'re at the meeting spot' : '$them has arrived';
    final eta = (t['eta'] as num?)?.toInt();
    if (eta != null) return '$them ${_iMove ? 'are' : 'is'} about $eta min away';
    if (t['live'] != null) return '$them ${_iMove ? 'are' : 'is'} on the way';
    return _iMove ? 'Share your location so they can follow you' : '$them hasn\'t shared their location yet';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final t = _t;
    final open = t?['open'] == true;
    final pin = _newPin ?? _point(t?['pin']);
    final live = _point(t?['live']);
    final lastAt = (t?['lastAt'] as num?)?.toInt();
    return Scaffold(
      appBar: AppBar(title: Text(_delivery ? 'Delivery' : 'Pickup')),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: t == null
              ? const LinearProgressIndicator()
              : !open
                  ? Text('This order isn\'t on its way any more, so there\'s nothing to follow.', key: const Key('tripClosed'), style: th.bodyLarge)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_status(t), key: const Key('tripStatus'), style: th.titleMedium),
                      Text(
                          [
                            if ((t['spot'] ?? '').toString().isNotEmpty) 'Meeting at ${t['spot']}',
                            if (lastAt != null) 'updated ${ago(lastAt)}',
                          ].join(' · '),
                          style: th.bodySmall),
                    ]),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: live ?? pin ?? const LatLng(9.08, 8.68),
                initialZoom: live != null || pin != null ? 16 : 6,
                onTap: _placing ? (_, p) => setState(() => _newPin = p) : null,
              ),
              children: [
                if (showMapTiles)
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ng.com.stall.app'),
                MarkerLayer(markers: [
                  if (pin != null)
                    Marker(
                        point: pin,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on_rounded, key: Key('pinMarker'), color: StallColors.red, size: 44)),
                  if (live != null)
                    Marker(
                      point: live,
                      width: 36,
                      height: 36,
                      child: Container(
                        key: const Key('liveMarker'),
                        decoration: BoxDecoration(color: StallColors.indigo, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                        child: Icon(_delivery ? Icons.delivery_dining_rounded : Icons.directions_walk_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                ]),
                if (showMapTiles) const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            if (_placing)
              Positioned(
                left: 16,
                right: 16,
                top: 12,
                child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_newPin == null ? 'Tap the map where you\'ll meet.' : 'Tap again to move it, then save.', textAlign: TextAlign.center))),
              ),
          ]),
        ),
        if (open)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_msg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_msg!, key: const Key('tripMsg'), style: th.bodySmall)),
                if (_iMove) ...[
                  _share == null
                      ? FilledButton.icon(
                          key: const Key('shareLive'),
                          onPressed: _startShare,
                          icon: const Icon(Icons.my_location_rounded),
                          label: const Text('Share my location'))
                      : OutlinedButton.icon(
                          key: const Key('stopLive'),
                          onPressed: _stopShare,
                          icon: const Icon(Icons.location_disabled_rounded),
                          label: const Text('Stop sharing')),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text('Optional. Only while this screen is open, for up to 90 minutes. Or just tell them when:', style: th.bodySmall),
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in const [5, 10, 20, 30])
                      ActionChip(key: Key('teta-$m'), label: Text('$m min'), onPressed: _busy ? null : () => _post('orders/eta', {'min': m}, 'Told them about $m min')),
                    ActionChip(
                        key: const Key('teta-here'), label: const Text('I\'m here'), onPressed: _busy ? null : () => _post('orders/eta', {'here': true}, 'Told them you\'re here')),
                  ]),
                ],
                if (_iPin)
                  _placing
                      ? Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => setState(() {
                                        _placing = false;
                                        _newPin = null;
                                      }),
                                  child: const Text('Cancel'))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: const Key('pinSave'),
                              onPressed: _newPin == null || _busy
                                  ? null
                                  : () async {
                                      final p = _newPin!;
                                      await _post('orders/pin', {'lat': p.latitude, 'lng': p.longitude}, 'Meeting spot saved');
                                      if (mounted) {
                                        setState(() {
                                          _placing = false;
                                          _newPin = null;
                                        });
                                      }
                                    },
                              child: const Text('Save spot'),
                            ),
                          ),
                        ])
                      : Row(children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              key: const Key('pinSet'),
                              onPressed: () => setState(() => _placing = true),
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: Text(t?['pin'] == null ? 'Set the meeting spot' : 'Move the meeting spot'),
                            ),
                          ),
                          if (t?['pin'] != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                                key: const Key('pinClear'),
                                onPressed: _busy ? null : () => _post('orders/pin', {'clear': true}, 'Meeting spot removed'),
                                child: const Text('Remove')),
                          ],
                        ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
