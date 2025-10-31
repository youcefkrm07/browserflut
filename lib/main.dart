import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _BrowserTab {
  _BrowserTab({
    required this.controller,
    required String initialUrl,
  }) : currentUrl = initialUrl;

  final WebViewController controller;
  String currentUrl;
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;

  String get displayTitle {
    final uri = Uri.tryParse(currentUrl);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
    if (currentUrl.isNotEmpty) {
      return currentUrl;
    }
    return 'New tab';
  }
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
  static const String _defaultStartupUrl = 'https://www.google.com';

  final List<_BrowserTab> _tabs = <_BrowserTab>[];
  int _activeTabIndex = 0;
  final TextEditingController _urlCtrl =
      TextEditingController(text: _defaultStartupUrl);
  final FocusNode _addressFocusNode = FocusNode();
  String _homeUrl = _defaultStartupUrl;
  static const int _historyLimit = 50;
  final List<String> _history = <String>[];
  final Set<String> _bookmarks = <String>{};

  final Map<String, String?> _userAgentOptions = {
    'Default': null,
    'Chrome Desktop':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
    'Safari on iPhone':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1',
  };
  static const String _customUserAgentKey = 'Custom';
  String _selectedUserAgentKey = 'Default';
  String? _customUserAgent;

  bool get _hasTabs => _tabs.isNotEmpty;

  _BrowserTab get _activeTab => _tabs[_activeTabIndex];

  WebViewController get _activeController => _activeTab.controller;

  String get _currentUrl => _activeTab.currentUrl;

  bool get _isBookmarked => _bookmarks.contains(_currentUrl);

  int get _activeProgress => _activeTab.progress;

  bool get _activeCanGoBack => _activeTab.canGoBack;

  bool get _activeCanGoForward => _activeTab.canGoForward;

  String? get _resolvedUserAgent {
    if (_selectedUserAgentKey == _customUserAgentKey) {
      final custom = _customUserAgent;
      if (custom != null && custom.isNotEmpty) {
        return custom;
      }
      return null;
    }
    return _userAgentOptions[_selectedUserAgentKey];
  }

  @override
  void initState() {
    super.initState();
    final controller = WebViewController();
    final tab = _BrowserTab(controller: controller, initialUrl: _homeUrl);
    _tabs.add(tab);
    _configureTab(0, _homeUrl);
  }

  void _configureTab(int index, String initialUrl) {
    final tab = _tabs[index];
    tab.currentUrl = initialUrl;
    tab.progress = 0;
    tab.canGoBack = false;
    tab.canGoForward = false;

    tab.controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_resolvedUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => _handleProgress(index, progress),
          onPageStarted: (url) => _handlePageStarted(index, url),
          onPageFinished: (url) => _handlePageFinished(index, url),
          onWebResourceError: (error) =>
              _handleWebResourceError(index, error),
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _handleProgress(int tabIndex, int progress) {
    if (!mounted || tabIndex >= _tabs.length) return;
    setState(() {
      _tabs[tabIndex].progress = progress;
    });
  }

  void _handlePageStarted(int tabIndex, String url) {
    if (!mounted || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    setState(() {
      tab.progress = 0;
      tab.currentUrl = url;
    });
    if (_activeTabIndex == tabIndex &&
        !_addressFocusNode.hasFocus &&
        _urlCtrl.text != url) {
      _urlCtrl.text = url;
    }
  }

  Future<void> _handlePageFinished(int tabIndex, String url) async {
    if (!mounted || tabIndex >= _tabs.length) return;
    final tab = _tabs[tabIndex];
    final controller = tab.controller;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (!mounted || tabIndex >= _tabs.length) return;
    setState(() {
      tab.canGoBack = back;
      tab.canGoForward = forward;
      tab.progress = 100;
      tab.currentUrl = url;
      _history.remove(url);
      _history.insert(0, url);
      if (_history.length > _historyLimit) {
        _history.removeRange(_historyLimit, _history.length);
      }
    });
    if (_activeTabIndex == tabIndex &&
        !_addressFocusNode.hasFocus &&
        _urlCtrl.text != url) {
      _urlCtrl.text = url;
    }
  }

  void _handleWebResourceError(int tabIndex, WebResourceError error) {
    if (!mounted) return;
    if (tabIndex < _tabs.length) {
      setState(() {
        _tabs[tabIndex].progress = 100;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.description)),
    );
  }

  void _switchToTab(int index) {
    if (index == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = index;
    });
    if (!_addressFocusNode.hasFocus) {
      _urlCtrl.text = _tabs[index].currentUrl;
    }
  }

  void _addNewTab({String? initialUrl}) {
    final url = initialUrl ?? _homeUrl;
    final controller = WebViewController();
    final tab = _BrowserTab(controller: controller, initialUrl: url);
    final newIndex = _tabs.length;
    _tabs.add(tab);
    _configureTab(newIndex, url);
    setState(() {
      _activeTabIndex = newIndex;
    });
    if (!_addressFocusNode.hasFocus) {
      _urlCtrl.text = url;
    }
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    final wasActive = index == _activeTabIndex;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
        return;
      }
      if (wasActive) {
        _activeTabIndex = index >= _tabs.length ? _tabs.length - 1 : index;
      } else if (index < _activeTabIndex) {
        _activeTabIndex -= 1;
      }
    });
    if (_hasTabs && !_addressFocusNode.hasFocus) {
      _urlCtrl.text = _currentUrl;
    }
  }

  bool _isHttpScheme(String? scheme) => scheme == 'http' || scheme == 'https';

  Uri _buildSearchUri(String query) {
    return Uri.https('duckduckgo.com', '/', {'q': query});
  }

  Future<void> _loadUri(Uri uri) async {
    if (!_hasTabs) return;
    final tab = _activeTab;
    await tab.controller.loadRequest(uri);
    if (!mounted) return;
    setState(() {
      tab.progress = 0;
      tab.currentUrl = uri.toString();
      tab.canGoBack = false;
      tab.canGoForward = false;
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
      } else {
        _bookmarks.add(_currentUrl);
      }
    });
    final message = _bookmarks.contains(_currentUrl)
        ? 'Added to bookmarks.'
        : 'Removed from bookmarks.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  Future<void> _applyUserAgent({
    required String key,
    String? value,
  }) async {
    final String? resolved =
        key == _customUserAgentKey ? value : _userAgentOptions[key];
    setState(() {
      _selectedUserAgentKey = key;
      if (key == _customUserAgentKey) {
        _customUserAgent = value;
      }
    });

    await Future.wait(
      _tabs.map((tab) => tab.controller.setUserAgent(resolved)),
    );

    if (mounted && _hasTabs) {
      await _activeController.reload();
    }
  }

  void _showUserAgentDialog() {
    final customCtrl = TextEditingController(text: _customUserAgent ?? '');
    var selection = _selectedUserAgentKey;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Customize User Agent'),
          content: StatefulBuilder(
            builder: (ctx, setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._userAgentOptions.entries.map(
                      (entry) => RadioListTile<String>(
                        title: Text(entry.key),
                        value: entry.key,
                        groupValue: selection,
                        onChanged: (value) {
                          if (value == null) return;
                          setStateDialog(() {
                            selection = value;
                          });
                        },
                      ),
                    ),
                    const Divider(),
                    RadioListTile<String>(
                      value: _customUserAgentKey,
                      groupValue: selection,
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() {
                          selection = value;
                        });
                      },
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Custom user agent'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: customCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Enter user agent',
                              border: OutlineInputBorder(),
                            ),
                            minLines: 1,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (selection == _customUserAgentKey) {
                  final value = customCtrl.text.trim();
                  await _applyUserAgent(
                    key: _customUserAgentKey,
                    value: value.isEmpty ? null : value,
                  );
                } else {
                  await _applyUserAgent(
                    key: selection,
                    value: _userAgentOptions[selection],
                  );
                }
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ).then((_) => customCtrl.dispose());
  }

  Widget _buildTabStrip() {
    if (_tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final isActive = index == _activeTabIndex;
                  final label = '${index + 1}. ${tab.displayTitle}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: tab.currentUrl,
                      child: InputChip(
                        label: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        showCheckmark: false,
                        selected: isActive,
                        selectedColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        onPressed: () => _switchToTab(index),
                        onDeleted: _tabs.length > 1
                            ? () => _closeTab(index)
                            : null,
                        deleteIcon: _tabs.length > 1
                            ? const Icon(Icons.close, size: 18)
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New tab',
            onPressed: () => _addNewTab(),
          ),
        ],
      ),
    );
  }

  void _exitApp() {
    try {
      SystemNavigator.pop();
    } catch (_) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTabs = _hasTabs;
    final showProgress = hasTabs && _activeProgress < 100;

    return PopScope(
      canPop: !hasTabs || !_activeCanGoBack,
      onPopInvoked: (didPop) async {
        if (!hasTabs) return;
        if (didPop) return;
        if (await _activeController.canGoBack()) {
          await _activeController.goBack();
        } else if (mounted) {
          Navigator.of(context).maybePop();
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
              onPressed: _activeCanGoBack
                  ? () async {
                      await _activeController.goBack();
                    }
                  : null,
              tooltip: 'Back',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _activeCanGoForward
                  ? () async {
                      await _activeController.goForward();
                    }
                  : null,
              tooltip: 'Forward',
            ),
            IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _loadHome(),
              tooltip: 'Home',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _activeController.reload();
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
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => _addNewTab(),
              tooltip: 'New Tab',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_circle_right_outlined),
              onPressed: () => _loadFromField(),
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
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: _exitApp,
              tooltip: 'Exit',
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            _buildTabStrip(),
            if (showProgress)
              LinearProgressIndicator(value: _activeProgress / 100),
            Expanded(
              child: SafeArea(
                top: false,
                child: hasTabs
                    ? WebViewWidget(controller: _activeController)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
