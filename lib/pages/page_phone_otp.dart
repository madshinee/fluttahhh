import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/supabase_service.dart';
import '../models/user.dart' as app_user;
import 'page_tasks.dart';


class PagePhoneOTP extends StatefulWidget {
  final String phoneNumber;
  
  const PagePhoneOTP({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<PagePhoneOTP> createState() => _PagePhoneOTPState();
}

class _PagePhoneOTPState extends State<PagePhoneOTP> {
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isButtonEnabled = false;
  DateTime? _lastOTPSent;
  bool _canResend = true;

  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(_validate);
    // Envoyer l'OTP automatiquement
    _sendOTP();
  }

  void _validate() {
    setState(() {
      _isButtonEnabled = _otpCtrl.text.length == 6;
    });
  }

  Future<void> _sendOTP() async {
    // Vérifier le cooldown (60 secondes)
    if (_lastOTPSent != null) {
      final timeSinceLast = DateTime.now().difference(_lastOTPSent!);
      if (timeSinceLast.inSeconds < 60) {
        _showSnack('Attendez ${60 - timeSinceLast.inSeconds} secondes', isError: true);
        return;
      }
    }

    try {
      setState(() => _isLoading = true);
      await SupabaseService.signInWithPhone(widget.phoneNumber);
      _lastOTPSent = DateTime.now();
      _showSnack('Code envoyé au ${widget.phoneNumber}');
    } catch (e) {
      _showSnack('Erreur envoi SMS: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onVerifyOTP() async {
    if (!_isButtonEnabled) return;
    
    setState(() => _isLoading = true);
    try {
      final authResponse = await SupabaseService.verifyOTP(
        widget.phoneNumber,
        _otpCtrl.text.trim(),
      );

      if (authResponse.user != null) {
        // Récupérer le profil utilisateur
        final users = await SupabaseService.getUsers();
        app_user.User user;
        
        try {
          user = users.firstWhere(
            (u) {
              String cleanPhone = widget.phoneNumber.replaceAll('+', '').replaceAll('221', '').replaceAll(' ', '').replaceAll('-', '');
              String cleanUserPhone = u.phone.replaceAll('+', '').replaceAll('221', '').replaceAll(' ', '').replaceAll('-', '');
              debugPrint('Recherche téléphone: "$cleanPhone" dans "$cleanUserPhone"');
              return cleanUserPhone.contains(cleanPhone) || cleanPhone.contains(cleanUserPhone) || u.phone.contains(widget.phoneNumber);
            },
          );
          debugPrint('Utilisateur trouvé par téléphone: ${user.fullname} (${user.email})');
          debugPrint('ID utilisateur trouvé: ${user.id}');
          debugPrint('Téléphone utilisateur: ${user.phone}');
          debugPrint('ID authResponse: ${authResponse.user!.id}');
          debugPrint('=== COMPARAISON DES IDs ===');
          debugPrint('ID base de données: ${user.id}');
          debugPrint('ID auth Supabase: ${authResponse.user!.id}');
          debugPrint('IDs identiques: ${user.id == authResponse.user!.id}');
          
          // CORRECTION : Forcer l'utilisation de l'ID de la base de données
          if (user.id != authResponse.user!.id) {
            debugPrint('CORRECTION : Utilisation de l\'ID de la base de données au lieu de l\'ID auth');
            // Conserver l'ID de la base de données mais mettre à jour les autres infos
            user = app_user.User(
              id: user.id,  // Garder l'ID de la base de données !
              fullname: user.fullname,
              email: user.email,
              phone: user.phone,
              country: user.country,
              state: user.state,
              address: user.address,
            );
          }
        } catch (e) {
          debugPrint('Aucun utilisateur trouvé pour le téléphone: ${widget.phoneNumber}');
          debugPrint('Création d\'un nouvel utilisateur avec l\'ID Supabase: ${authResponse.user!.id}');
          
          // Créer le profil s'il n'existe pas
          user = app_user.User(
            id: authResponse.user!.id,
            fullname: authResponse.user!.userMetadata?['fullname'] ?? 
                     'Utilisateur Téléphone',
            email: authResponse.user!.userMetadata?['email'] ?? '',
            phone: widget.phoneNumber,
            country: authResponse.user!.userMetadata?['country'] ?? '',
            state: authResponse.user!.userMetadata?['state'] ?? '',
            address: authResponse.user!.userMetadata?['address'] ?? '',
          );
          
          try {
            await SupabaseService.createUser(user);
            debugPrint('UTILISATEUR CRÉÉ/MIS À JOUR DANS SUPABASE: ${user.id}');
          } catch (createError) {
            print('Erreur création profil: $createError');
          }
        }
        
        _showSnack('Bienvenue ${user.fullname} 👋');
        await Future.delayed(const Duration(milliseconds: 800));
        
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PageTasks(user: user)),
        );
      }
    } catch (e) {
      _showSnack('Code invalide: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[400] : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
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
              const SizedBox(height: 16),

              // ── Back button ──
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textDark,
                  size: 24,
                ),
              ),
              const SizedBox(height: 40),

              // ── Title ──
              const Center(
                child: Text(
                  'Vérification',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Entrez le code à 6 chiffres envoyé à\n${widget.phoneNumber}',
                  style: const TextStyle(
                    fontSize: 14, 
                    color: AppColors.textGrey
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),

              // ── OTP Input ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder),
                ),
                child: TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: AppColors.textDark,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '------',
                    hintStyle: TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      color: AppColors.textGrey,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // ── Verify button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isButtonEnabled && !_isLoading ? _onVerifyOTP : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white, 
                            strokeWidth: 2.5
                          )
                        )
                      : const Text(
                          'Vérifier',
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w600
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Resend link ──
              Center(
                child: TextButton(
                  onPressed: _isLoading ? null : _sendOTP,
                  child: Text(
                    'Renvoyer le code',
                    style: TextStyle(
                      color: _isLoading ? Colors.grey : AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
