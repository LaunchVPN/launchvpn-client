import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        let binaryMessenger = engineBridge.applicationRegistrar.messenger()
        let flutterApi = AppFlutterApi(binaryMessenger: binaryMessenger)
        BridgeHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: AppHostApi(flutterApi: flutterApi))
        FileExportHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: FileExportApi())
        let backupApi = AppleBackupApi()
        BackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)
        AppleBackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)
        AppleWidgetHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: AppleWidgetApi(flutterApi: flutterApi))
        TesterHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: TesterApi())
        TunnelStopsHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: TunnelStopsApi())
        
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }
}
