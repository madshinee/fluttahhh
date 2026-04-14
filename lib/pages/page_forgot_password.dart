import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/supabase_service.dart';
import '../models/user.dart';
import 'page_connexion.dart';
import 'page_reset_email_sent.dart';

class PageForgotPassword extends StatefulWidget {
  const PageForgotPassword({super.key});

  @override
  State<PageForgotPassword> createState() => _PageForgotPasswordState();
}

class _PageForgotPasswordState extends State<PageForgotPassword> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isButtonEnabled = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_validate);
  }

  void _validate() {
    final email = _emailCtrl.text.trim();
    final emailValid = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(email);
    
    setState(() {
      if (email.isNotEmpty && !emailValid) {
        _emailError = 'Format d\'email invalide';
      } else {
        _emailError = null;
      }
      _isButtonEnabled = emailValid;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSendResetEmail() async {
    setState(() => _isLoading = true);
    
    try {
      final email = _emailCtrl.text.trim();
      
      // Utiliser Supabase pour envoyer un vrai email de réinitialisation
      await SupabaseService.resetPassword(email);
      
      // Naviguer vers la page de confirmation
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PageResetEmailSent(email: email),
        ),
      );
    } catch (e) {
      _showSnack('Erreur lors de l\'envoi : $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[400] : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const PageConnexion()),
                    ),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textDark,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // ── Icon ──
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Title ──
              const Center(
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // ── Subtitle ──
              const Center(
                child: Text(
                  'Don\'t worry! It happens. Please enter the\nemail address associated with your account.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textGrey,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),

              // ── Email field ──
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 14, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Enter Your Email',
                  hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
                  prefixIcon: const Icon(
                    Icons.mail_outline_rounded,
                    color: AppColors.textGrey,
                    size: 20,
                  ),
                  errorText: _emailError,
                  errorStyle: const TextStyle(fontSize: 12, color: Colors.red),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── Send Reset Email button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isButtonEnabled && !_isLoading ? _onSendResetEmail : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
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
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Send Reset Email',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Back to login link ──
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const PageConnexion()),
                  ),
                  child: const Text(
                    'Back to Login',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
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
