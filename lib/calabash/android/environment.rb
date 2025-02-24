require 'rexml/document'
require 'timeout'

# We sometimes want to require a Ruby gem without having our IDE auto-complete
# using it. For example awesome_print adds a ton of methods to 'Object'
alias :cal_require_without_documentation :require
cal_require_without_documentation 'luffa'

require 'timeout'

if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
  require 'win32/registry'
end

module Calabash
  module Android
    class Environment < Calabash::Environment
      # @!visibility private
      class InvalidEnvironmentError < RuntimeError; end
      # @!visibility private
      class InvalidJavaSDKHome < RuntimeError; end

      # A URI that points to the embedded Calabash server in the app under test.
      #
      # The default value is 'http://localhost:34777'.
      #
      # You can control the value of this variable by setting the `CAL_ENDPOINT`
      # variable.
      #
      # @todo Maybe rename this to CAL_SERVER_URL or CAL_SERVER?
      DEVICE_ENDPOINT = URI.parse((variable('CAL_ENDPOINT') || 'http://127.0.0.1:34777'))

      # A URI that points to the helper server on the device.
      #
      # The default value is 'http://localhost:34778'.
      #
      # You can control the value of this variable by setting the `CAL_HELPER_ENDPOINT`
      # variable.
      DEVICE_HELPER_ENDPOINT = URI.parse((variable('CAL_HELPER_ENDPOINT') || 'http://127.0.0.1:34778'))

      private

      def self.set_android_dependencies(android_dependencies)
        @@android_dependencies = android_dependencies
      end

      def self.set_java_dependencies(java_dependencies)
        @@java_dependencies = java_dependencies
      end

      def self.android_dependencies(key)
        if @@android_dependencies.has_key?(key)
          file = @@android_dependencies[key]

          unless File.exist?(file)
            raise "No such file '#{file}'"
          end

          file
        else
          raise "No such dependency '#{key}'"
        end
      end

      def self.java_dependencies(key)
        if key == :ant_path
          ant_executable
        elsif @@java_dependencies.has_key?(key)
          file = @@java_dependencies[key]

          unless File.exist?(file)
            raise "No such file '#{file}'"
          end

          file
        else
          raise "No such dependency '#{key}'"
        end
      end

      public

      def self.adb_path
        android_dependencies(:adb_path)
      end

      def self.aapt_path
        android_dependencies(:aapt_path)
      end

      def self.zipalign_path
        android_dependencies(:zipalign_path)
      end

      def self.android_jar_path
        android_dependencies(:android_jar_path)
      end

      def self.java_path
        java_dependencies(:java_path)
      end

      def self.keytool_path
        java_dependencies(:keytool_path)
      end

      def self.jarsigner_path
        java_dependencies(:jarsigner_path)
      end

      def self.ant_path
        java_dependencies(:ant_path)
      end

      def self.setup
        if Environment.variable('ANDROID_HOME')
          android_sdk_location = Environment.variable('ANDROID_HOME')
          Logger.debug("Setting Android SDK location to $ANDROID_HOME")
        else
          android_sdk_location = detect_android_sdk_location
        end

        if android_sdk_location.nil?
          Logger.error 'Could not find an Android SDK please make sure it is installed.'
          Logger.error 'You can read about how Calabash is searching for an Android SDK and how you can help here:'
          Logger.error 'https://github.com/calabash/calabash-android/blob/master/documentation/installation.md#prerequisites'

          raise 'Could not find an Android SDK'
        end

        Logger.debug("Android SDK location set to '#{android_sdk_location}'")

        begin
          set_android_dependencies(locate_android_dependencies(android_sdk_location))
        rescue InvalidEnvironmentError => e
          Logger.error 'Could not locate Android dependency'
          Logger.error 'You can read about how Calabash is searching for an Android SDK and how you can help here:'
          Logger.error 'https://github.com/calabash/calabash-android/blob/master/documentation/installation.md#prerequisites'

          raise e
        end

        if Environment.variable('JAVA_HOME')
          java_sdk_home = Environment.variable('JAVA_HOME')
          Logger.debug("Setting Java SDK location to $JAVA_HOME")
        else
          java_sdk_home = detect_java_sdk_location
        end

        Logger.debug("Java SDK location set to '#{java_sdk_home}'")

        begin
          set_java_dependencies(locate_java_dependencies(java_sdk_home))
        rescue InvalidJavaSDKHome => e
          Logger.error "Could not find Java Development Kit please make sure it is installed."
          Logger.error "You can read about how Calabash is searching for a JDK and how you can help here:"
          Logger.error "https://github.com/calabash/calabash-android/blob/master/documentation/installation.md#prerequisites"

          raise e
        rescue InvalidEnvironmentError => e
          Logger.error "Could not find Java dependency"
          Logger.error "You can read about how Calabash is searching for a JDK and how you can help here:"
          Logger.error "https://github.com/calabash/calabash-android/blob/master/documentation/installation.md#prerequisites"

          raise e
        end
      end

      private

      def self.tools_directory
        tools_directories = tools_directories(Environment.variable('ANDROID_HOME'))

        File.join(Environment.variable('ANDROID_HOME'), tools_directories.first)
      end

      def self.tools_directories(android_sdk_location)
        build_tools_files = list_files(File.join(android_sdk_location, 'build-tools')).select {|file| File.directory?(file)}

        build_tools_directories =
            build_tools_files.select do |dir|
              begin
                Luffa::Version.new(File.basename(dir))
                true
              rescue ArgumentError
                false
              end
            end.sort do |a, b|
              Luffa::Version.compare(Luffa::Version.new(File.basename(a)), Luffa::Version.new(File.basename(b)))
            end.reverse.map{|dir| File.join('build-tools', File.basename(dir))}

        if build_tools_directories.empty?
          build_tools_directories = [File.join('build-tools', File.basename(build_tools_files.reverse.first))]
        end

        build_tools_directories + ['platform-tools', 'tools']
      end

      def self.platform_directory(android_sdk_location)
        files = list_files(File.join(android_sdk_location, 'platforms'))
                    .select {|file| File.directory?(file)}

        sorted_files = files.sort_by {|item| '%08s' % item.split('-').last}.reverse

        File.join('platforms', File.basename(sorted_files.first))
      end

      def self.locate_android_dependencies(android_sdk_location)
        adb_path = scan_for_path(android_sdk_location, adb_executable, ['platform-tools'])
        aapt_path = scan_for_path(android_sdk_location, aapt_executable, tools_directories(android_sdk_location))
        zipalign_path = scan_for_path(android_sdk_location, zipalign_executable, tools_directories(android_sdk_location))

        if adb_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{adb_executable}' in '#{android_sdk_location}'"
        end

        if aapt_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{aapt_executable}' in '#{android_sdk_location}'"
        end

        if zipalign_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{zipalign_executable}' in '#{android_sdk_location}'"
        end

        Logger.debug("Set aapt path to '#{aapt_path}'")
        Logger.debug("Set zipalign path to '#{zipalign_path}'")
        Logger.debug("Set adb path to '#{adb_path}'")

        android_jar_path = scan_for_path(File.join(android_sdk_location, 'platforms'), 'android.jar', [File.basename(platform_directory(android_sdk_location))])

        if android_jar_path.nil?
          raise InvalidEnvironmentError,
                "Could not find 'android.jar' in '#{File.join(android_sdk_location, 'platforms')}'"
        end

        Logger.debug("Set android jar path to '#{android_jar_path}'")

        {
            aapt_path: aapt_path,
            zipalign_path: zipalign_path,
            adb_path: adb_path,
            android_jar_path: android_jar_path
        }
      end

      def self.locate_java_dependencies(java_sdk_location)
        # For the Java dependencies, we will use the PATH elements of they exist
        on_path = find_executable_on_path(java_executable)

        if on_path
          Logger.debug('Found java on PATH')
          java_path = on_path
        else
          if java_sdk_location.nil? || java_sdk_location.empty?
            raise InvalidJavaSDKHome,
                  "Could not locate '#{java_executable}' on path, and Java SDK Home is invalid."
          end

          java_path = scan_for_path(java_sdk_location, java_executable, ['bin'])
        end

        Logger.debug("Set java path to '#{java_path}'")

        on_path = find_executable_on_path(keytool_executable)

        if on_path
          Logger.debug('Found keytool on PATH')
          keytool_path = on_path
        else
          if java_sdk_location.nil? || java_sdk_location.empty?
            raise InvalidJavaSDKHome,
                  "Could not locate '#{keytool_executable}' on path, and Java SDK Home is invalid."
          end

          keytool_path = scan_for_path(java_sdk_location, keytool_executable, ['bin'])
        end

        Logger.debug("Set keytool path to '#{keytool_path}'")

        on_path = find_executable_on_path(jarsigner_executable)

        if on_path
          Logger.debug('Found jarsigner on PATH')
          jarsigner_path = on_path
        else
          if java_sdk_location.nil? || java_sdk_location.empty?
            raise InvalidJavaSDKHome,
                  "Could not locate '#{jarsigner_executable}' on path, and Java SDK Home is invalid."
          end

          jarsigner_path = scan_for_path(java_sdk_location, jarsigner_executable, ['bin'])
        end

        Logger.debug("Set jarsigner path to '#{jarsigner_path}'")

        if java_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{java_executable}' on PATH or in '#{java_sdk_location}'"
        end

        if keytool_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{keytool_executable}' on PATH or in '#{java_sdk_location}'"
        end

        if jarsigner_path.nil?
          raise InvalidEnvironmentError,
                "Could not find '#{jarsigner_executable}' on PATH or in '#{java_sdk_location}'"
        end

        {
            java_path: java_path,
            keytool_path: keytool_path,
            jarsigner_path: jarsigner_path
        }
      end

      def self.scan_for_path(path, file_name, expected_sub_folders = nil)
        # Optimization for expected folders
        if expected_sub_folders && !expected_sub_folders.empty?
          expected_sub_folders.each do |expected_sub_folder|
            result = scan_for_path(File.join(path, expected_sub_folder), file_name)

            return result if result
          end

          Logger.warn("Did not find '#{file_name}' in any standard directory of '#{path}'. Calabash will therefore take longer to load")
          Logger.debug(" - Expected to find '#{file_name}' in any of:")

          expected_sub_folders.each do |expected_sub_folder|
            Logger.debug(" - #{File.join(path, expected_sub_folder)}")
          end
        end

        files = list_files(path).sort.reverse

        if files.reject{|file| File.directory?(file)}.
            map{|file| File.basename(file)}.include?(file_name)
          return File.join(path, file_name)
        else
          files.select{|file| File.directory?(file)}.each do |dir|
            result = scan_for_path(dir, file_name)

            return result if result
          end
        end

        nil
      end

      def self.detect_android_sdk_location
        if File.exist?(monodroid_config_file)
          sdk_location = read_attribute_from_monodroid_config('android-sdk', 'path')

          if sdk_location
            Logger.debug("Setting Android SDK location from '#{monodroid_config_file}'")

            return sdk_location
          end
        end

        if File.exist?('~/Library/Developer/Xamarin/android-sdk-mac_x86/')
          return '~/Library/Developer/Xamarin/android-sdk-mac_x86/'
        end

        if File.exist?('C:\\Android\\android-sdk')
          return 'C:\\Android\\android-sdk'
        end

        if is_windows?
          from_registry = read_registry(::Win32::Registry::HKEY_CURRENT_USER, "Software\\Novell\\Mono for Android", 'AndroidSdkDirectory')

          if from_registry && File.exist?(from_registry)
            Logger.debug("Setting Android SDK location from HKEY_CURRENT_USER Software\\Novell\\Mono for Android")
            return from_registry
          end

          from_registry = read_registry(::Win32::Registry::HKEY_LOCAL_MACHINE, 'Software\\Android SDK Tools', 'Path')

          if from_registry && File.exist?(from_registry)
            Logger.debug("Setting Android SDK location from HKEY_LOCAL_MACHINE Software\\Android SDK Tools")
            return from_registry
          end
        end

        nil
      end

      def self.detect_java_sdk_location
        if File.exist?(monodroid_config_file)
          sdk_location = read_attribute_from_monodroid_config('java-sdk', 'path')

          if sdk_location
            Logger.debug("Setting Java SDK location from '#{monodroid_config_file}'")

            return sdk_location
          end
        end

        java_versions = ['1.9', '1.8', '1.7', '1.6']

        if is_windows?
          java_versions.each do |java_version|
            key = "SOFTWARE\\JavaSoft\\Java Development Kit\\#{java_version}"
            from_registry = read_registry(::Win32::Registry::HKEY_LOCAL_MACHINE, key, 'JavaHome')

            if from_registry && File.exist?(from_registry)
              Logger.debug("Setting Java SDK location from HKEY_LOCAL_MACHINE #{key}")
              return from_registry
            end
          end
        end

        nil
      end

      def self.monodroid_config_file
        File.expand_path('~/.config/xbuild/monodroid-config.xml')
      end

      def self.read_attribute_from_monodroid_config(element, attribute)
        element = REXML::Document.new(IO.read(monodroid_config_file)).elements["//#{element}"]

        if element
          element.attributes[attribute]
        else
          nil
        end
      end

      def self.find_executable_on_path(executable)
        path_elements.each do |x|
          f = File.join(x, executable)
          return f if File.exist?(f)
        end

        nil
      end

      def self.path_elements
        return [] unless Environment.variable('PATH')
        Environment.variable('PATH').split (/[:;]/)
      end

      def self.zipalign_executable
        is_windows? ? 'zipalign.exe' : 'zipalign'
      end

      def self.jarsigner_executable
        is_windows? ? 'jarsigner.exe' : 'jarsigner'
      end

      def self.java_executable
        is_windows? ? 'java.exe' : 'java'
      end

      def self.keytool_executable
        is_windows? ? 'keytool.exe' : 'keytool'
      end

      def self.adb_executable
        is_windows? ? 'adb.exe' : 'adb'
      end

      def self.aapt_executable
        is_windows? ? 'aapt.exe' : 'aapt'
      end

      def self.ant_executable
        is_windows? ? 'ant.exe' : 'ant'
      end

      def self.is_windows?
        (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
      end

      def self.read_registry(root_key, key, value)
        begin
          root_key.open(key)[value]
        rescue
          nil
        end
      end

      def self.list_files(path)
        # Dir.glob does not accept backslashes, even on windows. We have to
        # substitute all backwards slashes to forward.
        # C:\foo becomes C:/foo

        if is_windows?
          Dir.glob(File.join(path, '*').gsub('\\', '/'))
        else
          Dir.glob(File.join(path, '*'))
        end
      end
    end
  end
end
