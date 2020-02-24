declare module "@capacitor/core" {
    interface PluginRegistry {
        CapacitorTwilioVoiceSDK: CapacitorTwilioVoiceSDKPlugin;
    }
}
export interface CapacitorTwilioVoiceSDKPlugin {
    echo(options: {
        value: string;
    }): Promise<{
        value: string;
    }>;


    makeCall(options: {
        token?: string;
        params?: any;
      }): Promise<{
        value: string;
      }>;
    
      init(options?: any): Promise<{value: string}>;


      sendDigits(digits?: string): Promise<{value: string}>;
    
      disconnect(options?: any): Promise<void>;
    
      rejectCallInvite(options?: any): Promise<void>;
    
      acceptCallInvite(options?: any): Promise<void>;
    
      setSpeaker(options?: any): Promise<void>;
    
      muteCall(options?: any): Promise<void>;
    
      unmuteCall(options?: any): Promise<void>;
    
      isCallMuted(options?: any): Promise<void>;
    
      error(options?: any): Promise<void>;
    
      clientinitialized(options?: any): Promise<void>;
    
      callinvitereceived(options?: any): Promise<void>;
    
      callinvitecanceled(options?: any): Promise<void>;
    
      calldidconnect(options?: any): Promise<void>;
    
      calldiddisconnect(options?: any): Promise<void>;
    
    
    
}
