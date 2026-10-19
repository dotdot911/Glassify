Pod::Spec.new do |s|
  s.name         = 'Glassify'
  s.version      = '0.1.0'
  s.summary      = "iOS 26 Liquid Glass for iOS 13+, re-implemented with Metal."
  s.description  = <<-DESC
    Glass views, containers, glass buttons, switch, slider, segmented control, navigation bar and
    toolbar with the look and motion of iOS 26 Liquid Glass, rendered by a C++ core and Metal.
  DESC
  s.homepage     = 'https://github.com/dotdot911/Glassify'
  s.license      = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author       = 'Hung Phan'
  s.source       = { :git => 'https://github.com/dotdot911/Glassify.git', :tag => s.version.to_s }

  s.platform     = :ios, '13.0'
  s.requires_arc = true
  s.frameworks   = 'UIKit', 'Metal', 'QuartzCore', 'CoreGraphics'
  s.library      = 'c++'

  s.source_files         = 'Sources/Glassify/include/Glassify/*.h',
                           'Sources/Glassify/Platform/*.{h,mm}',
                           'Sources/Glassify/Core/**/*.{h,cpp}',
                           'Sources/Glassify/Shaders/*.h'
  s.public_header_files  = 'Sources/Glassify/include/Glassify/*.h'
  s.private_header_files = 'Sources/Glassify/Platform/*.h',
                           'Sources/Glassify/Core/**/*.h',
                           'Sources/Glassify/Shaders/*.h'
  # The shaders are compiled into GlassifyShaders.bundle (default.metallib), found at run time.
  s.resource_bundles     = { 'GlassifyShaders' => ['Sources/Glassify/Shaders/*.metal'] }

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Sources/Glassify/Core/include" ' \
                             '"${PODS_TARGET_SRCROOT}/Sources/Glassify/include"',
    'MTL_HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Sources/Glassify/Shaders"',
  }
end
