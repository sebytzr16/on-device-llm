Pod::Spec.new do |s|
  s.name = 'OnDeviceNative'
  s.version = '0.1.0'
  s.summary = 'Local llama.cpp inference bridge'
  s.description = 'The pinned llama.cpp runtime and a stable C ABI for Dart FFI.'
  s.homepage = 'https://github.com/ggml-org/llama.cpp'
  s.license = { :type => 'MIT', :file => '../../LICENSE' }
  s.author = 'OnDevice LLM contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'OnDeviceNative.xcframework'
  s.frameworks = 'Metal', 'MetalKit', 'Accelerate', 'Foundation'
  s.libraries = 'c++'
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_od_version -Wl,-u,_od_create -Wl,-u,_od_destroy -Wl,-u,_od_error -Wl,-u,_od_info -Wl,-u,_od_preview -Wl,-u,_od_load -Wl,-u,_od_begin -Wl,-u,_od_step' }
end
