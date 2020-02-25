#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(CapacitorTwilioVoiceSDK, "CapacitorTwilioVoiceSDK",
CAP_PLUGIN_METHOD(echo, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(makeCall, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(initialize, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(sendDigits, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(disconnect, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(rejectCallInvite, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(acceptCallInvite, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(setSpeaker, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(muteCall, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(unmuteCall, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(isCallMuted, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(error, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(clientinitialized, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(callinvitereceived, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(callinvitecanceled, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(calldidconnect, CAPPluginReturnPromise);
CAP_PLUGIN_METHOD(calldiddisconnect, CAPPluginReturnPromise);

)
