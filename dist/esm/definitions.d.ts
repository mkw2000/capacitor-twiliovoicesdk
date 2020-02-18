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
}
