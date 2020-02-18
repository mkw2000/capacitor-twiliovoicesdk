
  Pod::Spec.new do |s|
    s.name = 'CapacitorTwiliovoicesdk'
    s.version = '0.0.1'
    s.summary = 'Capacitor plugin for Twilio Programmable Voice SDK'
    s.license = 'WTFPL'
    s.homepage = 'https://github.com/mkw2000/capacitor-twiliovoicesdk'
    s.author = 'Michael Weiner'
    s.source = { :git => 'https://github.com/mkw2000/capacitor-twiliovoicesdk', :tag => s.version.to_s }
    s.source_files = 'ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
    s.ios.deployment_target  = '11.0'
    s.dependency 'Capacitor'
    s.dependency 'TwilioVoice'

  end