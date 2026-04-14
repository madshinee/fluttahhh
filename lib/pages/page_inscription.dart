import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';
import '../models/user.dart' as app_user;
import '../services/data_provider_service.dart';
import '../services/offline_service.dart';
import '../services/error_reporting_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../services/firebase_service.dart';
import 'page_connexion.dart';
import 'page_tasks.dart';

import 'page_onboarding.dart';

class PageInscription extends StatefulWidget {
  const PageInscription({super.key});

  @override
  State<PageInscription> createState() => _PageInscriptionState();
}

class _PageInscriptionState extends State<PageInscription> {
  // ── Controllers ──
  final _nomCtrl        = TextEditingController();
  final _emailCtrl      = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _confirmCtrl    = TextEditingController();

  // ── State ──
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _agreeTerms      = false;
  bool _isButtonEnabled = false;
  bool _isLoading       = false;
  String? _emailError;
  String? _passwordError;

  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCountryCode;

  // Country and States data
  LocationData? locationData;
  List<Map<String, dynamic>> _countries = [
    {'name': 'Sénégal', 'code': 'SN'},
    {'name': 'France', 'code': 'FR'},
    {'name': 'États-Unis', 'code': 'US'},
    {'name': 'Canada', 'code': 'CA'},
    {'name': 'Mali', 'code': 'ML'},
    {'name': 'Côte d\'Ivoire', 'code': 'CI'},
    {'name': 'Burkina Faso', 'code': 'BF'},
    {'name': 'Niger', 'code': 'NE'},
    {'name': 'Guinée', 'code': 'GN'},
  ];
  
  List<String> _states = [];
  bool _countriesLoading = true;
  bool _statesLoading = false;
  bool _gpsRetried = false;

  @override
  void initState() {
    super.initState();
    _nomCtrl.addListener(_validate);
    _emailCtrl.addListener(_validate);
    _phoneCtrl.addListener(_validate);
    _addressCtrl.addListener(_validate);
    _passwordCtrl.addListener(_validate);
    _confirmCtrl.addListener(_validate);
    _loadCountries();
    _detectLocation(); // Auto-détection GPS
  }

  Future<void> _loadCountries() async {
    try {
      setState(() {
        _countriesLoading = false;
      });
      debugPrint(' Pays chargés: ${_countries.length}');
    } catch (e) {
      setState(() => _countriesLoading = false);
      debugPrint(' Erreur chargement pays: $e');
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() => _statesLoading = true);
    try {
      // Define states for each country
      final Map<String, List<String>> countryStates = {
        'SN': ['Dakar', 'Thiès', 'Kaolack', 'Saint-Louis', 'Diourbel', 'Louga', 'Fatick', 'Kédougou', 'Kolda', 'Tambacounda', 'Mbour'],
        'FR': ['Île-de-France', 'Provence-Alpes-Côte d\'Azur', 'Hauts-de-France', 'Auvergne-Rhône-Alpes', 'Nouvelle-Aquitaine'],
        'US': ['California', 'Texas', 'New York', 'Florida', 'Illinois'],
        'CA': ['Ontario', 'Quebec', 'British Columbia', 'Alberta'],
        'ML': ['Bamako', 'Sikasso', 'Mopti', 'Kayes', 'Ségou', 'Koulikoro'],
        'CI': ['Abidjan', 'Bouaké', 'Daloa', 'Yamoussoukro', 'Korhogo', 'San Pedro', 'Divo', 'Gagnoa', 'Soubré', 'Man', 'Danané', 'Guiglo', 'Toulépleu', 'Séguéla', 'Bondoukou', 'Bouna', 'Odienné', 'Mankono', 'Sakassou', 'Béoumi', 'Katiola', 'Dabou', 'Grand-Bassam', 'Bonoua', 'Agboville', 'Sinfra', 'Tiassalé', 'Toumodi', 'Dimbokro', 'Bocanda', 'Yamoussoukro', 'Abengourou', 'Aboisso', 'Adzopé', 'Alépé', 'Attécoubé', 'Bingerville', 'Brobo', 'Dabou', 'Diasson', 'Gagnoa', 'Grand-Béréby', 'Guéyo', 'Issia', 'Jacqueville', 'Lakota', 'Maféré', 'Méagui', 'Oumé', 'Sassandra', 'Séguéla', 'Sipilou', 'Tabou', 'Taabo', 'Tieningboué', 'Toulépleu', 'Vavoua', 'Zouan-Hounien'],
      };
      
      setState(() {
        _states = countryStates[countryCode] ?? [];
        _statesLoading = false;
      });
      debugPrint(' States chargés: ${_states.length}');
    } catch (e) {
      setState(() => _statesLoading = false);
      debugPrint('Erreur chargement states: $e');
    }
  }

  Future<void> _detectLocation() async {
    try {
      debugPrint('Début détection GPS...');
      locationData = await LocationService.getCurrentLocation();
      if (locationData != null) {
        debugPrint('GPS trouvé: ${locationData!.country} / ${locationData!.state}');
        
        // Find matching country
        final matchingCountry = _countries.firstWhere(
          (country) => country['name'] == locationData!.country,
          orElse: () => <String, dynamic>{},
        );
        
        debugPrint('Pays trouvé: ${matchingCountry.isNotEmpty ? matchingCountry['name'] : 'NON'}');
          
        if (matchingCountry.isNotEmpty) {
          final countryName = matchingCountry['name'] as String;
          final countryCode = matchingCountry['code'] as String;
          final countryList = _countries.map((c) => c['name'] as String).toList();
            
          debugPrint('Liste pays: ${countryList.take(5).toList()}...');
          debugPrint('Pays à sélectionner: "$countryName"');
          debugPrint('Pays dans liste: ${countryList.contains(countryName)}');
            
          setState(() {
            _selectedCountry = countryName;
            _selectedCountryCode = countryCode;
          });
          debugPrint('Pays sélectionné: $_selectedCountry');
            
          // Charger les states pour ce pays
          await _loadStates(countryCode);
            
          // Forcer la reconstruction du dropdown
          setState(() {});
            
          // Pré-sélectionner le state si trouvé
          if (locationData!.state.isNotEmpty && _states.isNotEmpty) {
            debugPrint('States disponibles: ${_states.length}');
            debugPrint('Recherche state: "${locationData!.state}"');
              
            final matchingState = _states.firstWhere(
              (state) => state.toLowerCase() == locationData!.state.toLowerCase(),
              orElse: () => '',
            );
              
            debugPrint('State trouvé: "${matchingState.isNotEmpty ? matchingState : 'NON'}"');
              
            if (matchingState.isNotEmpty) {
              debugPrint('Liste states: ${_states.take(5).toList()}...');
              debugPrint('State à sélectionner: "$matchingState"');
              debugPrint('State dans liste: ${_states.contains(matchingState)}');
                
              setState(() {
                _selectedState = matchingState;
              });
              debugPrint('State sélectionné: $_selectedState');
            }
          }
        }
      } else {
        debugPrint('GPS non disponible');
      }
    } catch (e) {
      debugPrint('Erreur détection auto: $e');
    }
  }

  void _validate() {
    final nomOk  = _nomCtrl.text.trim().isNotEmpty;
    final emailOk = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
        .hasMatch(_emailCtrl.text.trim());
    final phoneOk = _phoneCtrl.text.trim().length >= 8;
    final addressOk = _addressCtrl.text.trim().isNotEmpty;
    final countryOk = _selectedCountry != null;
    final stateOk = _selectedState != null;
    final passOk  = _passwordCtrl.text.length >= 8;
    final matchOk = _passwordCtrl.text == _confirmCtrl.text &&
        _confirmCtrl.text.isNotEmpty;

    setState(() {
      // Email validation
      if (_emailCtrl.text.isNotEmpty && !emailOk) {
        _emailError = 'Format d\'email invalide';
      } else {
        _emailError = null;
      }
      
      // Password match validation
      if (_confirmCtrl.text.isNotEmpty && !matchOk) {
        _passwordError = 'Les mots de passe ne correspondent pas';
      } else {
        _passwordError = null;
      }
      
      _isButtonEnabled =
          nomOk && emailOk && phoneOk && addressOk && countryOk && stateOk && passOk && matchOk && _agreeTerms;
      
      // Debug logs pour diagnostiquer
      debugPrint('=== VALIDATION DEBUG ===');
      debugPrint('nomOk: $nomOk (${_nomCtrl.text.trim()})');
      debugPrint('emailOk: $emailOk (${_emailCtrl.text.trim()})');
      debugPrint('phoneOk: $phoneOk (${_phoneCtrl.text.trim()})');
      debugPrint('addressOk: $addressOk (${_addressCtrl.text.trim()})');
      debugPrint('countryOk: $countryOk ($_selectedCountry)');
      debugPrint('stateOk: $stateOk ($_selectedState)');
      debugPrint('passOk: $passOk (${_passwordCtrl.text.length} chars)');
      debugPrint('matchOk: $matchOk');
      debugPrint('_agreeTerms: $_agreeTerms');
      debugPrint('_isButtonEnabled: $_isButtonEnabled');
      debugPrint('=====================');
    });
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCreateAccount() async {
    debugPrint('=== _onCreateAccount appelé ===');
    debugPrint('Nom: ${_nomCtrl.text.trim()}');
    debugPrint('Email: ${_emailCtrl.text.trim()}');
    debugPrint('Phone: ${_phoneCtrl.text.trim()}');
    debugPrint('Country: ${_selectedCountry}');
    debugPrint('State: ${_selectedState}');
    debugPrint('Address: ${_addressCtrl.text.trim()}');
    
    setState(() => _isLoading = true);
    try {
      // S'assurer que la base de données est initialisée
      debugPrint('Initialisation de la base de données...');
      await OfflineService.initialize();
      debugPrint('Base de données initialisée');
      
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      
      final newUser = app_user.User(
        id: Uuid().v4(), // Enlever const pour générer un nouveau UUID à chaque fois
        fullname: _nomCtrl.text.trim(),
        email: email,
        phone: _phoneCtrl.text.trim().startsWith('+') 
            ? _phoneCtrl.text.trim() 
            : '+221${_phoneCtrl.text.trim()}',
        country: _selectedCountry ?? '',
        state: _selectedState ?? '',
        address: _addressCtrl.text.trim(),
      );

      debugPrint('Création utilisateur: ${newUser.toJson()}');

      // 1. Create user in offline storage first
      debugPrint('Sauvegarde locale...');
      await OfflineService.insertUser(newUser);
      debugPrint('Utilisateur sauvegardé localement');
      
      // 2. Créer les comptes Auth d'abord
      try {
        // Supabase Auth → déclenche automatiquement ton trigger handle_new_user
        final supabaseResponse = await SupabaseService.signUpWithEmail(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          data: {
            'fullname': newUser.fullname,
            'phone': newUser.phone,
            'country': newUser.country,
            'state': newUser.state,
            'address': newUser.address,
          },
        );
        debugPrint(' Compte Supabase Auth créé + profil automatique via trigger');

        // Firebase Auth
        await FirebaseService.signUpWithEmail(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
        debugPrint(' Compte Firebase Auth créé');

        // Firebase Firestore → maintenant auth != null, les règles acceptent
        // Vérifier si l'utilisateur existe déjà pour éviter la duplication
        app_user.User? existingUser;
        try {
          existingUser = await DataProviderService.findUser(newUser.email);
          debugPrint('Utilisateur existant trouvé: ${existingUser != null}');
        } catch (e) {
          debugPrint('Erreur vérification utilisateur existant: $e');
        }
        
        final createdUser = existingUser ?? await DataProviderService.createUser(newUser);
        await OfflineService.updateUser(createdUser);
        
        await ErrorReportingService.reportMessage('User created successfully: ${createdUser.email}');
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Compte créé avec succès !'),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        
        // Navigate to home page with the created user
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PageTasks(user: createdUser)),
        );
        
      } catch (providerError) {
        await ErrorReportingService.reportError(
          providerError, 
          StackTrace.current, 
          context: {
            'action': 'user_creation_remote',
            'user_email': newUser.email,
          }
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Compte créé mais erreur de synchronisation. Vos données sont enregistrées localement.'),
          backgroundColor: Colors.orange[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        
        // Navigate to home page with offline user
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PageTasks(user: newUser)),
        );
      }
      
    } catch (e) {
      await ErrorReportingService.reportError(
        e, 
        StackTrace.current, 
        context: {
          'action': 'user_creation',
          'user_email': _emailCtrl.text.trim(),
        }
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              const SizedBox(height: 24),

              // ── Title ──
              const Center(
                child: Text(
                  'Sign Up',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Please provide the details below to\ncreate your account',
                  style: TextStyle(fontSize: 13, color: AppColors.textGrey),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),

              // ── Full Name ──
              _buildLabel('Full Name'),
              const SizedBox(height: 8),
              _buildInput(
                controller: _nomCtrl,
                hint: 'Full Name',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 14),

              // ── Email ──
              _buildLabel('Email Address'),
              const SizedBox(height: 8),
              _buildInput(
                controller: _emailCtrl,
                hint: 'Email Address',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
              ),
              const SizedBox(height: 14),

              // ── Phone ──
              _buildLabel('Phone Number'),
              const SizedBox(height: 8),
              _buildInput(
                controller: _phoneCtrl,
                hint: 'Phone Number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // ── Country + State ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Country'),
                        const SizedBox(height: 8),
                        _countriesLoading
                            ? _buildLoadingDropdown()
                            : _buildDropdown(
                                value: _selectedCountry,
                                hint: 'Country',
                                items: _countries.map((c) => c['name'] as String).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _selectedCountry = v;
                                    _selectedState = null; // Réinitialiser l'état
                                    _states.clear(); // Vider la liste des états
                                  });
                                  // Trouver le code pays et charger les états
                                  final country = _countries.firstWhere(
                                    (c) => c['name'] == v,
                                    orElse: () => {'code': ''},
                                  );
                                  if (country['code'].isNotEmpty) {
                                    _selectedCountryCode = country['code'];
                                    _loadStates(country['code']);
                                  }
                                  _validate();
                                },
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('State'),
                        const SizedBox(height: 8),
                        _statesLoading
                            ? _buildLoadingDropdown()
                            : _buildDropdown(
                                value: _selectedState,
                                hint: 'State',
                                items: _states,
                                onChanged: (v) {
                                  setState(() => _selectedState = v);
                                  _validate();
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Home Address ──
              _buildLabel('Home Address'),
              const SizedBox(height: 8),
              _buildInput(
                controller: _addressCtrl,
                hint: 'Home Address',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 14),

              // ── New Password ──
              _buildLabel('New Password'),
              const SizedBox(height: 8),
              _buildPasswordInput(
                controller: _passwordCtrl,
                hint: 'New Password',
                obscure: _obscurePassword,
                onToggle: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 14),

              // ── Confirm Password ──
              _buildLabel('Confirm Password'),
              const SizedBox(height: 8),
              _buildPasswordInput(
                controller: _confirmCtrl,
                hint: 'Confirm Password',
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                errorText: _passwordError,
              ),
              const SizedBox(height: 16),

              // ── Terms checkbox ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreeTerms,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) {
                        setState(() => _agreeTerms = v ?? false);
                        _validate();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            color: AppColors.textGrey, fontSize: 12),
                        children: [
                          TextSpan(text: 'I agree with the '),
                          TextSpan(
                            text: 'Terms and Conditions',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: ' of TranspoX'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Create Account button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      _isButtonEnabled && !_isLoading ? _onCreateAccount : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Sign in link ──
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Have an account? ',
                        style: TextStyle(
                            color: AppColors.textGrey, fontSize: 13)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PageConnexion()),
                      ),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark),
      );

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textGrey, size: 20),
        errorText: errorText,
        errorStyle: const TextStyle(fontSize: 12, color: Colors.red),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }

  Widget _buildPasswordInput({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            color: AppColors.textGrey, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textGrey,
            size: 20,
          ),
          onPressed: onToggle,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(fontSize: 12, color: Colors.red),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                  color: AppColors.textGrey, fontSize: 14)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textGrey, size: 20),
          isExpanded: true,
          style: const TextStyle(
              color: AppColors.textDark, fontSize: 14),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLoadingDropdown() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Chargement...',
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
