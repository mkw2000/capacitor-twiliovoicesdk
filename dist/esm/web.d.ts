import { WebPlugin } from '@capacitor/core';
import { CapacitorTwilioVoiceSDKPlugin } from './definitions';
export declare class CapacitorTwilioVoiceSDKWeb extends WebPlugin implements CapacitorTwilioVoiceSDKPlugin {
    constructor();
    echo(options: {
        value: string;
    }): Promise<{
        value: string;
    }>;
}
declare const CapacitorTwilioVoiceSDK: CapacitorTwilioVoiceSDKWeb;
export { CapacitorTwilioVoiceSDK };
