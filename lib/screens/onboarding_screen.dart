import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'image': 'assets/onboarding_0.png',
      'title': 'Welcome to LinkUp',
      'desc': 'Organize your life, your way.',
    },
    {
      'image': 'assets/onboarding_1.png',
      'title': 'Add Events Easily',
      'desc': 'Tap, create, and manage all your events in seconds.',
    },
    {
      'image': 'assets/onboarding_2.png',
      'title': 'Collaborate & Share',
      'desc': 'Share calendars and allow others to edit together.',
    },
  ];

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenTutorial', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/calendarHome');
  }

  void _handleNext() {
    if (_currentIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _onboardingData.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final item = _onboardingData[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        item['image']!,
                        height: MediaQuery.of(context).size.height * 0.45,
                        width: MediaQuery.of(context).size.width * 0.7,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        item['title']!,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item['desc']!,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_onboardingData.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: _currentIndex == index ? 20 : 8,
                decoration: BoxDecoration(
                  color: _currentIndex == index ? Colors.deepPurple : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          // Button
         Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220), // limit width
                child: ElevatedButton.icon(
                  icon: Icon(
                    _currentIndex == _onboardingData.length - 1
                        ? Icons.check
                        : Icons.arrow_forward,
                    color: Colors.white,
                  ),
                  label: Text(
                    _currentIndex == _onboardingData.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.white, // <-- fix this
                    ),
                  ),
                  onPressed: _handleNext,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
