import Foundation
import Capacitor
import UIKit
import AVFoundation
import PushKit
import CallKit
import TwilioVoice

let baseURLString = ""
// If your token server is written in PHP, accessTokenEndpoint needs .php extension at the end. For example : /accessToken.php
let accessTokenEndpoint = "/accessToken"
let identity = "alice"
let twimlParamTo = "to"


@objc(CapacitorTwilioVoiceSDK)
public class CapacitorTwilioVoiceSDK: CAPPlugin, UIViewController, PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, CXProviderDelegate, UITextFieldDelegate, AVAudioPlayerDelegate  {
 
        
        var deviceTokenString: String? = ""
        
        var voipRegistry: PKPushRegistry?
        var incomingPushCompletionCallback: (()->Swift.Void?)? = nil
        
        var isSpinning: Bool?
        var incomingAlertController: UIAlertController?
        
        var callKitCompletionCallback: ((Bool)->Swift.Void?)? = nil
        var audioDevice: TVODefaultAudioDevice = TVODefaultAudioDevice()
        var activeCallInvites: [String: TVOCallInvite]! = [:]
        var activeCalls: [String: TVOCall]! = [:]
        
        // activeCall represents the last connected call
        var activeCall: TVOCall? = nil
        
        var callKitProvider: CXProvider?
        var callKitCallController: CXCallController?
        var userInitiatedDisconnect: Bool = false
        
        /*
         Custom ringback will be played when this flag is enabled.
         When [answerOnBridge](https://www.twilio.com/docs/voice/twiml/dial#answeronbridge) is enabled in
         the <Dial> TwiML verb, the caller will not hear the ringback while the call is ringing and awaiting
         to be accepted on the callee's side. Configure this flag based on the TwiML application.
         */
        var playCustomRingback: Bool = false
        var ringtonePlayer: AVAudioPlayer? = nil
        
        
        
        // Push registry for APNS VOIP
        private var voipPushRegistry: PKPushRegistry?
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
        
        
       @objc func initializePlugin() {
                    print("Initializing plugin")
            //        let debugTwilioPreference = Bundle.main.object(forInfoDictionaryKey: "TVPEnableDebugging")?.uppercased()
            //        if (debugTwilioPreference == "YES") || (debugTwilioPreference == "TRUE") {
            //            TwilioVoice.logLevel = TVOLogLevelDebug
            //        } else {
            //            TwilioVoice.logLevel = TVOLogLevelOff
            //        }
            
            // read in Enable CallKit preference
            //        let enableCallKitPreference = Bundle.main.object(forInfoDictionaryKey: "TVPEnableCallKit")?.uppercased()
            let enableCallKitPreference = "YES"
            
            if (enableCallKitPreference == "YES") || (enableCallKitPreference == "TRUE") {
                enableCallKit = true
                audioDevice = TVODefaultAudioDevice()
                TwilioVoice.audioDevice = audioDevice
            } else {
                enableCallKit = false
            }
            
            // read in MASK_INCOMING_PHONE_NUMBER preference
            //        let enableMaskIncomingPhoneNumberPreference = Bundle.main.object(forInfoDictionaryKey: "TVPMaskIncomingPhoneNumber")?.uppercased()
            let enableMaskIncomingPhoneNumberPreference = "YES"
            
            if (enableMaskIncomingPhoneNumberPreference == "YES") || (enableMaskIncomingPhoneNumberPreference == "TRUE") {
                maskIncomingPhoneNumber = true
            } else {
                maskIncomingPhoneNumber = false
            }
            
            if !enableCallKit {
                //ask for notification support
                let center = UNUserNotificationCenter.current()
                let options: UNAuthorizationOptions = [.alert, .sound]
                
                center.requestAuthorization(options: options, completionHandler: { granted, error in
                    if !granted {
                        print("Notifications not granted")
                    }
                })
                
                // initialize ringtone player
                let ringtoneURL = Bundle.main.url(forResource: "ringing.wav", withExtension: nil)
                if ringtoneURL != nil {
                    let error: Error? = nil
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
                        ringtonePlayer?.numberOfLoops = -1
                        ringtonePlayer?.prepareToPlay()
                    }
                }
            }
        }
        
       @objc func initialize(_ call: CAPPluginCall?) {
        let accessToken = call!.getString("token")
            print("Initializing with an access token")
            
            // retain this command as the callback to use for raising Twilio events
            //        self.callback = command?.callbackId
            
            self.accessToken = accessToken
            if self.accessToken != nil {
                
                // initialize VOIP Push Registry
                self.voipPushRegistry = PKPushRegistry.init(queue: DispatchQueue.main)
                self.voipPushRegistry?.delegate = self
                self.voipPushRegistry?.desiredPushTypes = Set<PKPushType>([.voIP])
                
                if enableCallKit {
                    // initialize CallKit (based on Twilio ObjCVoiceCallKitQuickstart)
                    let incomingCallAppName = Bundle.main.object(forInfoDictionaryKey: "TVPIncomingCallAppName") as? String
                    let configuration = CXProviderConfiguration(localizedName: incomingCallAppName ?? "")
                    configuration.maximumCallGroups = 1
                    configuration.maximumCallsPerCallGroup = 1
                    if let callkitIcon = UIImage(named: "logo.png") {
                        configuration.iconTemplateImageData = callkitIcon.pngData()
                    }
                    configuration.ringtoneSound = "traditionalring.mp3"
                    
                    self.callKitProvider = CXProvider(configuration: configuration)
                    self.callKitProvider?.setDelegate(self, queue: nil)
                    
                    callKitCallController = CXCallController()
                }
                
            }
        
        call.resolve([
            "value": "yo dude"
        ])
            
        }
        
        
       @objc func makeCall(_ call: CAPPluginCall?) {
        let token = call?.getString("token")
            if let call = self.activeCall {
                self.userInitiatedDisconnect = true
                performEndCallAction(uuid: call.uuid)
                self.toggleUIState(isEnabled: false, showCallControl: false)
            } else {
                let uuid = UUID()
                let handle = "Voice Bot"
                
                self.checkRecordPermission { (permissionGranted) in
                    if (!permissionGranted) {
                        let alertController: UIAlertController = UIAlertController(title: "Voice Quick Start",
                                                                                   message: "Microphone permission not granted",
                                                                                   preferredStyle: .alert)
                        
                        let continueWithMic: UIAlertAction = UIAlertAction(title: "Continue without microphone",
                                                                           style: .default,
                                                                           handler: { (action) in
                                                                            self.performStartCallAction(uuid: uuid, handle: handle)
                        })
                        alertController.addAction(continueWithMic)
                        
                        let goToSettings: UIAlertAction = UIAlertAction(title: "Settings",
                                                                        style: .default,
                                                                        handler: { (action) in
                                                                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                                      options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false],
                                                                                                      completionHandler: nil)
                        })
                        alertController.addAction(goToSettings)
                        
                        let cancel: UIAlertAction = UIAlertAction(title: "Cancel",
                                                                  style: .cancel,
                                                                  handler: { (action) in
                                                                    self.toggleUIState(isEnabled: true, showCallControl: false)
                                                                    //                            self.stopSpin()
                        })
                        alertController.addAction(cancel)
                        
                        self.present(alertController, animated: true, completion: nil)
                    } else {
                        self.performStartCallAction(uuid: uuid, handle: handle)
                    }
                }
            }
        
        call.resolve([
             "value": "yo dude"
         ])
            
        }
        
       @objc func sendDigits(_ call: CAPPluginCall?) {
        let digits = call?.getString("digits");
        
        if digits != nil {
            self.call?.sendDigits(digits!)
            
            call.resolve([
                 "value": "yo dude"
             ])
            
        } else {
            call.reject(
            )
        }
        
        
        
        }
        
        
        deinit {
            // CallKit has an odd API contract where the developer must call invalidate or the CXProvider is leaked.
            if let callKitProvider = self.callKitProvider {
                callKitProvider.invalidate()
            }
        }

        
       @objc func fetchAccessToken() -> String? {
            let endpointWithIdentity = String(format: "%@?identity=%@", accessTokenEndpoint, identity)
            guard let accessTokenURL = URL(string: baseURLString + endpointWithIdentity) else {
                return nil
            }
            
            return try? String.init(contentsOf: accessTokenURL, encoding: .utf8)
        }
        
       @objc func toggleUIState(isEnabled: Bool, showCallControl: Bool) {
            print("toggle ui state")
        }
        
//        @IBAction func mainButtonPressed(_ sender: Any) {
//            if let call = self.activeCall {
//                self.userInitiatedDisconnect = true
//                performEndCallAction(uuid: call.uuid)
//                self.toggleUIState(isEnabled: false, showCallControl: false)
//            } else {
//                let uuid = UUID()
//                let handle = "Voice Bot"
//
//                self.checkRecordPermission { (permissionGranted) in
//                    if (!permissionGranted) {
//                        let alertController: UIAlertController = UIAlertController(title: "Voice Quick Start",
//                                                                                   message: "Microphone permission not granted",
//                                                                                   preferredStyle: .alert)
//
//                        let continueWithMic: UIAlertAction = UIAlertAction(title: "Continue without microphone",
//                                                                           style: .default,
//                                                                           handler: { (action) in
//                                                                            self.performStartCallAction(uuid: uuid, handle: handle)
//                        })
//                        alertController.addAction(continueWithMic)
//
//                        let goToSettings: UIAlertAction = UIAlertAction(title: "Settings",
//                                                                        style: .default,
//                                                                        handler: { (action) in
//                                                                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
//                                                                                                      options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false],
//                                                                                                      completionHandler: nil)
//                        })
//                        alertController.addAction(goToSettings)
//
//                        let cancel: UIAlertAction = UIAlertAction(title: "Cancel",
//                                                                  style: .cancel,
//                                                                  handler: { (action) in
//                                                                    self.toggleUIState(isEnabled: true, showCallControl: false)
//                        })
//                        alertController.addAction(cancel)
//
//                        self.present(alertController, animated: true, completion: nil)
//                    } else {
//                        self.performStartCallAction(uuid: uuid, handle: handle)
//                    }
//                }
//            }
//        }
        
       @objc func checkRecordPermission(completion: @escaping (_ permissionGranted: Bool) -> Void) {
            let permissionStatus: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
            
            switch permissionStatus {
            case AVAudioSessionRecordPermission.granted:
                // Record permission already granted.
                completion(true)
                break
            case AVAudioSessionRecordPermission.denied:
                // Record permission denied.
                completion(false)
                break
            case AVAudioSessionRecordPermission.undetermined:
                // Requesting record permission.
                // Optional: pop up app dialog to let the users know if they want to request.
                AVAudioSession.sharedInstance().requestRecordPermission({ (granted) in
                    completion(granted)
                })
                break
            default:
                completion(false)
                break
            }
        }
        
//        @IBAction func muteSwitchToggled(_ sender: UISwitch) {
//            // The sample app supports toggling mute from app UI only on the last connected call.
//            if let call = self.activeCall {
//                call.isMuted = sender.isOn
//            }
//        }
        
//3
        
        // MARK: UITextFieldDelegate
       @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            return true
        }
        
        
        // MARK: PKPushRegistryDelegate
       @objc func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
            NSLog("pushRegistry:didUpdatePushCredentials:forType:")
            
            if (type != .voIP) {
                return
            }
            
            guard let accessToken = fetchAccessToken() else {
                return
            }
            
            let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
            
            TwilioVoice.register(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
                if let error = error {
                    NSLog("An error occurred while registering: \(error.localizedDescription)")
                }
                else {
                    NSLog("Successfully registered for VoIP push notifications.")
                }
            }
            
            self.deviceTokenString = deviceToken
        }
        
       @objc func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
            NSLog("pushRegistry:didInvalidatePushTokenForType:")
            
            if (type != .voIP) {
                return
            }
            
            guard let deviceToken = deviceTokenString, let accessToken = fetchAccessToken() else {
                return
            }
            
            TwilioVoice.unregister(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
                if let error = error {
                    NSLog("An error occurred while unregistering: \(error.localizedDescription)")
                }
                else {
                    NSLog("Successfully unregistered from VoIP push notifications.")
                }
            }
            
            self.deviceTokenString = nil
        }
        
        /**
         * Try using the `pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:` method if
         * your application is targeting iOS 11. According to the docs, this delegate method is deprecated by Apple.
         */
       @objc func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
            NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:")
            
            if (type == PKPushType.voIP) {
                // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error:` when delegate queue is not passed
                TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
            }
        }
        
        /**
         * This delegate method is available on iOS 11 and above. Call the completion handler once the
         * notification payload is passed to the `TwilioVoice.handleNotification()` method.
         */
       @objc func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
            NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:completion:")
            
            if (type == PKPushType.voIP) {
                // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error:` when delegate queue is not passed
                TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
            }
            
            if let version = Float(UIDevice.current.systemVersion), version < 13.0 {
                // Save for later when the notification is properly handled.
                self.incomingPushCompletionCallback = completion
            } else {
                /**
                 * The Voice SDK processes the call notification and returns the call invite synchronously. Report the incoming call to
                 * CallKit and fulfill the completion before exiting this callback method.
                 */
                completion()
            }
        }
        
       @objc func incomingPushHandled() {
            if let completion = self.incomingPushCompletionCallback {
                completion()
                self.incomingPushCompletionCallback = nil
            }
        }
        
        // MARK: TVONotificaitonDelegate
       @objc func callInviteReceived(_ callInvite: TVOCallInvite) {
            NSLog("callInviteReceived:")
            
            var from:String = callInvite.from ?? "Voice Bot"
            from = from.replacingOccurrences(of: "client:", with: "")
            
            // Always report to CallKit
            reportIncomingCall(from: from, uuid: callInvite.uuid)
            self.activeCallInvites[callInvite.uuid.uuidString] = callInvite
        }
        
       @objc func cancelledCallInviteReceived(_ cancelledCallInvite: TVOCancelledCallInvite, error: Error) {
            NSLog("cancelledCallInviteCanceled:error:, error: \(error.localizedDescription)")
            
            if (self.activeCallInvites!.isEmpty) {
                NSLog("No pending call invite")
                return
            }
            
            var callInvite: TVOCallInvite?
            for (_, invite) in self.activeCallInvites {
                if (invite.callSid == cancelledCallInvite.callSid) {
                    callInvite = invite
                    break
                }
            }
            
            if let callInvite = callInvite {
                performEndCallAction(uuid: callInvite.uuid)
            }
        }
        
        // MARK: TVOCallDelegate
       @objc func callDidStartRinging(_ call: TVOCall) {
            NSLog("callDidStartRinging:")
            
            //          self.placeCallButton.setTitle("Ringing", for: .normal)
            
            /*
             When [answerOnBridge](https://www.twilio.com/docs/voice/twiml/dial#answeronbridge) is enabled in the
             <Dial> TwiML verb, the caller will not hear the ringback while the call is ringing and awaiting to be
             accepted on the callee's side. The application can use the `AVAudioPlayer` to play custom audio files
             between the `[TVOCallDelegate callDidStartRinging:]` and the `[TVOCallDelegate callDidConnect:]` callbacks.
             */
            if (self.playCustomRingback) {
                self.playRingback()
            }
        }
        
       @objc func callDidConnect(_ call: TVOCall) {
            NSLog("callDidConnect:")
            
            if (self.playCustomRingback) {
                self.stopRingback()
            }
            
            self.callKitCompletionCallback!(true)
            
            //          self.placeCallButton.setTitle("Hang Up", for: .normal)
            
            toggleUIState(isEnabled: true, showCallControl: true)
            //          stopSpin()
            toggleAudioRoute(toSpeaker: true)
        }
        
       @objc func call(_ call: TVOCall, isReconnectingWithError error: Error) {
            NSLog("call:isReconnectingWithError:")
            
            //          self.placeCallButton.setTitle("Reconnecting", for: .normal)
            
            toggleUIState(isEnabled: false, showCallControl: false)
        }
        
       @objc func callDidReconnect(_ call: TVOCall) {
            NSLog("callDidReconnect:")
            
            //          self.placeCallButton.setTitle("Hang Up", for: .normal)
            
            toggleUIState(isEnabled: true, showCallControl: true)
        }
        
       @objc func call(_ call: TVOCall, didFailToConnectWithError error: Error) {
            NSLog("Call failed to connect: \(error.localizedDescription)")
            
            if let completion = self.callKitCompletionCallback {
                completion(false)
            }
            
            performEndCallAction(uuid: call.uuid)
            callDisconnected(call)
        }
        
       @objc func call(_ call: TVOCall, didDisconnectWithError error: Error?) {
            if let error = error {
                NSLog("Call failed: \(error.localizedDescription)")
            } else {
                NSLog("Call disconnected")
            }
            
            if !self.userInitiatedDisconnect {
                var reason = CXCallEndedReason.remoteEnded
                
                if error != nil {
                    reason = .failed
                }
                
                let callHandle = CXHandle(type: .generic, value: "placeholder")
                let callUpdate = CXCallUpdate()
                callUpdate.remoteHandle = callHandle
                callUpdate.supportsDTMF = true
                callUpdate.supportsHolding = true
                callUpdate.supportsGrouping = false
                callUpdate.supportsUngrouping = false
                callUpdate.hasVideo = false
                
                self.callKitProvider?.reportCall(with: call.uuid, updated: callUpdate)
                
            }
            
            callDisconnected(call)
        }
        
       @objc func callDisconnected(_ call: TVOCall) {
            if (call == self.activeCall) {
                self.activeCall = nil
            }
            self.activeCalls.removeValue(forKey: call.uuid.uuidString)
            
            self.userInitiatedDisconnect = false
            
            if (self.playCustomRingback) {
                self.stopRingback()
            }
            
            toggleUIState(isEnabled: true, showCallControl: false)
            //          self.placeCallButton.setTitle("Call", for: .normal)
        }
        
        
        // MARK: AVAudioSession
       @objc func toggleAudioRoute(toSpeaker: Bool) {
            // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
            audioDevice.block = {
                kTVODefaultAVAudioSessionConfigurationBlock()
                do {
                    if (toSpeaker) {
                        try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                    } else {
                        try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                    }
                } catch {
                    NSLog(error.localizedDescription)
                }
            }
            audioDevice.block()
        }
        
        
        
        
        // MARK: CXProviderDelegate
       @objc func providerDidReset(_ provider: CXProvider) {
            NSLog("providerDidReset:")
            audioDevice.isEnabled = true
        }
        
       @objc func providerDidBegin(_ provider: CXProvider) {
            NSLog("providerDidBegin")
        }
        
       @objc func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
            NSLog("provider:didActivateAudioSession:")
            audioDevice.isEnabled = true
        }
        
       @objc func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
            NSLog("provider:didDeactivateAudioSession:")
        }
        
       @objc func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
            NSLog("provider:timedOutPerformingAction:")
        }
        
       @objc func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
            NSLog("provider:performStartCallAction:")
            
            toggleUIState(isEnabled: false, showCallControl: false)
            
            audioDevice.isEnabled = false
            audioDevice.block();
            
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
            
            self.performVoiceCall(uuid: action.callUUID, client: "") { (success) in
                if (success) {
                    provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
                    action.fulfill()
                } else {
                    action.fail()
                }
            }
        }
        
       @objc func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
            NSLog("provider:performAnswerCallAction:")
            
            audioDevice.isEnabled = false
            audioDevice.block();
            
            self.performAnswerVoiceCall(uuid: action.callUUID) { (success) in
                if (success) {
                    action.fulfill()
                } else {
                    action.fail()
                }
            }
            
            action.fulfill()
        }
        
       @objc func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
            NSLog("provider:performEndCallAction:")
            
            if let invite = self.activeCallInvites[action.callUUID.uuidString] {
                invite.reject()
                self.activeCallInvites.removeValue(forKey: action.callUUID.uuidString)
            } else if let call = self.activeCalls[action.callUUID.uuidString] {
                call.disconnect()
            } else {
                NSLog("Unknown UUID to perform end-call action with")
            }
            
            action.fulfill()
        }
        
       @objc func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
            NSLog("provider:performSetHeldAction:")
            
            if let call = self.activeCalls[action.callUUID.uuidString] {
                call.isOnHold = action.isOnHold
                action.fulfill()
            } else {
                action.fail()
            }
        }
        
       @objc func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
            NSLog("provider:performSetMutedAction:")
            
            if let call = self.activeCalls[action.callUUID.uuidString] {
                call.isMuted = action.isMuted
                action.fulfill()
            } else {
                action.fail()
            }
        }
        
        // MARK: Call Kit Actions
       @objc func performStartCallAction(uuid: UUID, handle: String) {
            let callHandle = CXHandle(type: .generic, value: handle)
            let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
            let transaction = CXTransaction(action: startCallAction)
            
            callKitCallController?.request(transaction)  { error in
                if let error = error {
                    NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
                    return
                }
                
                NSLog("StartCallAction transaction request successful")
                
                let callUpdate = CXCallUpdate()
                callUpdate.remoteHandle = callHandle
                callUpdate.supportsDTMF = true
                callUpdate.supportsHolding = true
                callUpdate.supportsGrouping = false
                callUpdate.supportsUngrouping = false
                callUpdate.hasVideo = false
                
                self.callKitProvider?.reportCall(with: uuid, updated: callUpdate)
            }
        }
        
       @objc func reportIncomingCall(from: String, uuid: UUID) {
            let callHandle = CXHandle(type: .generic, value: from)
            
            let callUpdate = CXCallUpdate()
            callUpdate.remoteHandle = callHandle
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false
            
            callKitProvider?.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
                if let error = error {
                    NSLog("Failed to report incoming call successfully: \(error.localizedDescription).")
                } else {
                    NSLog("Incoming call successfully reported.")
                }
            }
        }
        
       @objc func performEndCallAction(uuid: UUID) {
            
            let endCallAction = CXEndCallAction(call: uuid)
            let transaction = CXTransaction(action: endCallAction)
            
            callKitCallController?.request(transaction) { error in
                if let error = error {
                    NSLog("EndCallAction transaction request failed: \(error.localizedDescription).")
                } else {
                    NSLog("EndCallAction transaction request successful")
                }
            }
        }
        
       @objc func performVoiceCall(uuid: UUID, client: String?, completionHandler: @escaping (Bool) -> Swift.Void) {
            guard let accessToken = fetchAccessToken() else {
                completionHandler(false)
                return
            }
            
            let connectOptions: TVOConnectOptions = TVOConnectOptions(accessToken: accessToken) { (builder) in
                builder.params = [twimlParamTo : "outgoing text thing "]
                builder.uuid = uuid
            }
            let call = TwilioVoice.connect(with: connectOptions, delegate: self)
            self.activeCall = call
            self.activeCalls[call.uuid.uuidString] = call
            self.callKitCompletionCallback = completionHandler
        }
        
       @objc func performAnswerVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Swift.Void) {
            if let callInvite = self.activeCallInvites[uuid.uuidString] {
                let acceptOptions: TVOAcceptOptions = TVOAcceptOptions(callInvite: callInvite) { (builder) in
                    builder.uuid = callInvite.uuid
                }
                let call = callInvite.accept(with: acceptOptions, delegate: self)
                self.activeCall = call
                self.activeCalls[call.uuid.uuidString] = call
                self.callKitCompletionCallback = completionHandler
                
                self.activeCallInvites.removeValue(forKey: uuid.uuidString)
                
                guard #available(iOS 13, *) else {
                    self.incomingPushHandled()
                    return
                }
            } else {
                NSLog("No CallInvite matches the UUID")
            }
        }
        
        // MARK: Ringtone
       @objc func playRingback() {
            let ringtonePath = URL(fileURLWithPath: Bundle.main.path(forResource: "ringtone", ofType: "wav")!)
            do {
                self.ringtonePlayer = try AVAudioPlayer(contentsOf: ringtonePath)
                self.ringtonePlayer?.delegate = self
                self.ringtonePlayer?.numberOfLoops = -1
                
                self.ringtonePlayer?.volume = 1.0
                self.ringtonePlayer?.play()
            } catch {
                NSLog("Failed to initialize audio player")
            }
        }
        
       @objc func stopRingback() {
            if (self.ringtonePlayer?.isPlaying == false) {
                return
            }
            
            self.ringtonePlayer?.stop()
        }
        
       @objc func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            if (flag) {
                NSLog("Audio player finished playing successfully");
            } else {
                NSLog("Audio player finished playing with some error");
            }
        }
        
       @objc func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            NSLog("Decode error occurred: \(error?.localizedDescription)");
        }
        
    
    
}
