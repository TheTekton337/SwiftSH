Pod::Spec.new do |spec|
  spec.name             = 'SwiftSH'
  spec.version          = '0.1.3'
  spec.summary          = 'A Swift SSH framework that wraps libssh2.'
  spec.homepage         = 'https://github.com/TheTekton337/SwiftSH'
  spec.license          = { :type => 'MIT', :file => 'LICENSE' }
  spec.authors          = { 'Tommaso Madonia' => 'tommaso@madonia.me' }
  spec.source           = { :git => 'https://github.com/TheTekton/SwiftSH.git', :tag => '0.1.3' }
  
  spec.platforms        = { :ios => '13.0', :osx => '10.15' }
  spec.swift_version    = '5.3'
  spec.requires_arc     = true

  spec.dependency 'CSSH'
  spec.dependency 'CSwiftSH'

  spec.source_files  = 'Sources/SwiftSH/*.{swift}'
end
