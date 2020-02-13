import { WebPlugin } from '@capacitor/core';
import { CapacitorTwilioVoiceSDKPlugin } from './definitions';

export class CapacitorTwilioVoiceSDKWeb extends WebPlugin implements CapacitorTwilioVoiceSDKPlugin {
  constructor() {
    super({
      name: 'CapacitorTwilioVoiceSDK',
      platforms: ['web']
    });
  }

  async echo(options: { value: string }): Promise<{value: string}> {
    console.log('ECHO', options);
    return options;
  }
}

const CapacitorTwilioVoiceSDK = new CapacitorTwilioVoiceSDKWeb();

export { CapacitorTwilioVoiceSDK };

import { registerWebPlugin } from '@capacitor/core';
registerWebPlugin(CapacitorTwilioVoiceSDK);
