import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const TinyBrowserApp());
}

enum _BrowserMenuAction {
  customizeUserAgent,
  showBookmarks,
  showHistory,
  setHome,
  clearHistory,
  clearBookmarks,
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
  final FocusNode _addressFocusNode = FocusNode();
  bool _canGoBack = false;
  bool _canGoForward = false;
  int _progress = 0; // 0-100
  String _currentUrl = 'https://www.google.com';
  String _homeUrl = 'https://www.google.com';
  static const int _historyLimit = 50;
  final List<String> _history = <String>[];
  final Set<String> _bookmarks = <String>{};
  bool _isBookmarked = false;

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
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _progress = 0;
              _currentUrl = url;
              _isBookmarked = _bookmarks.contains(url);
            });
            if (!_addressFocusNode.hasFocus && _urlCtrl.text != url) {
              _urlCtrl.text = url;
            }
          },
          onPageFinished: (url) async {
            final back = await _controller.canGoBack();
            final fwd = await _controller.canGoForward();
            if (!mounted) return;
            setState(() {
              _canGoBack = back;
              _canGoForward = fwd;
              _progress = 100;
              _currentUrl = url;
              _isBookmarked = _bookmarks.contains(url);
              _history.remove(url);
              _history.insert(0, url);
              if (_history.length > _historyLimit) {
                _history.removeRange(_historyLimit, _history.length);
              }
            });
            if (!_addressFocusNode.hasFocus && _urlCtrl.text != url) {
              _urlCtrl.text = url;
            }
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.description)),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl));
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
              final isSelected = _currentUserAgent == key;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(key),
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
    _addressFocusNode.dispose();
    super.dispose();
  }

  bool _isHttpScheme(String? scheme) => scheme == 'http' || scheme == 'https';

  Uri _buildSearchUri(String query) {
    return Uri.https('duckduckgo.com', '/', {'q': query});
  }

  Future<void> _loadUri(Uri uri) async {
    await _controller.loadRequest(uri);
    if (!mounted) return;
    setState(() {
      _progress = 0;
      _currentUrl = uri.toString();
      _isBookmarked = _bookmarks.contains(_currentUrl);
    });
    if (!_addressFocusNode.hasFocus) {
      _urlCtrl.text = uri.toString();
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _loadFromField() async {
    var input = _urlCtrl.text.trim();
    if (input.isEmpty) return;
    final directUri = Uri.tryParse(input);
    if (directUri != null && _isHttpScheme(directUri.scheme)) {
      await _loadUri(directUri);
      return;
    }

    final prefixedUri = Uri.tryParse('https://$input');
    if (prefixedUri != null && prefixedUri.host.isNotEmpty) {
      await _loadUri(prefixedUri);
      return;
    }

    final searchUri = _buildSearchUri(input);
    await _loadUri(searchUri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Searching for "$input"')),
    );
  }

  Future<void> _loadHome() async {
    final uri = Uri.tryParse(_homeUrl);
    if (uri != null && _isHttpScheme(uri.scheme)) {
      await _loadUri(uri);
    }
  }

  void _setCurrentAsHome() {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null || !_isHttpScheme(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot set non-HTTP(S) page as home.')),
      );
      return;
    }
    setState(() {
      _homeUrl = _currentUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home page updated.')),
    );
  }

  void _toggleBookmark() {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null || !_isHttpScheme(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only HTTP(S) pages can be bookmarked.')),
      );
      return;
    }
    setState(() {
      if (_bookmarks.contains(_currentUrl)) {
        _bookmarks.remove(_currentUrl);
        _isBookmarked = false;
      } else {
        _bookmarks.add(_currentUrl);
        _isBookmarked = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isBookmarked ? 'Added to bookmarks.' : 'Removed from bookmarks.',
        ),
      ),
    );
  }

  void _showBookmarksSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final bookmarks = _bookmarks.toList()..sort();
        if (bookmarks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('No bookmarks yet.'),
            ),
          );
        }
        return ListView.separated(
          itemCount: bookmarks.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final url = bookmarks[index];
            return ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                final uri = Uri.tryParse(url);
                if (uri != null && _isHttpScheme(uri.scheme)) {
                  _loadUri(uri);
                }
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove bookmark',
                onPressed: () {
                  setState(() {
                    _bookmarks.remove(url);
                    _isBookmarked = _bookmarks.contains(_currentUrl);
                  });
                  Navigator.of(ctx).pop();
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        if (_history.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('History is empty.'),
            ),
          );
        }
        return ListView.separated(
          itemCount: _history.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final url = _history[index];
            final host = Uri.tryParse(url)?.host ?? url;
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                final uri = Uri.tryParse(url);
                if (uri != null && _isHttpScheme(uri.scheme)) {
                  _loadUri(uri);
                }
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove from history',
                onPressed: () {
                  setState(() {
                    _history.removeAt(index);
                  });
                  Navigator.of(ctx).pop();
                },
              ),
            );
          },
        );
      },
    );
  }

  void _clearHistory() {
    if (_history.isEmpty) return;
    setState(() {
      _history.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History cleared.')),
    );
  }

  void _clearBookmarks() {
    if (_bookmarks.isEmpty) return;
    setState(() {
      _bookmarks.clear();
      _isBookmarked = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bookmarks cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        if (!mounted) return;
        Navigator.of(context).maybePop();
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
                focusNode: _addressFocusNode,
                textInputAction: TextInputAction.go,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
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
              icon: const Icon(Icons.home_outlined),
              onPressed: _loadHome,
              tooltip: 'Home',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _controller.reload();
              },
              tooltip: 'Reload',
            ),
            IconButton(
              icon: Icon(
                _isBookmarked ? Icons.star : Icons.star_border,
                color: _isBookmarked ? Colors.amber : null,
              ),
              onPressed: _toggleBookmark,
              tooltip: _isBookmarked ? 'Remove bookmark' : 'Add bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_circle_right_outlined),
              onPressed: _loadFromField,
              tooltip: 'Go',
            ),
            PopupMenuButton<_BrowserMenuAction>(
              onSelected: (value) {
                switch (value) {
                  case _BrowserMenuAction.customizeUserAgent:
                    _showUserAgentDialog();
                    break;
                  case _BrowserMenuAction.showBookmarks:
                    _showBookmarksSheet();
                    break;
                  case _BrowserMenuAction.showHistory:
                    _showHistorySheet();
                    break;
                  case _BrowserMenuAction.setHome:
                    _setCurrentAsHome();
                    break;
                  case _BrowserMenuAction.clearHistory:
                    _clearHistory();
                    break;
                  case _BrowserMenuAction.clearBookmarks:
                    _clearBookmarks();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.customizeUserAgent,
                  child: Text('Customize User Agent'),
                ),
                const PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.showBookmarks,
                  child: Text('Bookmarks'),
                ),
                const PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.showHistory,
                  child: Text('History'),
                ),
                const PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.setHome,
                  child: Text('Set Current As Home'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.clearHistory,
                  enabled: _history.isNotEmpty,
                  child: const Text('Clear History'),
                ),
                PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.clearBookmarks,
                  enabled: _bookmarks.isNotEmpty,
                  child: const Text('Clear Bookmarks'),
                ),
              ],
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
