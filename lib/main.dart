import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const TinyBrowserApp());
}

class _BrowserTab {
  _BrowserTab({
    required this.id,
    required this.controller,
    required this.urlController,
  }) : currentUrl = urlController.text;

  final int id;
  final WebViewController controller;
  final TextEditingController urlController;
  String currentUrl;
  bool canGoBack = false;
  bool canGoForward = false;
  int progress = 0;
}

enum _BrowserMenuAction {
  customizeUserAgent,
  showBookmarks,
  showHistory,
  setHome,
  clearHistory,
  clearBookmarks,
  exitApp,
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
  final FocusNode _addressFocusNode = FocusNode();
  final TextEditingController _customUserAgentCtrl = TextEditingController();
  final List<_BrowserTab> _tabs = <_BrowserTab>[];
  int _activeTabIndex = 0;
  int _nextTabId = 1;
  String _homeUrl = 'https://www.google.com';
  static const int _historyLimit = 50;
  final List<String> _history = <String>[];
  final Set<String> _bookmarks = <String>{};
  static const String _customUserAgentKey = 'Custom';
  String? _customUserAgent;

  final Map<String, String> _userAgentOptions = {
    'Default': '',
    'Chrome Desktop':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
    'Safari on iPhone':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1',
  };
  String _currentUserAgent = 'Default';

  String? _userAgentFor(String key) {
    if (key == _customUserAgentKey) return _customUserAgent;
    return _userAgentOptions[key];
  }

  _BrowserTab _createTab({String? initialUrl}) {
    final startUrl = (initialUrl?.isNotEmpty ?? false) ? initialUrl! : _homeUrl;
    final urlController = TextEditingController(text: startUrl);
    late final _BrowserTab tab;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgentFor(_currentUserAgent))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              tab.progress = p;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              tab.progress = 0;
              tab.currentUrl = url;
            });
            if (!_addressFocusNode.hasFocus &&
                tab.urlController.text != url &&
                _isTabActive(tab)) {
              tab.urlController.text = url;
            }
          },
          onPageFinished: (url) async {
            final back = await controller.canGoBack();
            final fwd = await controller.canGoForward();
            if (!mounted) return;
            setState(() {
              tab.canGoBack = back;
              tab.canGoForward = fwd;
              tab.progress = 100;
              tab.currentUrl = url;
              _history.remove(url);
              _history.insert(0, url);
              if (_history.length > _historyLimit) {
                _history.removeRange(_historyLimit, _history.length);
              }
            });
            if (!_addressFocusNode.hasFocus &&
                tab.urlController.text != url &&
                _isTabActive(tab)) {
              tab.urlController.text = url;
            }
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.description)),
            );
          },
        ),
      );

    tab = _BrowserTab(
      id: _nextTabId++,
      controller: controller,
      urlController: urlController,
    );
    controller.loadRequest(Uri.parse(startUrl));
    return tab;
  }

  bool _isTabActive(_BrowserTab tab) =>
      _tabs.isNotEmpty && identical(_tabs[_activeTabIndex], tab);

  _BrowserTab get _activeTab => _tabs[_activeTabIndex];

  bool get _isActiveTabBookmarked =>
      _bookmarks.contains(_activeTab.currentUrl);

  @override
  void initState() {
    super.initState();
    final initialTab = _createTab(initialUrl: _homeUrl);
    _tabs.add(initialTab);
  }

  void _openNewTab({String? initialUrl}) {
    final tab = _createTab(initialUrl: initialUrl);
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      _tabs[index].controller.reload();
      return;
    }
    _BrowserTab? removed;
    setState(() {
      removed = _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (index < _activeTabIndex) {
        _activeTabIndex -= 1;
      }
    });
    removed?.urlController.dispose();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _switchToTab(int index) {
    if (index == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = index;
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _tabLabel(int index, _BrowserTab tab) {
    final host = Uri.tryParse(tab.currentUrl)?.host;
    if (host == null || host.isEmpty) {
      return 'Tab ${index + 1}';
    }
    return host;
  }

  Widget _buildTabStrip() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in _tabs.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(_tabLabel(entry.key, entry.value)),
                        selected: entry.key == _activeTabIndex,
                        onPressed: () => _switchToTab(entry.key),
                        onDeleted: _tabs.length > 1
                            ? () => _closeTab(entry.key)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New tab',
            onPressed: () => _openNewTab(),
          ),
        ],
      ),
    );
  }

  void _applyUserAgentToAllTabs(String? userAgent) {
    for (final tab in _tabs) {
      tab.controller.setUserAgent(userAgent);
    }
    _activeTab.controller.reload();
  }

  void _showUserAgentDialog() {
    _customUserAgentCtrl.text = _customUserAgent ?? '';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Customize User Agent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._userAgentOptions.keys.map((String key) {
                final isSelected = _currentUserAgent == key;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(key),
                  onTap: () {
                    final agent = _userAgentFor(key);
                    setState(() {
                      _currentUserAgent = key;
                    });
                    _applyUserAgentToAllTabs(agent);
                    Navigator.of(context).pop();
                  },
                );
              }),
              ListTile(
                leading: Icon(
                  _currentUserAgent == _customUserAgentKey
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _currentUserAgent == _customUserAgentKey
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: const Text('Custom'),
                subtitle: Text(
                  (_customUserAgent?.isNotEmpty ?? false)
                      ? _customUserAgent!
                      : 'Not set',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: _customUserAgent?.isNotEmpty ?? false,
                onTap: (_customUserAgent?.isNotEmpty ?? false)
                    ? () {
                        setState(() {
                          _currentUserAgent = _customUserAgentKey;
                        });
                        _applyUserAgentToAllTabs(_customUserAgent);
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
              const Divider(),
              TextField(
                controller: _customUserAgentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Custom user agent',
                  hintText: 'Paste or type a user agent string',
                ),
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('Apply Custom User Agent'),
                onPressed: () {
                  final value = _customUserAgentCtrl.text.trim();
                  if (value.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a user agent string first.'),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _customUserAgent = value;
                    _currentUserAgent = _customUserAgentKey;
                  });
                  _applyUserAgentToAllTabs(value);
                  Navigator.of(context).pop();
                },
              ),
            ],
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
    for (final tab in _tabs) {
      tab.urlController.dispose();
    }
    _addressFocusNode.dispose();
    _customUserAgentCtrl.dispose();
    super.dispose();
  }

  bool _isHttpScheme(String? scheme) => scheme == 'http' || scheme == 'https';

  Uri _buildSearchUri(String query) {
    return Uri.https('duckduckgo.com', '/', {'q': query});
  }

  Future<void> _loadUri(Uri uri) async {
    final tab = _activeTab;
    await tab.controller.loadRequest(uri);
    if (!mounted) return;
    final url = uri.toString();
    setState(() {
      tab.progress = 0;
      tab.currentUrl = url;
    });
    if (!_addressFocusNode.hasFocus) {
      tab.urlController.text = url;
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _loadFromField() async {
    final tab = _activeTab;
    var input = tab.urlController.text.trim();
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
    final uri = Uri.tryParse(_activeTab.currentUrl);
    if (uri == null || !_isHttpScheme(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot set non-HTTP(S) page as home.')),
      );
      return;
    }
    setState(() {
      _homeUrl = _activeTab.currentUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home page updated.')),
    );
  }

  void _toggleBookmark() {
    final url = _activeTab.currentUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || !_isHttpScheme(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only HTTP(S) pages can be bookmarked.')),
      );
      return;
    }
    setState(() {
      if (_bookmarks.contains(url)) {
        _bookmarks.remove(url);
      } else {
        _bookmarks.add(url);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _bookmarks.contains(url)
              ? 'Added to bookmarks.'
              : 'Removed from bookmarks.',
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
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bookmarks cleared.')),
    );
  }

  Future<void> _exitApp() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exit is not supported in the browser.')),
      );
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final isBookmarked = _isActiveTabBookmarked;
    return PopScope(
      canPop: !activeTab.canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final tab = _activeTab;
        if (await tab.controller.canGoBack()) {
          await tab.controller.goBack();
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
                controller: activeTab.urlController,
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
              onPressed: activeTab.canGoBack
                  ? () async {
                      await activeTab.controller.goBack();
                    }
                  : null,
              tooltip: 'Back',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: activeTab.canGoForward
                  ? () async {
                      await activeTab.controller.goForward();
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
                await activeTab.controller.reload();
              },
              tooltip: 'Reload',
            ),
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.star : Icons.star_border,
                color: isBookmarked ? Colors.amber : null,
              ),
              onPressed: _toggleBookmark,
              tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_circle_right_outlined),
              onPressed: _loadFromField,
              tooltip: 'Go',
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: _exitApp,
              tooltip: 'Exit',
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
                  case _BrowserMenuAction.exitApp:
                    _exitApp();
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
                const PopupMenuDivider(),
                const PopupMenuItem<_BrowserMenuAction>(
                  value: _BrowserMenuAction.exitApp,
                  child: Text('Exit'),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            _buildTabStrip(),
            if (activeTab.progress < 100)
              LinearProgressIndicator(value: activeTab.progress / 100),
            Expanded(
              child: SafeArea(
                top: false,
                child: WebViewWidget(controller: activeTab.controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
