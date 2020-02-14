import Foundation
import Capacitor
import AVFoundation
import CallKit
import PushKit
import TwilioVoice
import UserNotifications


private let kTwimlParamTo = "To"

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CapacitorTwilioVoiceSDK)
public class CapacitorTwilioVoiceSDK: CAPPlugin {
    
  // Callback for the Javascript plugin delegate, used for events
    private var callback: String?
    // Push registry for APNS VOIP
    private var voipPushRegistry: PKPushRegistry?
    private var incomingPushCompletionCallback: (() -> Void)?
    // Current call (can be nil)
    private var call: TVOCall?
    // Current call invite (can be nil)
    private var callInvite: TVOCallInvite?
    // Device Token from Apple Push Notification Service for VOIP
    private var pushDeviceToken: String?
    // Access Token from Twilio
    private var accessToken: String?
    // Outgoing call params
    private var outgoingCallParams: [AnyHashable : Any]?
    // Configure whether or not to use CallKit via the plist
    // This is a variable from plugin installation (ENABLE_CALLKIT)
    private var enableCallKit = false
    // Configure whether or not to mask the incoming phone number for privacy via the plist
    // This is a variable from plugin installation (MASK_INCOMING_PHONE_NUMBER)
    private var maskIncomingPhoneNumber = false
    // Call Kit member variables
    private var callKitProvider: CXProvider?
    private var callKitCallController: CXCallController?
    private var callKitCompletionCallback: ((Bool) -> Void)?
    // Audio Properties
    private var ringtonePlayer: AVAudioPlayer?
    private var audioDevice: TVODefaultAudioDevice?
}

class TwilioVoicePlugin {
    func pluginInitialize() {
        
        
        print("Initializing plugin")
        let debugTwilioPreference: String? = Bundle.main.object(forInfoDictionaryKey: "TVPEnableDebugging")?.uppercased()
        if (debugTwilioPreference == "YES") || (debugTwilioPreference == "TRUE") {
            TwilioVoice.logLevel = TVOLogLevelDebug
        } else {
            TwilioVoice.logLevel = TVOLogLevelOff
        }
        
        // read in Enable CallKit preference
        let enableCallKitPreference = Bundle.main.object(forInfoDictionaryKey: "TVPEnableCallKit")?.uppercased()
        if (enableCallKitPreference == "YES") || (enableCallKitPreference == "TRUE") {
            enableCallKit = true
            audioDevice = TVODefaultAudioDevice()
            TwilioVoice.audioDevice = audioDevice
        } else {
            enableCallKit = false
        }
        
        // read in MASK_INCOMING_PHONE_NUMBER preference
        let enableMaskIncomingPhoneNumberPreference = Bundle.main.object(forInfoDictionaryKey: "TVPMaskIncomingPhoneNumber")?.uppercased()
        if (enableMaskIncomingPhoneNumberPreference == "YES") || (enableMaskIncomingPhoneNumberPreference == "TRUE") {
            maskIncomingPhoneNumber = true
        } else {
            maskIncomingPhoneNumber = false
        }
        
        if !enableCallKit {
            //ask for notification support
            let center = UNUserNotificationCenter.current()
            let options: UNAuthorizationOptions = .alert + .sound
            
            center.requestAuthorization(options: options, completionHandler: { granted, error in
                if !granted {
                    print("Notifications not granted")
                }
            })
            
            // initialize ringtone player
            let ringtoneURL = Bundle.main.url(forResource: "ringing.wav", withExtension: nil)
            if ringtoneURL != nil {
                var error: Error? = nil
                do {
                    if let ringtoneURL = ringtoneURL {
                        ringtonePlayer = try AVAudioPlayer(contentsOf: ringtoneURL)
                    }
                } catch {
                }
                if error != nil {
                    print("Error initializing ring tone player: \(error?.localizedDescription ?? "")")
                } else {
                    //looping ring
                    ringtonePlayer.numberOfLoops = -1
                    ringtonePlayer.prepareToPlay()
                }
            }
        }
        
    }
    
    
    func initialize(withAccessToken command: CDVInvokedUrlCommand?) {
        print("Initializing with an access token")

        // retain this command as the callback to use for raising Twilio events
        callback = command?.callbackId

        accessToken = command?.arguments[0] as? Data
        if accessToken != nil {

            // initialize VOIP Push Registry
            voipPushRegistry = PKPushRegistry(queue: DispatchQueue.main)
            voipPushRegistry.delegate = self
            voipPushRegistry.desiredPushTypes = Set<AnyHashable>([.voIP])

            if enableCallKit {
                // initialize CallKit (based on Twilio ObjCVoiceCallKitQuickstart)
                let incomingCallAppName = Bundle.main.object(forInfoDictionaryKey: "TVPIncomingCallAppName") as? String
                let configuration = CXProviderConfiguration(localizedName: incomingCallAppName ?? "")
                configuration.maximumCallGroups = 1
                configuration.maximumCallsPerCallGroup = 1
                let callkitIcon = UIImage(named: "logo.png")
                configuration.iconTemplateImageData =
                configuration.ringtoneSound = "traditionalring.mp3"

                callKitProvider = CXProvider(configuration: configuration)
                callKitProvider.setDelegate(self, queue: nil)

                callKitCallController = CXCallController()
            }

            javascriptCallback("onclientinitialized")
        }

    }

    
    
    func call(_ command: CDVInvokedUrlCommand?) {
        if command?.arguments.count() ?? 0 > 0 {
            accessToken = command?.arguments[0] as? Data
            if command?.arguments.count() ?? 0 > 1 {
                outgoingCallParams = command?.arguments[1]
            }

            if call && call.state == TVOCallStateConnected {
                performEndCallAction(withUUID: call.uuid)
            } else {
                if enableCallKit {
                    let uuid = UUID()
                    let incomingCallAppName = Bundle.main.object(forInfoDictionaryKey: "TVPIncomingCallAppName") as? String
                    performStartCallAction(with: uuid, handle: incomingCallAppName)
                } else {
                    print("Making call to with params \(outgoingCallParams)")
                    let connectOptions = TVOConnectOptions(accessToken: accessToken, block: { builder in
                            builder?.params = [
                            kTwimlParamTo: self.outgoingCallParams["To"]
                            ]
                        })
                    call = TwilioVoice.connect(with: connectOptions, delegate: self)
                    outgoingCallParams = nil
                }
            }
        }
    }

    func sendDigits(_ command: CDVInvokedUrlCommand?) {
        if command?.arguments.count() ?? 0 > 0 {
            call.sendDigits(command?.arguments[0] as? CDVInvokedUrlCommand)
        }
    }

    
    
    
    func disconnect(_ command: CDVInvokedUrlCommand?) {
        if callInvite && call && call.state == TVOCallStateRinging {
            callInvite.reject()
            callInvite = nil
        } else if call {
            call.disconnect()
        }
    }

    func acceptCallInvite(_ command: CDVInvokedUrlCommand?) {
        if callInvite {
            callInvite.accept(withDelegate: self)
        }
        if ringtonePlayer.isPlaying() {
            //pause ringtone
            ringtonePlayer.pause()
        }
    }

    func rejectCallInvite(_ command: CDVInvokedUrlCommand?) {
        if callInvite {
            callInvite.reject()
        }
        if ringtonePlayer.isPlaying() {
            //pause ringtone
            ringtonePlayer.pause()
        }
    }

    
    // MARK: - AVAudioSession
    func toggleAudioRoute(_ toSpeaker: Bool) {
        // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
        let audioDevice = self.audioDevice ?? TwilioVoice.audioDevice as? TVODefaultAudioDevice
        audioDevice?.block = {
            // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
            kTVODefaultAVAudioSessionConfigurationBlock()

            // Overwrite the audio route
            let session = AVAudioSession.sharedInstance()
            var error: Error? = nil
            if toSpeaker {
                do {
                    try session.overrideOutputAudioPort(AVAudioSessionPortOverrideSpeaker)

                    if try session.overrideOutputAudioPort(AVAudioSessionPortOverrideSpeaker) == nil {
                        print("Unable to reroute audio: \(error?.localizedDescription ?? "")")
                    }
                } catch {
                    print("Unable to reroute audio: \(error?.localizedDescription ?? "")")
                }
            } else {
                do {
                    try session.overrideOutputAudioPort(AVAudioSessionPortOverrideNone)

                    if try session.overrideOutputAudioPort(AVAudioSessionPortOverrideNone) == nil {
                        print("Unable to reroute audio: \(error?.localizedDescription ?? "")")
                    }
                } catch {
                    print("Unable to reroute audio: \(error?.localizedDescription ?? "")")
                }
            }
        }
        audioDevice?.block()
    }

    func setSpeaker(_ command: CDVInvokedUrlCommand?) {
        let mode = command?.arguments[0] as? String
        if mode?.isEqual("on") ?? false {
            toggleAudioRoute(true)
        } else {
            toggleAudioRoute(false)
        }
    }

    
    func muteCall(_ command: CDVInvokedUrlCommand?) {
        if call {
            call.muted = true
        }
    }

    func unmuteCall(_ command: CDVInvokedUrlCommand?) {
        if call {
            call.muted = false
        }
    }

    func isCallMuted(_ command: CDVInvokedUrlCommand?) {
        if call {
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAsBool: call.muted)
            commandDelegate.send(result, callbackId: command?.callbackId)
        } else {
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAsBool: false)
            commandDelegate.send(result, callbackId: command?.callbackId)
        }
    }

    
    // MARK: PKPushRegistryDelegate methods
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        if type.isEqual(toString: PKPushType.voIP) {
            pushDeviceToken = credentials.token.description
            print("Updating push device token for VOIP: \(pushDeviceToken)")
            TwilioVoice.register(withAccessToken: accessToken, deviceToken: pushDeviceToken) { error in
                if error != nil {
                    print("Error registering Voice Client for VOIP Push: \(error?.localizedDescription ?? "")")
                } else {
                    print("Registered Voice Client for VOIP Push")
                }
            }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        if type.isEqual(toString: PKPushType.voIP) {
            print("Invalidating push device token for VOIP: \(pushDeviceToken)")
            TwilioVoice.unregister(withAccessToken: accessToken, deviceToken: pushDeviceToken) { error in
                if error != nil {
                    print("Error unregistering Voice Client for VOIP Push: \(error?.localizedDescription ?? "")")
                } else {
                    print("Unegistered Voice Client for VOIP Push")
                }
                self.pushDeviceToken = nil
            }
        }
    }

    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        if type.isEqual(toString: PKPushType.voIP) {
            print("Received Incoming Push Payload for VOIP: \(payload.dictionaryPayload)")
            TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:")

        // Save for later when the notification is properly handled.
        incomingPushCompletionCallback = completion

        if type.isEqual(toString: PKPushType.voIP) {
            if !TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self) {
                print("This is not a valid Twilio Voice notification.")
            }
        }
    }

    func incomingPushHandled() {
        if incomingPushCompletionCallback {
            incomingPushCompletionCallback()
            incomingPushCompletionCallback = nil
        }
    }

    // MARK: TVONotificationDelegate
    func callInviteReceived(_ callInvite: TVOCallInvite?) {
        handleCallInviteReceived(callInvite)
    }

    
    
    func cancelledCallInviteReceived(_ cancelledCallInvite: TVOCancelledCallInvite) {
        print("cancelledCallInviteReceived:")

        incomingPushHandled()

        if !callInvite || !(callInvite.callSid == cancelledCallInvite.callSid) {
            print("No matching pending CallInvite. Ignoring the Cancelled CallInvite")
            return
        }
        if enableCallKit {
            performEndCallAction(withUUID: callInvite.uuid)
        } else {
            cancelNotification()
            //pause ringtone
            ringtonePlayer.pause()
        }

        callInvite = nil
        incomingPushHandled()
        javascriptCallback("oncallinvitecanceled")
    }

    
    
    func handleCallInviteReceived(_ callInvite: TVOCallInvite?) {
        if let uuid = callInvite?.uuid {
            print("Call Invite Received: \(uuid)")
        }
        // Two simlutaneous callInvites or calls are not supported by Twilio and cause an error
        // if the user attempts to answer the second call invite through CallKit.
        // Rather than surface the second invite, just reject it which will most likely
        // result in the second invite going to voicemail
        if self.callInvite == nil && call == nil {
            self.callInvite = callInvite
            var callInviteProperties: [StringLiteralConvertible : UnknownType?]? = nil
            if let from = callInvite?.from, let to = callInvite?.to, let callSid = callInvite?.callSid {
                callInviteProperties = [
                "from": from,
                "to": to,
                "callSid": callSid
            ]
            }
            if enableCallKit {
                reportIncomingCall(from: (maskIncomingPhoneNumber ? "Unknown" : callInvite?.from), withUUID: callInvite?.uuid)
            } else {
                showNotification((maskIncomingPhoneNumber ? "Unknown" : callInvite?.from))
                //play ringtone
                ringtonePlayer.play()
            }

            javascriptCallback("oncallinvitereceived", withArguments: callInviteProperties)
        } else {
            incomingPushHandled()
            if let uuid = callInvite?.uuid {
                print("Call Invite Received During Call. Ignoring: \(uuid)")
            }
        }
    }

    
    
    func notificationError(_ error: Error?) {
        print("Twilio Voice Notification Error: \(error?.localizedDescription ?? "")")
        javascriptErrorback(error)
    }

    // MARK: TVOCallDelegate
    func callDidConnect(_ call: TVOCall?) {
        if let description = call?.description() {
            print("Call Did Connect: \(description)")
        }
        self.call = call

        if !enableCallKit {
            cancelNotification()
            if ringtonePlayer.isPlaying() {
                //pause ringtone
                ringtonePlayer.pause()
            }
        } else {
            callKitCompletionCallback(true)
            callKitCompletionCallback = nil
        }

        var callProperties: [AnyHashable : Any] = [:]
        if call?.from != nil {
            if let from = call?.from {
                callProperties["from"] = from
            }
        }
        if call?.to != nil {
            if let to = call?.to {
                callProperties["to"] = to
            }
        }
        if call?.sid != nil {
            if let sid = call?.sid {
                callProperties["callSid"] = sid
            }
        }
        callProperties["isMuted"] = NSNumber(value: call?.isMuted ?? false)
        let callState = string(fromCallState: call?.state)
        if callState != "" {
            callProperties["state"] = callState
        }
        javascriptCallback("oncalldidconnect", withArguments: callProperties)
    }

    
    func call(_ call: TVOCall?, didFailToConnectWithError error: Error?) {
        if let description = call?.description() {
            print("Call Did Fail with Error: \(description), \(error?.localizedDescription ?? "")")
        }
        if enableCallKit {
            callKitCompletionCallback(false)
        }
        callDisconnected(call)
        javascriptErrorback(error)
    }

    func call(_ call: TVOCall?, didDisconnectWithError error: Error?) {
        if error != nil {
            if let error = error {
                print("Call failed: \(error)")
            }
            javascriptErrorback(error)
        } else {
            print("Call disconnected")
        }

        callDisconnected(call)
    }

    func callDisconnected(_ call: TVOCall?) {
        if let description = call?.description() {
            print("Call Did Disconnect: \(description)")
        }

        // Call Kit Integration
        if enableCallKit {
            performEndCallAction(withUUID: call?.uuid)
        }

        self.call = nil
        callKitCompletionCallback = nil
    }

    // MARK: Conversion methods for the plugin
    func string(from state: TVOCallState) -> String? {
        if state == TVOCallStateRinging {
            return "ringing"
        } else if state == TVOCallStateConnected {
            return "connected"
        } else if state == TVOCallStateConnecting {
            return "connecting"
        } else if state == TVOCallStateDisconnected {
            return "disconnected"
        }

        return nil
    }
    
    
    // MARK: Cordova Integration methods for the plugin Delegate - from TCPlugin.m/Stevie Graham
    func javascriptCallback(_ event: String?, withArguments arguments: [AnyHashable : Any]?) {
        var options: [AnyHashable : Any]? = nil
        if let arguments = arguments {
            options = [
            "callback" : event ?? "",
            "arguments" : arguments
        ]
        }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAsDictionary: options)
        result.keepCallbackAsBool = true

        commandDelegate.send(result, callbackId: callback)
    }

    func javascriptCallback(_ event: String?) {
        javascriptCallback(event, withArguments: nil)
    }

    func javascriptErrorback(_ error: Error?) {
        let object = [
            "message" : error?.localizedDescription
        ]
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAsDictionary: object)
        result.keepCallbackAsBool = true

        commandDelegate.send(result, callbackId: callback)
    }

    
    // MARK: - Local Notification methods used if CallKit isn't enabled
    func showNotification(_ alertBody: String?) {
        let center = UNUserNotificationCenter.current()

        center.removeAllPendingNotificationRequests()


        let content = UNMutableNotificationContent()
        content.sound = UNNotificationSound(named: UNNotificationSoundName("ringing.wav"))
        content.title = "Answer"
        content.body = alertBody ?? ""


        let request = UNNotificationRequest(identifier: "IncomingCall", content: content, trigger: nil)

        center.add(request, withCompletionHandler: { error in
            if error != nil {
                print("Error adding local notification for incoming call: \(error?.localizedDescription ?? "")")
            }
        })

    }

    func cancelNotification() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    
    
    // MARK: - CXProviderDelegate - based on Twilio Voice with CallKit Quickstart ObjC
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        if call {
            print("Sending Digits: \(action.digits)")
            call.sendDigits(action.digits)
        } else {
            print("No current call")
        }

    }

    
    // All CallKit Integration Code comes from https://github.com/twilio/voice-callkit-quickstart-objc/blob/master/ObjCVoiceCallKitQuickstart/ViewController.m

    func providerDidReset(_ provider: CXProvider) {
        print("providerDidReset:")
        audioDevice.enabled = true
    }

    func providerDidBegin(_ provider: CXProvider) {
        print("providerDidBegin:")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("provider:didActivateAudioSession:")
        audioDevice.enabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("provider:didDeactivateAudioSession:")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("provider:timedOutPerformingAction:")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("provider:performStartCallAction:")

        audioDevice.enabled = false
        audioDevice.block()

        callKitProvider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        weak var weakSelf = self
        performVoiceCall(with: action.callUUID, client: nil) { success in
            let strongSelf = weakSelf
            if success {
                strongSelf?.callKitProvider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("provider:performAnswerCallAction:")

        assert(callInvite.uuid == action.callUUID, "We only support one Invite at a time.")

        audioDevice.enabled = false
        audioDevice.block()

        performAnswerVoiceCall(with: action.callUUID) { success in
            if success {
                action.fulfill()
            } else {
                action.fail()
            }
        }

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("provider:performEndCallAction:")

        if callInvite {
            callInvite.reject()
            callInvite = nil
            javascriptCallback("oncallinvitecanceled")
        } else if call {
            call.disconnect()
        }

        audioDevice.enabled = true
        action.fulfill()
    }

    
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        if call && call.state == TVOCallStateConnected {
            call.isOnHold = action.isOnHold
            action.fulfill()
        } else {
            action.fail()
        }
    }

    // MARK: - CallKit Actions
    func performStartCallAction(with uuid: UUID?, handle: String?) {
        if uuid == nil || handle == nil {
            return
        }

        let callHandle = CXHandle(type: .generic, value: handle ?? "")
        var startCallAction: CXStartCallAction? = nil
        if let uuid = uuid {
            startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        }
        var transaction: CXTransaction? = nil
        if let startCallAction = startCallAction {
            transaction = CXTransaction(action: startCallAction)
        }

        if let transaction = transaction {
            callKitCallController.request(transaction) { error in
                if error != nil {
                    print("StartCallAction transaction request failed: \(error?.localizedDescription ?? "")")
                } else {
                    print("StartCallAction transaction request successful")

                    let callUpdate = CXCallUpdate()
                    callUpdate.remoteHandle = callHandle
                    callUpdate.supportsDTMF = true
                    callUpdate.supportsHolding = true
                    callUpdate.supportsGrouping = false
                    callUpdate.supportsUngrouping = false
                    callUpdate.hasVideo = false

                    if let uuid = uuid {
                        self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
                    }
                }
            }
        }
    }

    
    func reportIncomingCall(from: String?, with uuid: UUID?) {
        let callHandle = CXHandle(type: .generic, value: from ?? "")

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false

        if let uuid = uuid {
            callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
                if error == nil {
                    print("Incoming call successfully reported.")
                } else {
                    print("Failed to report incoming call successfully: \(error?.localizedDescription ?? "").")
                }
            }
        }
    }

    func performEndCallAction(with uuid: UUID?) {
        var endCallAction: CXEndCallAction? = nil
        if let uuid = uuid {
            endCallAction = CXEndCallAction(call: uuid)
        }
        var transaction: CXTransaction? = nil
        if let endCallAction = endCallAction {
            transaction = CXTransaction(action: endCallAction)
        }

        if let transaction = transaction {
            callKitCallController.request(transaction) { error in
                if error != nil {
                    print("EndCallAction transaction request failed: \(error?.localizedDescription ?? "")")
                } else {
                    print("EndCallAction transaction request successful")
                }
            }
        }
    }

    func performVoiceCall(with uuid: UUID?, client: String?, completion completionHandler: @escaping (_ success: Bool) -> Void) {

        weak var weakSelf = self
        let connectOptions = TVOConnectOptions(accessToken: accessToken, block: { builder in
                let strongSelf = weakSelf
                if let outgoingCallParams = strongSelf?.outgoingCallParams["To"] {
                    builder?.params = [
                    kTwimlParamTo: outgoingCallParams
                    ]
                }
                builder?.uuid = uuid
            })
        call = TwilioVoice.connect(with: connectOptions, delegate: self)
        callKitCompletionCallback = completionHandler
    }

    
    
    func performAnswerVoiceCall(with uuid: UUID?, completion completionHandler: @escaping (_ success: Bool) -> Void) {
        weak var weakSelf = self
        let acceptOptions = TVOAcceptOptions(callInvite: callInvite, block: { builder in
                let strongSelf = weakSelf
                builder?.uuid = strongSelf?.callInvite.uuid
            })

        call = callInvite.accept(with: acceptOptions, delegate: self)

        if !call {
            completionHandler(false)
        } else {
            callKitCompletionCallback = completionHandler
        }

        callInvite = nil
        incomingPushHandled()
    }

    
}
