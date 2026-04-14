import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io' show Platform;

class LocationService {
  static Future<LocationData?> getCurrentLocation() async {
    try {
      // GPS non supporté sur web
      if (kIsWeb) {
        debugPrint('GPS non disponible sur web');
        return null;
      }
      
      // Vérifier les permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Service GPS désactivé');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Permission GPS refusée');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Permission GPS refusée permanently');
        return null;
      }

      // Obtenir la position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Reverse geocoding
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return LocationData(
          country: place.country ?? '',
          state: place.administrativeArea ?? place.subAdministrativeArea ?? '',
          city: place.locality ?? place.subLocality ?? '',
          fullAddress: _formatAddress(place),
        );
      }

      return null;
    } catch (e) {
      debugPrint('Erreur GPS: $e');
      return null;
    }
  }

  static String _formatAddress(Placemark place) {
    final parts = [
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
      place.country,
    ].where((part) => part != null && part.isNotEmpty);
    
    return parts.join(', ');
  }
}

class LocationData {
  final String country;
  final String state;
  final String city;
  final String fullAddress;

  LocationData({
    required this.country,
    required this.state,
    required this.city,
    required this.fullAddress,
  });
}
