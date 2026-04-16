import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../models/user.dart' as app_user;
import '../services/data_provider_service.dart';
import '../services/offline_service.dart';
import '../services/error_reporting_service.dart';
import '../services/google_auth_service.dart';
import '../services/supabase_service.dart';
import '../services/firebase_service.dart';
import 'page_inscription.dart';

import 'page_onboarding.dart';
import 'page_forgot_password.dart';
import 'page_phone_otp.dart';
import 'page_tasks.dart';

class PageConnexion extends StatefulWidget {
  const PageConnexion({super.key});

  @override
  State<PageConnexion> createState() => _PageConnexionState();
}

class _PageConnexionState extends State<PageConnexion> {
  // ── Controllers ──
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // ── State ──
  bool _obscurePassword = true;
  bool _useEmail = true;
  bool _isLoading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('remembered_email');
      final password = prefs.getString('remembered_password');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (email != null && password != null && rememberMe) {
        setState(() {
          _emailCtrl.text = email;
          _passwordCtrl.text = password;
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading remembered credentials: $e');
    }
  }

  Future<void> _saveRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailCtrl.text.trim());
        await prefs.setString('remembered_password', _passwordCtrl.text.trim());
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('remembered_email');
        await prefs.remove('remembered_password');
        await prefs.remove('remember_me');
      }
    } catch (e) {
      debugPrint('Error saving remembered credentials: $e');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Login logic ──────────────────────────────────────────────────────────────
  Future<void> _onLogin() async {
    setState(() => _isLoading = true);
    try {
      final loginVal = _useEmail
          ? _emailCtrl.text.trim()
          : _phoneCtrl.text.trim();

      if (_useEmail) {
        final password = _passwordCtrl.text.trim();
        
        // Email login with AUTH verification (critical fix!)
        try {
          debugPrint('Tentative de connexion pour: $loginVal');
          
          // Utiliser DataProviderService avec fallback hors ligne
          app_user.User? user = await DataProviderService.signInWithEmail(_emailCtrl.text.trim(), _passwordCtrl.text);
          debugPrint('Auth réussie avec fallback hors ligne');
          
          if (user != null) {
            await ErrorReportingService.reportMessage('User authenticated successfully: ${user.email}');
            _showSnack('Welcome ${user.fullname} ');
            await Future.delayed(const Duration(milliseconds: 800));
            
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => PageTasks(user: user)),
            );
            return;
          } else {
            _showSnack('Email ou mot de passe incorrect', isError: true);
          }
        } catch (e) {
          await ErrorReportingService.reportError(
            e, 
            StackTrace.current, 
            context: {
              'action': 'login',
              'email': loginVal,
            }
          );
          _showSnack('Erreur de connexion : $e', isError: true);
        }
      } else {
        // Phone login - Redirection vers OTP
        String formattedPhone = loginVal;
        if (!loginVal.startsWith('+')) {
          formattedPhone = '+221$loginVal'; // Ajouter l'indicatif sénégalais par défaut
        }
        
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PagePhoneOTP(phoneNumber: formattedPhone),
          ),
        );
        return;
      }
    } catch (e) {
      await ErrorReportingService.reportError(
        e, 
        StackTrace.current, 
        context: {
          'action': 'login_general',
          'login_val': _useEmail ? _emailCtrl.text.trim() : _phoneCtrl.text.trim(),
        }
      );
      _showSnack('Erreur de connexion : $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[400] : Colors.pink[300],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
              const SizedBox(height: 24),

              // ── Title ──
              const Center(
                child: Text(
                  'Sign In',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Please provide your email and password to\nsign in to your account',
                  style: TextStyle(fontSize: 13, color: AppColors.textGrey),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),

              // ── Email/Phone toggle ──
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useEmail = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _useEmail ? AppColors.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'Email',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _useEmail ? AppColors.primary : AppColors.textGrey,
                            fontWeight: _useEmail ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useEmail = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: !_useEmail ? AppColors.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'Phone',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !_useEmail ? AppColors.primary : AppColors.textGrey,
                            fontWeight: !_useEmail ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Email/Phone input ──
              if (_useEmail) ...[
                _buildLabel('Email Address'),
                const SizedBox(height: 8),
                _buildInput(
                  controller: _emailCtrl,
                  hint: 'Email Address',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
              ] else ...[
                _buildLabel('Phone Number'),
                const SizedBox(height: 8),
                _buildInput(
                  controller: _phoneCtrl,
                  hint: 'Phone Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
              ],
              const SizedBox(height: 14),

              // ── Password input (only for email) ──
              if (_useEmail) ...[
                _buildLabel('Password'),
                const SizedBox(height: 8),
                _buildPasswordInput(),
                const SizedBox(height: 14),

                // ── Remember me + Forgot password ──
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                              onChanged: (v) {
                                setState(() => _rememberMe = v ?? false);
                                _saveRememberedCredentials();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Remember me',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textGrey),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PageForgotPassword()),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // ── Sign in button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_useEmail
                          ? _emailCtrl.text.isNotEmpty && _passwordCtrl.text.isNotEmpty
                          : _phoneCtrl.text.isNotEmpty) &&
                      !_isLoading
                      ? _onLogin
                      : null,
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
                      : Text(
                          'Sign In',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // ── OR divider ──
              Row(
                children: [
                  const Expanded(
                      child: Divider(color: AppColors.textGrey, thickness: 0.5)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Expanded(
                      child: Divider(color: AppColors.textGrey, thickness: 0.5)),
                ],
              ),
              const SizedBox(height: 24),

              // ── Social login buttons ──
              _SocialButton(
                text: 'Continue with Google',
                icon: 'assets/icons/google.svg',
                onPressed: () => _handleGoogleSignIn(),
              ),
              const SizedBox(height: 16),

              // ── Sign up link ──
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Don\'t have an account? ',
                        style: TextStyle(
                            color: AppColors.textGrey, fontSize: 13)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PageInscription()),
                      ),
                      child: const Text(
                        'Sign up',
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

  Future<void> _handleGoogleSignIn() async {
    try {
      final user = await GoogleAuthService.signInWithGoogle();
      if (user != null && mounted) {
        debugPrint('GOOGLE SIGN IN: Utilisateur connecté ${user.id}');
        
        // Synchroniser l'utilisateur vers Firebase
        try {
          await SupabaseService.createUser(user);
          debugPrint('GOOGLE SIGN IN: Utilisateur créé/mis à jour dans Supabase');
          
          // Forcer la synchronisation vers Firebase
          await DataProviderService.syncUsersToOtherProviders([user], ProviderType.supabase);
          debugPrint('GOOGLE SIGN IN: Synchronisation vers Firebase effectuée');
        } catch (syncError) {
          debugPrint('GOOGLE SIGN IN: Erreur synchronisation: $syncError');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome ${user.fullname}!'),
            backgroundColor: Colors.pink[200],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PageTasks(user: user)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign in failed: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
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
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (value) => setState(() {}), // Déclenche la validation
      style: const TextStyle(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textGrey, size: 20),
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

  Widget _buildPasswordInput() {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      onChanged: (value) => setState(() {}), // Déclenche la validation
      style: const TextStyle(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            color: AppColors.textGrey, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textGrey,
            size: 20,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
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
}

// ── Social Button Widget ────────────────────────────────────────────────────────
class _SocialButton extends StatelessWidget {
  final String text;
  final String icon;
  final VoidCallback onPressed;

  const _SocialButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                icon,
                width: 20,
                height: 20,
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
