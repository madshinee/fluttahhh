import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String id; // Changé en String pour l'UID Supabase
  final String fullname;
  final String email;
  final String phone;
  final String country;
  final String state;
  final String address;
  final String? photoUrl; // Photo de profil optionnelle

  User({
    required this.id,
    required this.fullname,
    required this.email,
    required this.phone,
    this.country = '',
    this.state = '',
    this.address = '',
    this.photoUrl,
  });

  User copyWith({
    String? id,
    String? fullname,
    String? email,
    String? phone,
    String? country,
    String? state,
    String? address,
    String? photoUrl,
  }) {
    return User(
      id: id ?? this.id,
      fullname: fullname ?? this.fullname,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      country: country ?? this.country,
      state: state ?? this.state,
      address: address ?? this.address,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      fullname: json['fullname'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      address: json['address'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
    );
  }

  factory User.fromSupabaseJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      fullname: json['fullname'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      address: json['address'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
    );
  }

  factory User.fromSupabaseUser(supabase.User user) {
    return User(
      id: user.id, // Direct l'UID Supabase
      fullname: user.userMetadata?['fullname'] as String? ?? user.email?.split('@')[0] ?? '',
      email: user.email ?? '',
      phone: user.userMetadata?['phone'] as String? ?? '',
      country: user.userMetadata?['country'] as String? ?? '',
      state: user.userMetadata?['state'] as String? ?? '',
      address: user.userMetadata?['address'] as String? ?? '',
      photoUrl: user.userMetadata?['photoUrl'] as String? ?? user.userMetadata?['avatar_url'] as String?,
    );
  }

  factory User.fromFirebaseJson(String id, Map<String, dynamic> json) {
    return User(
      id: id,
      fullname: json['fullname'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      address: json['address'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
    );
  }

  factory User.fromFirebaseUser(firebase.User user) {
    return User(
      id: user.uid,
      fullname: user.displayName ?? user.email?.split('@')[0] ?? '',
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      country: '',
      state: '',
      address: '',
      photoUrl: user.photoURL,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullname': fullname,
      'email': email,
      'phone': phone,
      'country': country,
      'state': state,
      'address': address,
      'photoUrl': photoUrl,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id, // Garder l'ID pour la table users
      'fullname': fullname,
      'email': email.toLowerCase(),
      'phone': phone,
      'country': country,
      'state': state,
      'address': address,
      'photoUrl': photoUrl,
    };
  }

  Map<String, dynamic> toFirebaseJson() {
    return {
      'fullname': fullname,
      'email': email.toLowerCase(),
      'phone': phone,
      'country': country,
      'state': state,
      'address': address,
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  String toJsonString() {
    return '''{
      "id": "$id",
      "fullname": "$fullname",
      "email": "$email",
      "phone": "$phone",
      "country": "$country",
      "state": "$state",
      "address": "$address",
      "photoUrl": "$photoUrl"
    }''';
  }

  factory User.fromJsonString(String jsonString) {
    // Simple parsing for offline storage
    final id = RegExp(r'"id":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final fullname = RegExp(r'"fullname":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final email = RegExp(r'"email":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final phone = RegExp(r'"phone":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final country = RegExp(r'"country":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final state = RegExp(r'"state":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final address = RegExp(r'"address":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    final photoUrl = RegExp(r'"photoUrl":\s*"([^"]+)"').firstMatch(jsonString)?.group(1) ?? '';
    
    return User(
      id: id,
      fullname: fullname,
      email: email,
      phone: phone,
      country: country,
      state: state,
      address: address,
      photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
    );
  }
}
