import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _started = false;

  void _start() {
    setState(() {
      _started = !_started;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
          color: Color.fromARGB(255, 0, 0, 0),
          fontSize: 20,
        ),
      ),
      body: Center(
        child:
            GestureDetector(
              onTap: _start,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final animWidth = constraints.maxWidth * 0.2;
                  final animHeight = animWidth;

                  final size = constraints.constrain(Size(animWidth, animHeight));

                  return AnimatedAlign(
                    alignment: _started ? Alignment.center : Alignment.topLeft,
                    curve: Curves.easeInOut,
                    duration: const Duration(milliseconds: 500),
                    child:
                        SizedBox(
                          width: size.width,
                          height: size.height,
                          child: SvgPicture.asset(
                            'assets/Sun.svg',
                            fit: BoxFit.contain,
                          ),
                        ),
                  );
                },
              ),
            ),
      ),
    );
  }
}