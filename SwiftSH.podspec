Pod::Spec.new do |spec|
  spec.name             = 'SwiftSH'
  spec.version          = '0.1.2'
  spec.summary          = 'A Swift SSH framework that wraps libssh2.'
  spec.homepage         = 'https://github.com/TheTekton337/SwiftSH'
  spec.license          = 'MIT'
  spec.swift_versions   = ['5.3']
  spec.authors          = { 'Tommaso Madonia' => 'tommaso@madonia.me' }
  spec.source           = { :git => 'https://github.com/TheTekton337/SwiftSH.git', :tag => spec.version.to_s }

  spec.requires_arc     = true
  spec.default_subspec  = 'Libssh2'
  spec.swift_version    = '5.3'

  spec.macos.deployment_target = '10.15'
 spec.macos.deployment_target = '10.15'

  spec.subspec 'Core' do |core|
      core.source_files = 'Sources/SwiftSH/*.swift'
      core.exclude_files = 'SwiftSH/Libssh2*'
  end

  spec.subspec 'Libssh2' do |libssh2|
      libssh2.dependency 'SwiftSH/Core'
      libssh2.libraries = 'z'
      libssh2.preserve_paths = 'Sources/CSwiftSH'
      libssh2.source_files = 'Sources/CSwiftSH/*.{h,m}', 'Sources/SwiftSH/Libssh2*.{swift}'
      libssh2.pod_target_xcconfig = {
        'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
        'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/SwiftSH/Sources/CSwiftSH',
        'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/SwiftSH/Sources/CSwiftSH',
        'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/SwiftSH/Sources/CSwiftSH'
      }
  end

end
