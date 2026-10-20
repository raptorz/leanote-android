require 'xcodeproj'

abort 'Usage: ruby create_project.rb <output-directory>' unless ARGV.length == 1
output = File.expand_path(ARGV.fetch(0))
project = Xcodeproj::Project.new(File.join(output, 'SharingUI.xcodeproj'))
target = project.new_target(:ui_test_bundle, 'SharingUITests', :ios, '15.0')
source = project.main_group.new_file(File.join(__dir__, 'SharingUITests.swift'))
target.source_build_phase.add_file_reference(source)
target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.github.gemsnote.SharingUITests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project.path, 'SharingUITests')
