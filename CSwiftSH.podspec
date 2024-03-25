Pod::Spec.new do |spec|
  spec.name         = 'CSwiftSH'
  spec.version      = '0.1.3'
  spec.summary      = 'A Swift wrapper for the CSSH library, providing an interface to libssh2.'
  spec.description  = <<-DESC
                       CSwiftSH provides a Swift interface to the CSSH library, a wrapper around the libssh2 library.
                     DESC
  spec.homepage     = 'https://github.com/TheTekton337/CSwiftSH'
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.authors      = { 'Terrance Wood' => 'pntkl@ixqus.com' }
  spec.source       = { :git => 'https://github.com/TheTekton337/CSwiftSH.git', :tag => spec.version.to_s }
  
  spec.platforms    = { :ios => '13.0', :osx => '10.15' }
  spec.swift_version = '5.3'
  spec.requires_arc = true

  spec.dependency 'CSSH'

  spec.source_files  = 'Sources/CSwiftSH/**/*.{h,m,swift}'
end
