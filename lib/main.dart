import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as FMTC;
import 'package:geolocator/geolocator.dart';
import 'dart:math';

Future<void> main() async {
  // Ensure Flutter is Ready
  WidgetsFlutterBinding.ensureInitialized();
  //British FUCKS use an "s" not a "z" with initialize
  await FMTC.FMTCObjectBoxBackend().initialise();
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://vjageqfberifyclotivb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZqYWdlcWZiZXJpZnljbG90aXZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwMjMwOTcsImV4cCI6MjA3MjU5OTA5N30.Lu_RaQsjP4uE_FAFuXSFDNmuhG84ihtdmYZtSXiEz9A',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //this would come from your supabase in a real app
  final supabase = Supabase.instance.client;
  final List<Marker> _markers = [];
  String _locationName = 'Kizmet Map'; // this will hold our dynamic title
  Timer? _debounce; //Used to delay geocoding until the user stops moving the map

  //a controller to interact with the map
  final MapController _mapController = MapController();

  //This function fetches initial markers
  Future<void> _getInitialMarkers() async {
    try {
      final data = await supabase.from('locations').select();

      // If data is not null, create markers from it
      if (data.isNotEmpty) {
        final List<Marker> loadedMarkers = [];
        for (var row in data) {
          final lat = row['latitude'] as double;
          final lng = row['longitude'] as double;
          loadedMarkers.add(
            Marker(
              width: 80.0,
              height: 80.0,
              point: LatLng(lat, lng),
              child: const Icon(Icons.location_pin, color: Colors.blue, size: 40.0),
            ),
          );
        }
        // Update the state to display markers
        setState(() {
          _markers.addAll(loadedMarkers);
        });
      }
    } catch (e) {
      print("Error fetching initial markers: $e");
    }
  }

@override
void initState() {
  super.initState();
  _getInitialMarkers();
  _downloadOfflineMap();
}

Future<void> _reverseGeocode(LatLng center) async {

  try {
    List<Placemark> placemarks = await placemarkFromCoordinates(center.latitude, center.longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      setState(() {
        _locationName = "${p.locality}, ${p.administrativeArea}";
      });
    }
  } catch (e) {
    print("Error during reverse geocoding: $e");
  }
}

Future<void> _addMarkerAtCenter() async {
  try {
    final point = _mapController.camera.center;
    await supabase.from('locations').insert({
      'latitude': point.latitude,
      'longitude': point.longitude,
    });

    setState(() {
      _markers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: point,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 40.0),
        ),
      );
    });
  } catch (e) {
    print("Error saving marker: $e");
  }
}

Future<void> _downloadOfflineMap() async {
  try {
    //get user's current location
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    LatLng userLocation = LatLng(position.latitude, position.longitude);

    //Define the download regions
    final highDetailBounds = LatLngBounds.fromPoints(
      _calculateBoundingBox(userLocation, 30), // 30-mile radius for high detail
    );
    final lowDetailBounds = LatLngBounds.fromPoints(
      _calculateBoundingBox(userLocation, 100), // 100-mile radius for low detail
    );

    // Download high-detailed region
    await FMTC.FMTCStore('mapStore').download.startForeground(
      region: RectangleRegion(highDetailBounds).toDownloadable(
      1,
      15,

      TileLayerOptions(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  } catch (e) {
    print("Error downloading offline map: $e");
  }
}

List<LatLng> _calculateBoundingBox(LatLng center, double radiusInMiles) {
  const double milesToKm = 1.60934;
  final double radiusInKm = radiusInMiles * milesToKm;
  final double distance = radiusInKm / 2;
  final double earthRadius = 6371.0;

  double lat1 = center.latitude - (distance / earthRadius) * (180 / pi);
  double lon1 = center.longitude - (distance / earthRadius) * (180 / pi) / cos(center.latitude * pi / 180);
  double lat2 = center.latitude + (distance / earthRadius) * (180 / pi);
  double lon2 = center.longitude + (distance / earthRadius) * (180 / pi) / cos(center.latitude * pi / 180);

  return [LatLng(lat1, lon1), LatLng(lat2, lon2)];
}

@override
void dispose() {
  _debounce?.cancel();
  _mapController.dispose(); //Dispose of the controller
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(_locationName),
        ),
        body:FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(42.8781, -88.6298),
            initialZoom: 13.0,
            onPositionChanged: (position, hasGesture) {
              // Debouncing: Wait until the ser stops moving the map for 500ms
              if (_debounce?.isActive ?? false) _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () async {
                if (position.center != null) {
                  _reverseGeocode(position.center!);
                }
              });
            },
          ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            tileProvider: FMTCTileProvider(
              store: FMTCStore('mapStore'),
              Strategy: BrowseStoreStrategy.readUpdateCreate,
          ),
          MarkerLayer(
            markers: _markers,
          ),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                '@ OpenStreetMap contributors',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMarkerAtCenter,
        tooltip: 'Add Marker',
        child: const Icon(Icons.add_location),
        ),
      ),
    );
  }
}
