Pod::Spec.new do |spec|
  spec.name             = 'SwiftSH'
  spec.version          = '0.1.2'
  spec.summary          = 'A Swift SSH framework that wraps libssh2.'
  spec.homepage         = 'https://github.com/Frugghi/SwiftSH'
  spec.license          = { :type => 'MIT', :file => 'LICENSE' }
  spec.authors          = { 'Tommaso Madonia' => 'tommaso@madonia.me' }
  spec.source           = { :git => 'https://github.com/TheTekton/SwiftSH.git', :tag => '0.1.3' }
  
  spec.platforms        = { :ios => '13.0', :osx => '10.15' }
  spec.swift_version    = '5.3'
  spec.requires_arc     = true
  
  spec.dependency 'CSSH', '~> 1.11'

  spec.subspec 'Core' do |core|
    core.source_files = 'Sources/SwiftSH/**/*.swift'
    core.exclude_files = 'Sources/SwiftSH/**/Libssh2*'
  end
  
  spec.subspec 'CSwiftSH' do |cswiftsh|
    cswiftsh.dependency 'SwiftSH/Core'
    cswiftsh.dependency 'CSSH'
    cswiftsh.source_files = 'Sources/CSwiftSH/*.{h,c,swift}'
  end
  
  spec.subspec 'SwiftSH' do |swiftsh|
    swiftsh.dependency 'SwiftSH/Core'
    swiftsh.dependency 'SwiftSH/CSwiftSH'
    swiftsh.source_files = 'Sources/SwiftSH/*.{swift}'
  end
end
