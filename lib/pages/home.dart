import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _message = "Hi pal";
  final List<String> _messages = ["Stop touching me", "I said stop", "Don't make me angry"];
  int _messageIndex = 0;

  void _talk() {
    setState(() {
      _message = _messages[_messageIndex];
      _messageIndex = (_messageIndex + 1) % _messages.length;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _talk,
              child:
                Stack(
                  children: [
                    ClipRect(
                      clipper: _CustomClipper(),
                      child: Lottie.asset(
                        'assets/Daemon.json',
                        width: 500,
                        height: 500,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(
                      top: 300, // Replace 20% with a pixel value or calculate dynamically
                      right: 200,
                      child:
                        Text(
                        _message,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        ),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    // Crop to the top-left quarter, for example
    return Rect.fromLTWH(0, 0, size.width, size.height / 100 * 80);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}