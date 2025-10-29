import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const TinyBrowserApp());
}

class TinyBrowserApp extends StatelessWidget {
  const TinyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiny Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BrowserScreen(),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://www.google.com');
  bool _canGoBack = false;
  bool _canGoForward = false;
  int _progress = 0; // 0-100

  final Map<String, String> _userAgentOptions = {
    'Default': '',
    'Chrome Desktop':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
    'Safari on iPhone':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1',
  };
  String _currentUserAgent = 'Default';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgentOptions[_currentUserAgent])
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageFinished: (url) async {
            final back = await _controller.canGoBack();
            final fwd = await _controller.canGoForward();
            setState(() {
              _canGoBack = back;
              _canGoForward = fwd;
              _progress = 100;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlCtrl.text));
  }

  void _showUserAgentDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Customize User Agent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _userAgentOptions.keys.map((String key) {
              return ListTile(
                title: Text(key),
                leading: Radio<String>(
                  value: key,
                  groupValue: _currentUserAgent,
                  onChanged: (String? value) {
                    setState(() {
                      _currentUserAgent = value!;
                      _controller.setUserAgent(_userAgentOptions[value]);
                      _controller.reload();
                    });
                    Navigator.of(context).pop();
                  },
                ),
                onTap: () {
                  setState(() {
                    _currentUserAgent = key;
                    _controller.setUserAgent(_userAgentOptions[key]);
                    _controller.reload();
                  });
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFromField() async {
    var input = _urlCtrl.text.trim();
    if (input.isEmpty) return;
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://$input'; // default to https to avoid cleartext issues
    }
    final uri = Uri.tryParse(input);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await _controller.loadRequest(uri);
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _progress = 0);
    } else {
      if (kDebugMode) debugPrint('Invalid URL: $input');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: SafeArea(
            bottom: false,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              child: TextField(
                controller: _urlCtrl,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _loadFromField(),
                decoration: InputDecoration(
                  hintText: 'Enter URL',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _canGoBack
                  ? () async {
                      await _controller.goBack();
                    }
                  : null,
              tooltip: 'Back',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _canGoForward
                  ? () async {
                      await _controller.goForward();
                    }
                  : null,
              tooltip: 'Forward',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _controller.reload();
              },
              tooltip: 'Reload',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_circle_right_outlined),
              onPressed: _loadFromField,
              tooltip: 'Go',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'Customize User Agent') {
                  _showUserAgentDialog();
                }
              },
              itemBuilder: (BuildContext context) {
                return {'Customize User Agent'}.map((String choice) {
                  return PopupMenuItem<String>(
                    value: choice,
                    child: Text(choice),
                  );
                }).toList();
              },
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            Expanded(
              child: SafeArea(
                top: false,
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
