import Flutter
import UIKit
import Photos

public let kSchemePrefix = "ShareMedia"
public let kUserDefaultsKey = "ShareKey"
public let kUserDefaultsMessageKey = "ShareMessageKey"
public let kAppGroupIdKey = "AppGroupId"

public class SwiftReceiveSharingIntentPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let kMessagesChannel = "receive_sharing_intent/messages"
    static let kEventsChannelMedia = "receive_sharing_intent/events-media"
    
    private var initialMedia: [SharedMediaFile]?
    private var latestMedia: [SharedMediaFile]?
    
    private var eventSinkMedia: FlutterEventSink?
    
    // Singleton is required for calling functions directly from AppDelegate
    // - it is required if the developer is using also another library, which requires to call "application(_:open:options:)"
    // -> see Example app
    public static let instance = SwiftReceiveSharingIntentPlugin()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kMessagesChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)
        
        registrar.addApplicationDelegate(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        
        switch call.method {
        case "getInitialMedia":
            result(toJson(data: self.initialMedia))
        case "readMedia":
            readMedia()
            result(toJson(data: self.latestMedia))
        case "reset":
            self.initialMedia = nil
            self.latestMedia = nil
            clearSharedData()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func readMedia() -> Bool {
        let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
        let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)

        let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)

        if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
            do {
                let sharedArray = decode(data: json)

                let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap { item -> SharedMediaFile? in
                    let path: String?
                    if item.type == .text || item.type == .url {
                        path = item.path
                    } else {
                        path = getAbsolutePath(for: item.path)
                    }
                    
                    guard let validPath = path else { return nil }
                    
                    return SharedMediaFile(
                        path: validPath,
                        mimeType: item.mimeType,
                        thumbnail: getAbsolutePath(for: item.thumbnail),
                        description: message,
                        duration: item.duration,
                        type: item.type
                    )
                }

                latestMedia = sharedMediaFiles

                if let eventSink = eventSinkMedia {
                    eventSink(toJson(data: latestMedia))
                }

                return true
            } catch {
                return false
            }
        } else {
            return false
        }
    }
    
    // By Adding bundle id to prefix, we'll ensure that the correct application will be opened
    // - found the issue while developing multiple applications using this library, after "application(_:open:options:)" is called, the first app using this librabry (first app by bundle id alphabetically) is opened
    public func hasMatchingSchemePrefix(url: URL?) -> Bool {
        if let url = url, let appDomain = Bundle.main.bundleIdentifier {
            return url.absoluteString.hasPrefix("\(kSchemePrefix)-\(appDomain)")
        }
        return false
    }
    
    // This is the function called on app startup with a shared link if the app had been closed already.
    // It is called as the launch process is finishing and the app is almost ready to run.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if the app is not able to.
    // If the URL does not include the module's prefix, we must return true since while our module cannot handle the link, other modules might be and returning false can prevent
    // them from getting the chance to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        var handled = false

        if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
            if (hasMatchingSchemePrefix(url: url)) {
                handled = handleUrl(url: url, setInitialData: true)
            }
            return true
        } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] {
            // Handle multiple URLs shared in
            for key in activityDictionary.keys {
                if let userActivity = activityDictionary[key] as? NSUserActivity {
                    if let url = userActivity.webpageURL {
                        if (hasMatchingSchemePrefix(url: url)) {
                            handled = handleUrl(url: url, setInitialData: true)
                            break
                        }
                    }
                }
            }
        }
        // Si aucune URL n'a été traitée ou si aucune URL n'était présente
        // Vérifions les UserDefaults de toute façon pour récupérer les médias partagés
        if !handled {
            log("No URL handled, checking for shared media anyway")
            checkForSharedMedia()
        }
        
        return true
    }
    
    private func checkForSharedMedia() {
        let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
        let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)
                
        let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
        if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
            
            do {
                let sharedArray = decode(data: json)
                let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap { item -> SharedMediaFile? in
                    let path: String?
                    if item.type == .text || item.type == .url {
                        path = item.path
                    } else {
                        path = getAbsolutePath(for: item.path)
                    }
                    
                    guard let validPath = path else { return nil }
                    
                    return SharedMediaFile(
                        path: validPath,
                        mimeType: item.mimeType,
                        thumbnail: getAbsolutePath(for: item.thumbnail),
                        description: message,
                        duration: item.duration,
                        type: item.type
                    )
                }
                
                log("Processed shared media files count: \(sharedMediaFiles.count)")
                latestMedia = sharedMediaFiles
                initialMedia = latestMedia
                
                if let eventSink = eventSinkMedia {
                    eventSink(toJson(data: latestMedia))
                }
            } catch {
                log("Error processing shared media: \(error.localizedDescription)")
            }
        } else {
            log("No shared data found in UserDefaults for key: \(kUserDefaultsKey)")
        }
    }
    
    // This is the function called on resuming the app from a shared link.
    // It handles requests to open a resource by a specified URL. Returning true means that it was handled successfully, false means the attempt to open the resource failed.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we return false to indicate our module's attempt to open the resource failed and others should be allowed to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if (hasMatchingSchemePrefix(url: url)) {
            return handleUrl(url: url, setInitialData: false)
        }
        return false
    }
    
    // This function is called by other modules like Firebase DeepLinks.
    // It tells the delegate that data for continuing an activity is available. Returning true means that our module handled the activity and that others do not have to. Returning false tells
    // iOS that our app did not handle the activity.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we must return false to indicate that this module did not handle the prefix and that other modules should try to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            if (hasMatchingSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
        }
        return false
    }
    
    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
        let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
        let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)
        
        let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
        if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
            let sharedArray = decode(data: json)
            let sharedMediaFiles: [SharedMediaFile] = sharedArray.compactMap { item -> SharedMediaFile? in
                let path: String?
                if item.type == .text || item.type == .url {
                    path = item.path
                } else {
                    path = getAbsolutePath(for: item.path)
                }
                
                guard let validPath = path else { return nil }
                
                return SharedMediaFile(
                    path: validPath,
                    mimeType: item.mimeType,
                    thumbnail: getAbsolutePath(for: item.thumbnail),
                    description: message,
                    duration: item.duration,
                    type: item.type
                )
            }
            latestMedia = sharedMediaFiles
            if(setInitialData) {
                initialMedia = latestMedia
            }
            eventSinkMedia?(toJson(data: latestMedia))
        }
        return true
    }

    private func clearSharedData() {
        let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
        let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)

        log("Clearing shared data from UserDefaults")
        userDefaults?.removeObject(forKey: kUserDefaultsKey)
        userDefaults?.removeObject(forKey: kUserDefaultsMessageKey)
        userDefaults?.synchronize()
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSinkMedia = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSinkMedia = nil
        return nil
    }
    
    private func getAbsolutePath(for identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }
        
        if (identifier.starts(with: "file://") || identifier.starts(with: "/var/mobile/Media") || identifier.starts(with: "/private/var/mobile")) {
            return identifier.replacingOccurrences(of: "file://", with: "")
        }
        
        guard let phAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: .none).firstObject else {
            return nil
        }
        
        let (url, _) = getFullSizeImageURLAndOrientation(for: phAsset)
        return url
        
    }
    
    private func getFullSizeImageURLAndOrientation(for asset: PHAsset)-> (String?, Int) {
        var url: String? = nil
        var orientation: Int = 0
        let semaphore = DispatchSemaphore(value: 0)
        let options2 = PHContentEditingInputRequestOptions()
        options2.isNetworkAccessAllowed = true
        asset.requestContentEditingInput(with: options2){(input, info) in
            orientation = Int(input?.fullSizeImageOrientation ?? 0)
            url = input?.fullSizeImageURL?.path
            semaphore.signal()
        }
        semaphore.wait()
        return (url, orientation)
    }
    
    private func decode(data: Data) -> [SharedMediaFile] {
        let encodedData = try? JSONDecoder().decode([SharedMediaFile].self, from: data)
        return encodedData!
    }
    
    private func toJson(data: [SharedMediaFile]?) -> String? {
        if data == nil {
            return nil
        }
        let encodedData = try? JSONEncoder().encode(data)
        let json = String(data: encodedData!, encoding: .utf8)!
        return json
    }
    
    private func log(_ message: String) {
        print("[ReceiveSharingIntent] \(message)")  // Pour la console de débogage
    }
}


public class SharedMediaFile: Codable {
    public var path: String
    public var mimeType: String?
    public var thumbnail: String?
    public var title: String?
    public var description: String?
    public var duration: Double? // video duration in milliseconds
    public var type: SharedMediaType
    
    
    public init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        title: String?=nil,
        description: String?=nil,
        duration: Double? = nil,
        type: SharedMediaType) {
            self.path = path
            self.mimeType = mimeType
            self.thumbnail = thumbnail
            self.duration = duration
            self.title = title
            self.description = description
            self.type = type
        }
}

public enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
//     case audio
    case file
    case url

    public var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image:
                return UTType.image.identifier
            case .video:
                return UTType.movie.identifier
            case .text:
                return UTType.text.identifier
    //         case .audio:
    //             return UTType.audio.identifier
            case .file:
                return UTType.fileURL.identifier
            case .url:
                return UTType.url.identifier
            }
        }
        switch self {
        case .image:
            return "public.image"
        case .video:
            return "public.movie"
        case .text:
            return "public.text"
//         case .audio:
//             return "public.audio"
        case .file:
            return "public.file-url"
        case .url:
            return "public.url"
        }
    }
}
