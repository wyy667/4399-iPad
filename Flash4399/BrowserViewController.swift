import UIKit
import WebKit

final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let home = URL(string: "https://www.4399.com/")!
    private let assets = RuntimeAssets()
    private let gameAssets = GameAssets()
    private var webView: WKWebView!
    private var loadError: String?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        gameAssets.onFailure = { [weak self] message in self?.loadError = message }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.allowsInlineMediaPlayback = true
        // Keep audio user-initiated; Ruffle displays a play/unmute affordance.
        config.userContentController.addScriptMessageHandler(assets, contentWorld: .page, name: "runtimeAsset")
        config.userContentController.addScriptMessageHandler(gameAssets, contentWorld: .page, name: "gameAsset")
        do {
            for file in ["bootstrap.js", "Ruffle/ruffle.js", "input.js"] {
                let source = try RuntimeAssets.resource(file)
                config.userContentController.addUserScript(WKUserScript(
                    source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            }
        } catch {
            loadError = "播放器资源缺失，请重新构建包含 WebAssets 的 App。\n\(error.localizedDescription)"
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let menu = UITapGestureRecognizer(target: self, action: #selector(showMenu))
        menu.numberOfTouchesRequired = 3
        menu.cancelsTouchesInView = false
        view.addGestureRecognizer(menu)
        NotificationCenter.default.addObserver(self, selector: #selector(releaseInput),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        installCompatibilityRulesAndOpenHome()
    }

    private func installCompatibilityRulesAndOpenHome() {
        do {
            let rules = try RuntimeAssets.resource("content-rules.json")
            // The legacy detector destroys the game after only 600 ms, before
            // bundled WASM can compile. Ruffle supplies its own load/error UI.
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "Flash4399-LegacyPluginDetection-v1", encodedContentRuleList: rules
            ) { [weak self] list, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let list { self.webView.configuration.userContentController.add(list) }
                    self.webView.load(URLRequest(url: self.home))
                    if let error { self.showError("旧插件检测适配未加载：\(error.localizedDescription)") }
                }
            }
        } catch { showError("兼容规则资源缺失：\(error.localizedDescription)") }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(title: "浏览器菜单", action: #selector(showMenu), input: ",", modifierFlags: .command)]
    }

    @objc private func releaseInput() {
        webView.evaluateJavaScript("window.postMessage({type:'flash4399-release-input'}, '*')", completionHandler: nil)
    }

    @objc private func showMenu() {
        guard presentedViewController == nil else { return }
        releaseInput()
        let menu = UIAlertController(title: "4399", message: loadError ?? "三指轻点或 ⌘, 打开此菜单", preferredStyle: .actionSheet)
        if let loadError {
            menu.addAction(UIAlertAction(title: "复制加载错误", style: .default) { _ in UIPasteboard.general.string = loadError })
        }
        if webView.canGoBack {
            menu.addAction(UIAlertAction(title: "返回上一页", style: .default) { [weak self] _ in self?.webView.goBack() })
        }
        menu.addAction(UIAlertAction(title: "4399 首页", style: .default) { [weak self] _ in
            guard let self else { return }
            self.webView.load(URLRequest(url: self.home))
        })
        menu.addAction(UIAlertAction(title: "重新加载", style: .default) { [weak self] _ in self?.webView.reload() })
        menu.addAction(UIAlertAction(title: "播放器自检", style: .default) { [weak self] _ in
            guard let self else { return }
            do {
                self.webView.loadHTMLString(try RuntimeAssets.resource("selftest.html"), baseURL: URL(string: "https://selftest.invalid/"))
            } catch { self.showError("自检页面缺失") }
        })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.popoverPresentationController?.sourceView = view
        menu.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(menu, animated: true)
    }

    private func showError(_ message: String) {
        loadError = message
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "加载提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.webView.reload() })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        // No handoff to downloader apps or external executable URL schemes.
        decisionHandler(["http", "https", "about", "data", "blob"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let scheme = navigationAction.request.url?.scheme, ["http", "https"].contains(scheme) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadError = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError("网页进程已退出，可能是游戏占用内存过多。可以重新加载或返回首页。")
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
