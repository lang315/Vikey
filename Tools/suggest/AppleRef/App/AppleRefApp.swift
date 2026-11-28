import UIKit

// The text Apple's keyboard types into, for the suggestion benchmark (Tools/suggest). Each tap on Next puts
// the next case's text before the cursor (set by the app, so the keyboard doesn't learn it) and shows the
// letters the UI test is to type: "<id>\t<letters>", or "done".
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = RefController()
        window!.makeKeyAndVisible()
        return true
    }
}

final class RefController: UIViewController {
    private let text = UITextView()
    private let nextButton = UIButton(type: .system)
    private let letters = UILabel()
    private var cases: [[String]] = []   // [id, text before the cursor, letters to type]
    private var index = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if let path = ProcessInfo.processInfo.environment["CASES"], let data = FileManager.default.contents(atPath: path),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
            cases = list.map { $0.map { "\($0)" } }   // tap maps add numbers: only the first two fields are read
        }
        nextButton.setTitle("Next", for: .normal)
        nextButton.accessibilityIdentifier = "appleref.next"
        nextButton.addTarget(self, action: #selector(loadNext), for: .touchUpInside)
        letters.accessibilityIdentifier = "letters"
        letters.text = "\(cases.count) cases"
        text.accessibilityIdentifier = "text"
        text.font = .systemFont(ofSize: 17)
        for v in [nextButton, letters, text] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            nextButton.topAnchor.constraint(equalTo: g.topAnchor, constant: 8), nextButton.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            letters.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor), letters.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            text.topAnchor.constraint(equalTo: nextButton.bottomAnchor, constant: 8), text.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16), text.heightAnchor.constraint(equalToConstant: 160),
        ])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        text.becomeFirstResponder()
    }
    @objc private func loadNext() {
        index += 1
        guard index < cases.count else { letters.text = "done"; return }
        let c = cases[index]
        text.text = c[1]
        text.selectedRange = NSRange(location: (c[1] as NSString).length, length: 0)
        letters.text = "\(c[0])\t\(c.count > 2 ? c[2] : "")"
    }
}
