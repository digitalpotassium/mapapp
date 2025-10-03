import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Ensure Flutter is Ready
  WidgetsFlutterBinding.ensureInitialized();

  //load the enviornment variables from the .env file
  await dotenv.load(fileName: ".env");

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
      print("Error during reverse geocoding: $e");
    }
  }

@override
void initState() {
  super.initState();
  _getInitialMarkers();
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

@override
void dispose() {
  _debounce?.cancel();
  _mapController.dispose(); //Dispose of the controller
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    // retreives Mapbox access token
    final mapboxAccessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    
    if (mapboxAccessToken == null) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Mapbox Access token not found!'),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Kizmet Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          // The Title now uses our state variable
          title: Text(_locationName),
          ),
        body: FlutterMap(
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
              urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}',
              additionalOptions: {
                'accessToken': mapboxAccessToken,
              },
            ),
            MarkerLayer(
              markers: _markers,
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  '@ Mapbox',
                  onTap: () {},
                ),
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
