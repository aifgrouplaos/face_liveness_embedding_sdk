Pod::Spec.new do |s|
  s.name             = 'face_recognition_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter face recognition plugin scaffold.'
  s.description      = <<-DESC
Flutter plugin SDK for native face processing and verification.
                       DESC
  s.homepage         = 'https://example.com/face_recognition_sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AIF' => 'team@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'GoogleMLKit/FaceDetection'
  s.dependency 'TensorFlowLiteSwift'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
