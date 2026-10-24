import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ElBenchNativeGlass") else { return }
    let channel = FlutterMethodChannel(name: "elbench/native-glass", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "isSupported" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 26.0, *) {
        result(true)
      } else {
        result(false)
      }
    }
    registrar.register(ElBenchGlassFactory(messenger: registrar.messenger()), withId: "elbench/native-glass")
    FlutterMethodChannel(name: "elbench/native-share", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "share", let args = call.arguments as? [String: Any],
          let text = args["url"] as? String, let url = URL(string: text),
          ["http", "https"].contains(url.scheme ?? "") else {
          result(FlutterMethodNotImplemented)
          return
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        guard var presenter = windows.first(where: { $0.isKeyWindow })?.rootViewController else {
          result(false)
          return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.setValue(args["title"] as? String ?? "ElBench", forKey: "subject")
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 70, width: 1, height: 1)
        presenter.present(sheet, animated: !UIAccessibility.isReduceMotionEnabled) { result(true) }
      }
  }
}

private final class ElBenchGlassFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let options = args as? [String: Any] ?? [:]
    return ElBenchGlassView(frame: frame, viewId: viewId, messenger: messenger, options: options)
  }
}

private final class ElBenchGlassView: NSObject, FlutterPlatformView {
  private let glass: ElBenchGlassBackground

  private let channel: FlutterMethodChannel
  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, options: [String: Any]) {
    glass = ElBenchGlassBackground(frame: frame)
    channel = FlutterMethodChannel(name: "elbench/native-glass/\(viewId)", binaryMessenger: messenger)
    super.init()
    glass.apply(options, animated: false)
    glass.configure()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let options = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.glass.apply(options, animated: true)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { glass }
}

private final class ElBenchGlassBackground: UIView {
  private let material = UIVisualEffectView(effect: nil)
  var requestedRadius: Double?
  var fallbackColor: UIColor?
  private let selection = UIVisualEffectView(effect: nil)
  private var selectionIndex: Int?
  private var selectionCount = 0
  private var dragPosition: Double?
  private var verticalInset: CGFloat = 0
  private var isDark = false
  private var reduceMotion = false
  private var configured = false
  private var selectionAnimator: UIViewPropertyAnimator?
  private var previousBarBounds = CGRect.zero

  private var barBounds: CGRect {
    let inset = min(verticalInset, bounds.height / 3)
    return bounds.insetBy(dx: 0, dy: inset)
  }

  func apply(_ options: [String: Any], animated: Bool) {
    let wasDark = isDark
    let dark = options["dark"] as? Bool ?? (traitCollection.userInterfaceStyle == .dark)
    isDark = dark
    requestedRadius = options["cornerRadius"] as? Double
    let nextInset = CGFloat((options["verticalInset"] as? NSNumber)?.doubleValue ?? 0)
    let insetChanged = nextInset != verticalInset
    verticalInset = nextInset
    if let argb = (options["background"] as? NSNumber)?.uint32Value {
      fallbackColor = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
        green: CGFloat((argb >> 8) & 255) / 255, blue: CGFloat(argb & 255) / 255,
        alpha: CGFloat((argb >> 24) & 255) / 255)
    }
    overrideUserInterfaceStyle = dark ? .dark : .light
    let motionChanged = reduceMotion != (options["reduceMotion"] as? Bool ?? false)
    reduceMotion = options["reduceMotion"] as? Bool ?? false
    let index = options["selectionIndex"] as? Int
    let count = options["selectionCount"] as? Int ?? 0
    let drag = (options["dragPosition"] as? NSNumber)?.doubleValue
    let wasDragging = dragPosition != nil
    let dragChanged = drag != dragPosition
    let changed = index != selectionIndex || count != selectionCount || insetChanged
    selectionIndex = index
    selectionCount = count
    dragPosition = drag
    if configured {
      if insetChanged { setNeedsLayout() }
      // Keep both native materials alive for the lifetime of the surface.
      // Replacing their effects at every drag boundary reinitializes refraction
      // and causes a flash just as the lens starts tracking the finger.
      if wasDark != dark { updateMaterial() }
      if let drag = drag {
        if dragChanged || changed || motionChanged || !wasDragging {
          positionDragSelection(drag, newlyStarted: !wasDragging)
        }
      } else if wasDragging || changed || motionChanged {
        positionSelection(animated: (animated || wasDragging) && !reduceMotion)
      }
    }
  }

  private func positionDragSelection(_ position: Double, newlyStarted: Bool) {
    let bar = barBounds
    guard selectionCount > 0, bar.width > 20, bar.height > 0 else {
      stopSelectionAnimation()
      selection.isHidden = true
      return
    }
    selection.isHidden = false
    let clamped = max(0.0, min(Double(max(0, selectionCount - 1)), position))
    let slot = (bar.width - 20) / CGFloat(selectionCount)
    let midX = 10 + slot * (CGFloat(clamped) + 0.5)
    let midY = bar.midY
    // Keep the contact lens close to the selected slot; a very large bubble
    // obscures neighbouring controls and magnifies the jump on release.
    let dragWidth = min(bar.width - 8, max(slot * 1.18, 56))
    let dragHeight = max(0, bar.height - 4)
    let dragSize = CGSize(width: dragWidth, height: dragHeight)
    if newlyStarted {
      stopSelectionAnimation()
    }
    if reduceMotion || UIAccessibility.isReduceMotionEnabled {
      stopSelectionAnimation()
      selection.bounds = CGRect(origin: .zero, size: dragSize)
      selection.center = CGPoint(x: midX, y: midY)
      selection.layer.cornerRadius = dragHeight / 2
      return
    }
    // Lock horizontal tracking 1:1 with the finger so there is zero trailing lag.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    selection.center = CGPoint(x: midX, y: midY)
    CATransaction.commit()
    if newlyStarted {
      animateSelection(duration: 0.24, damping: 0.86) { [weak self] in
        self?.selection.bounds = CGRect(origin: .zero, size: dragSize)
        self?.selection.layer.cornerRadius = dragHeight / 2
      }
    } else if selection.bounds.size != dragSize {
      // A resize or feature update can change the slot width while a finger is
      // stationary. Cancel the old size target before applying new geometry.
      stopSelectionAnimation()
      selection.bounds = CGRect(origin: .zero, size: dragSize)
      selection.layer.cornerRadius = dragHeight / 2
    }
  }

  private func positionSelection(animated: Bool) {
    let bar = barBounds
    guard selectionCount > 0, let index = selectionIndex, index >= 0, index < selectionCount,
      bar.width > 20, bar.height > 12 else {
      stopSelectionAnimation()
      selection.isHidden = true
      return
    }
    let wasHidden = selection.isHidden
    selection.isHidden = false
    let slot = (bar.width - 20) / CGFloat(selectionCount)
    let target = CGRect(
      x: 10 + slot * CGFloat(index) + (slot - slot * 1.06) / 2,
      y: bar.minY + 6,
      width: slot * 1.06,
      height: max(0, bar.height - 12)
    )
    let targetCorner = target.height / 2
    guard animated && !wasHidden && !reduceMotion && !UIAccessibility.isReduceMotionEnabled && bar.width > 0 else {
      stopSelectionAnimation()
      selection.bounds = CGRect(origin: .zero, size: target.size)
      selection.center = CGPoint(x: target.midX, y: target.midY)
      selection.layer.cornerRadius = targetCorner
      return
    }
    // One interruptible spring owns all lens geometry. Rapid retaps and a drag
    // beginning mid-glide resume from the visible position rather than the
    // previous animation's destination, without chained completion animations.
    stopSelectionAnimation()
    animateSelection(duration: 0.34, damping: 0.86) { [weak self] in
      self?.selection.center = CGPoint(x: target.midX, y: target.midY)
      self?.selection.bounds = CGRect(origin: .zero, size: target.size)
      self?.selection.layer.cornerRadius = targetCorner
    }
  }

  private func stopSelectionAnimation() {
    guard let animator = selectionAnimator else { return }
    selectionAnimator = nil
    animator.stopAnimation(false)
    animator.finishAnimation(at: .current)
  }

  private func animateSelection(duration: TimeInterval, damping: CGFloat,
    changes: @escaping () -> Void) {
    let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: damping,
      animations: changes)
    selectionAnimator = animator
    animator.addCompletion { [weak self, weak animator] _ in
      guard let self = self, self.selectionAnimator === animator else { return }
      self.selectionAnimator = nil
    }
    animator.startAnimation()
  }

  func configure() {
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    backgroundColor = .clear
    clipsToBounds = false
    layer.cornerCurve = .continuous
    addSubview(material)
    addSubview(selection)
    selection.isHidden = true
    selection.layer.cornerCurve = .continuous
    configured = true
    if #available(iOS 26.0, *) {
      material.clipsToBounds = false
      selection.clipsToBounds = false
      material.cornerConfiguration = .capsule(maximumRadius: requestedRadius)
      selection.cornerConfiguration = .capsule()
    } else {
      material.clipsToBounds = true
      selection.clipsToBounds = true
    }
    NotificationCenter.default.addObserver(self, selector: #selector(updateMaterial),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    updateMaterial()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let bar = barBounds
    let geometryChanged = previousBarBounds != bar
    previousBarBounds = bar
    layer.cornerRadius = min(CGFloat(requestedRadius ?? Double(bar.height / 2)), bar.height / 2)
    material.frame = bar
    material.layer.cornerRadius = layer.cornerRadius
    if #available(iOS 26.0, *) {
      material.cornerConfiguration = .capsule(maximumRadius: requestedRadius)
      selection.cornerConfiguration = .capsule()
    } else {
      material.clipsToBounds = true
    }
    if geometryChanged { stopSelectionAnimation() }
    if let drag = dragPosition {
      positionDragSelection(drag, newlyStarted: false)
    } else if selectionAnimator == nil {
      positionSelection(animated: false)
    }
  }

  @objc private func motionPreferenceChanged() {
    if UIAccessibility.isReduceMotionEnabled {
      stopSelectionAnimation()
      if let drag = dragPosition {
        positionDragSelection(drag, newlyStarted: false)
      } else {
        positionSelection(animated: false)
      }
    }
  }

  @objc private func updateMaterial() {
    let dark = isDark
    let fallback = dark ? UIColor(white: 10.0 / 255.0, alpha: 0.97) : UIColor.white.withAlphaComponent(0.97)
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = true
      material.backgroundColor = .clear
      material.effect = effect

      // Let UIKit render the selection lens, including its natural highlights.
      let lens = UIGlassEffect(style: .clear)
      lens.isInteractive = true
      selection.backgroundColor = .clear
      selection.effect = lens
      selection.layer.borderWidth = 0
      selection.layer.borderColor = nil
    } else {
      material.effect = nil
      material.backgroundColor = fallbackColor ?? fallback
      selection.effect = nil
      selection.backgroundColor = dark
        ? UIColor(white: 0.20, alpha: 0.64)
        : UIColor(white: 0.16, alpha: 0.10)
    }
  }

  deinit {
    selectionAnimator?.stopAnimation(true)
    NotificationCenter.default.removeObserver(self)
  }
}
