import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/utils/input_sanitizer.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_error_dialog.dart';
import '../widgets/social_sign_in_button.dart';

/// Registration page for new users.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  late AnimationController _animationController;
  late List<Animation<double>> _fadeAnimations;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimations = List.generate(
      8,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.08,
            0.5 + (index * 0.08),
            curve: Curves.easeOut,
          ),
        ),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _authStateListener,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(Routes.login),
          ),
        ),
        body: SafeArea(
          bottom: true,
          child: Center(
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + MediaQuery.of(context).padding.bottom,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      FadeTransition(
                        opacity: _fadeAnimations[0],
                        child: _buildHeader(context),
                      ),
                      const SizedBox(height: 32),

                      // Display name field
                      FadeTransition(
                        opacity: _fadeAnimations[1],
                        child: _buildNameField(),
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      FadeTransition(
                        opacity: _fadeAnimations[2],
                        child: _buildEmailField(),
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      FadeTransition(
                        opacity: _fadeAnimations[3],
                        child: _buildPasswordField(),
                      ),
                      const SizedBox(height: 16),

                      // Confirm password field
                      FadeTransition(
                        opacity: _fadeAnimations[4],
                        child: _buildConfirmPasswordField(),
                      ),
                      const SizedBox(height: 16),

                      // Terms checkbox
                      FadeTransition(
                        opacity: _fadeAnimations[5],
                        child: _buildTermsCheckbox(context),
                      ),
                      const SizedBox(height: 24),

                      // Register button
                      FadeTransition(
                        opacity: _fadeAnimations[6],
                        child: _buildRegisterButton(),
                      ),
                      const SizedBox(height: 24),

                      // Divider
                      FadeTransition(
                        opacity: _fadeAnimations[7],
                        child: _buildDivider(context),
                      ),
                      const SizedBox(height: 24),

                      // Google sign up
                      FadeTransition(
                        opacity: _fadeAnimations[7],
                        child: SocialSignInButton(
                          onPressed: _onGoogleSignUp,
                          icon: 'G',
                          label: 'Sign up with Google',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go(Routes.login),
                            child: const Text('Sign In'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create Account',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Join Radius and connect with people nearby',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Display Name',
        prefixIcon: Icon(Icons.person_outlined),
        hintText: 'How others will see you',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your name';
        }
        // Sanitize and check the result
        final sanitized = InputSanitizer.sanitizeDisplayName(value);
        if (sanitized == null) {
          return 'Please enter a valid name';
        }
        if (sanitized.length < 2) {
          return 'Name must be at least 2 characters';
        }
        if (sanitized.length > 50) {
          return 'Name must be 50 characters or less';
        }
        // Check for suspicious patterns
        if (RegExp(r'[<>{}|\\^~\[\]`]').hasMatch(value)) {
          return 'Name contains invalid characters';
        }
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        // RFC 5322 compliant email regex - allows +, longer TLDs, and more special chars
        final emailRegex = RegExp(
          r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$",
        );
        if (!emailRegex.hasMatch(value)) {
          return 'Please enter a valid email';
        }
        // Additional length check to prevent DoS via very long strings
        if (value.length > 254) {
          return 'Email address is too long';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        helperText: 'At least 8 characters with letters and numbers',
      ),
      validator: _validatePassword,
    );
  }

  /// Validates password strength.
  ///
  /// Requires:
  /// - At least 8 characters
  /// - At least one letter
  /// - At least one number
  /// - No more than 128 characters (prevent DoS)
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (value.length > 128) {
      return 'Password is too long';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return 'Password must contain at least one letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    // Check for common weak passwords
    final lowerValue = value.toLowerCase();
    const weakPasswords = [
      'password',
      '12345678',
      'qwerty12',
      'letmein1',
      'welcome1',
      'admin123',
      'abc12345',
      'password1',
      'iloveyou1',
      'sunshine1',
    ];
    if (weakPasswords.any((weak) => lowerValue.contains(weak))) {
      return 'Please choose a stronger password';
    }
    return null;
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _onRegister(),
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your password';
        }
        if (value != _passwordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }

  Widget _buildTermsCheckbox(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: _acceptedTerms,
          onChanged: (value) {
            setState(() => _acceptedTerms = value ?? false);
          },
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _acceptedTerms = !_acceptedTerms);
            },
            child: Text.rich(
              TextSpan(
                text: 'I agree to the ',
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: 'Terms of Service',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButton() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;

        return FilledButton(
          onPressed: isLoading ? null : _onRegister,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create Account'),
          ),
        );
      },
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }

  void _authStateListener(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      context.go(Routes.home);
    } else if (state is AuthAwaitingEmailVerification) {
      context.go(Routes.emailVerification);
    } else if (state is AuthError) {
      showAuthErrorDialog(context, state.message);
    }
  }

  void _onRegister() {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please accept the Terms of Service and Privacy Policy'),
        ),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      // Sanitize inputs before sending to the bloc
      final sanitizedEmail =
          InputSanitizer.sanitizeEmail(_emailController.text);
      final sanitizedDisplayName =
          InputSanitizer.sanitizeDisplayName(_nameController.text);

      if (sanitizedEmail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid email')),
        );
        return;
      }

      context.read<AuthBloc>().add(
            AuthRegisterRequested(
              email: sanitizedEmail,
              password: _passwordController.text,
              displayName: sanitizedDisplayName,
            ),
          );
    }
  }

  void _onGoogleSignUp() {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please accept the Terms of Service and Privacy Policy'),
        ),
      );
      return;
    }

    context.read<AuthBloc>().add(const AuthSignInWithGoogleRequested());
  }
}
