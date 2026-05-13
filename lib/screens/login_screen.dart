import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // YENİ: Firebase servisimizi ekledik
import 'patient_main_screen.dart';
import 'caregiver_main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();

  // YENİ: FirebaseService örneğini oluşturduk
  final FirebaseService _firebaseService = FirebaseService();

  bool isLoginMode = true; 
  String _selectedRole = 'patient'; 
  bool isLoading = false; // YENİ: Yüklenme durumu için

  // YENİ: Veritabanı işlemleri asenkron olduğu için fonksiyonu async yaptık
  Future<void> _processAuth() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String name = _nameController.text.trim();
    String surname = _surnameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage("Please enter your email and password.");
      return;
    }

    if (!isLoginMode && (name.isEmpty || surname.isEmpty)) {
      _showMessage("Please enter your first and last name.");
      return;
    }

    setState(() {
      isLoading = true; // Start loading animation when button is pressed
    });

    try {
      if (isLoginMode) {
        // --- GİRİŞ YAPMA (FIREBASE) ---
        final userData = await _firebaseService.loginUser(email, password);
        
        if (userData != null) {
          String role = userData['role'] ?? 'patient';
          String userName = userData['name'] ?? 'User';
          
          _showMessage("Welcome, $userName");
          
          if (!mounted) return;
          if (role == 'patient') {
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => PatientMainScreen(currentUserEmail: email))
            );
          } else {
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => CaregiverMainScreen(currentUserEmail: email))
            );
          }
        } else {
          _showMessage("Incorrect email or password!");
        }
      } else {
        // --- SIGN UP (FIREBASE) ---
        bool success = await _firebaseService.registerUser(
          email: email,
          password: password,
          role: _selectedRole,
          name: name,
          surname: surname,
        );

        if (success) {
          _showMessage("Registration successful! You can now log in.");
          setState(() {
            isLoginMode = true;
            _nameController.clear();
            _surnameController.clear();
            _passwordController.clear();
          });
        } else {
          _showMessage("This email is already registered.");
        }
      }
    } catch (e) {
      _showMessage("An error occurred: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false; // İşlem bitince yüklenme animasyonunu durdur
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color mainColor = const Color(0xFF2E406E);
    Color secondaryColor = const Color(0xFF7FB060);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo vs.
              Image.asset('assets/images/logo.png', height: 170),
              const SizedBox(height: 10),
              Text(
                isLoginMode ? 'Log In' : 'Create a New Account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: mainColor),
              ),
              const SizedBox(height: 30),
              
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              if (!isLoginMode) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _surnameController,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                const Text("Account Type:", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Patient'),
                        value: 'patient',
                        groupValue: _selectedRole,
                        activeColor: mainColor,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setState(() { _selectedRole = value!; });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Caregiver'),
                        value: 'caregiver',
                        groupValue: _selectedRole,
                        activeColor: secondaryColor,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setState(() { _selectedRole = value!; });
                        },
                      ),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 24),
              
              // YENİ: Yükleniyor durumuna göre butonu değiştir
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _processAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLoginMode ? mainColor : secondaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isLoginMode ? 'Log In' : 'Sign Up',
                        style: const TextStyle(fontSize: 18, color: Colors.white),
                      ),
                ),
              ),
              
              TextButton(
                onPressed: isLoading ? null : () {
                  setState(() {
                    isLoginMode = !isLoginMode;
                  });
                },
                child: Text(
                  isLoginMode 
                    ? "Don't have an account? Sign up" 
                    : 'Back to login',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}