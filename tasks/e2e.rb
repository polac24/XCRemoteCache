require 'json'

desc 'Support for E2E tests: building XCRemoteCache-enabled xcodeproj using xcodebuild'
namespace :e2e do
    COCOAPODS_DIR = 'cocoapods-plugin'
    COCOAPODS_GEMSPEC_FILENAME = "cocoapods-xcremotecache.gemspec"
    E2E_COCOAPODS_SAMPLE_DIR = 'e2eTests/XCRemoteCacheSample'
    E2E_STANDALONE_SAMPLE_DIR = 'e2eTests/StandaloneSampleApp'
    GIT_REMOTE_NAME = 'self'
    # Location of the remote address that points to itself
    GIT_REMOTE_ADDRESS = '.'
    GIT_BRANCH = 'e2e-test-branch'
    LOG_NAME = "xcodebuild.log"
    DERIVED_DATA_PATH = './DerivedData'
    NGINX_ROOT_DIR = '/tmp/cache'
    XCRC_BINARIES = 'XCRC'
    SHARED_COCOAPODS_CONFIG = {
        'cache_addresses' => ['http://localhost:8080/cache/pods'], 
        'primary_repo' => GIT_REMOTE_ADDRESS,
        'primary_branch' => GIT_BRANCH,
        'mode' => 'consumer',
        'final_target' => 'XCRemoteCacheSample',
        'artifact_maximum_age' => 0
    }

    Stats = Struct.new(:hits, :misses, :hit_rate)

    # run E2E tests
    task :run => [:run_cocoapods, :run_standalone]

    # run E2E tests for CocoaPods-powered projects
    task :run_cocoapods do
        install_cocoapods_plugin
        start_nginx
        configure_git

        # Run scenarios for all Podfile scenarios
        for podfile_path in Dir.glob('e2eTests/**/*.Podfile')
            run_cocoapods_scenario(podfile_path)
        end
        # Revert all side effects
        clean
    end

    # run E2E tests for standalone (non-CocoaPods) projects
    task :run_standalone do
        clean_server
        start_nginx
        configure_git
        # Prepare binaries for the standalone mode
        prepare_for_standalone(E2E_STANDALONE_SAMPLE_DIR)

        puts 'Building standalone producer...'
        ####### Producer #########
        Dir.chdir(E2E_STANDALONE_SAMPLE_DIR) do
            clean_git
            # Run integrate the project
            p "#{XCRC_BINARIES}/xcprepare integrate --input StandaloneApp.xcodeproj --mode producer --final-producer-target StandaloneApp"
            system("pwd")
            system("#{XCRC_BINARIES}/xcprepare integrate --input StandaloneApp.xcodeproj --mode producer --final-producer-target StandaloneApp")
            # Build the project to fill in the cache
            build_project(nil, "StandaloneApp.xcodeproj", 'StandaloneApp')
            system("#{XCRC_BINARIES}/xcprepare stats --reset --format json")
        end

        puts 'Building standalone consumer...'

        ####### Consumer #########
        # new dir to emulate different srcroot
        consumer_srcroot = "#{E2E_STANDALONE_SAMPLE_DIR}_consumer"
        system("mv #{E2E_STANDALONE_SAMPLE_DIR} #{consumer_srcroot}")
        at_exit { puts("reverting #{E2E_STANDALONE_SAMPLE_DIR}"); system("mv #{consumer_srcroot} #{E2E_STANDALONE_SAMPLE_DIR}") }

        prepare_for_standalone(consumer_srcroot)
        Dir.chdir(consumer_srcroot) do
            system("#{XCRC_BINARIES}/xcprepare integrate --input StandaloneApp.xcodeproj --mode consumer")
            build_project(nil, "StandaloneApp.xcodeproj", 'StandaloneApp', {'derivedDataPath' => "#{DERIVED_DATA_PATH}_consumer"})
            valide_hit_rate

            puts 'Building standalone consumer with local change...'
            # Extra: validate local compilation of the Standalone ObjC code
            system("echo '' >> StandaloneApp/StandaloneObjc.m")
            build_project(nil, "StandaloneApp.xcodeproj", 'StandaloneApp', {'derivedDataPath' => "#{DERIVED_DATA_PATH}_consumer_local"})
        end

        # Revert all side effects
        clean
    end

    # Build and install a plugin
    def self.install_cocoapods_plugin
        Dir.chdir(COCOAPODS_DIR) do
            gemfile_path = "cocoapods-xcremotecache.gem"
            system("gem build #{COCOAPODS_GEMSPEC_FILENAME} -o #{gemfile_path}")
            system("gem install #{gemfile_path}")
        end
    end

    def self.start_nginx
        # Start nginx server
        system('nginx -c $PWD/e2eTests/nginx/nginx.conf')
        puts('starting nginx')
        # Call cleanup on exit
        at_exit { puts('resetting ngingx'); system('nginx -s stop') }
    end

    # Create a new branch out of a current commit and 
    # add remote that points to itself
    def self.configure_git
        system("git checkout -B #{GIT_BRANCH}")
        system("git remote add #{GIT_REMOTE_NAME} #{GIT_REMOTE_ADDRESS} && git fetch -q #{GIT_REMOTE_NAME}")
        # Revert new remote on exit
        at_exit { system("git remote remove #{GIT_REMOTE_NAME}")}
    end

    def self.pre_producer_setup
        clean_git
        clean_server
        # Link prebuilt binaries to the Project
        system("ln -s $(pwd)/releases #{E2E_COCOAPODS_SAMPLE_DIR}/#{XCRC_BINARIES}")
    end

    def self.pre_consumer_setup
        clean_git
        # Link prebuilt binaries to the Project
        system("ln -s $(pwd)/releases #{E2E_COCOAPODS_SAMPLE_DIR}/#{XCRC_BINARIES}")
    end

    def self.clean_server
        system("rm -rf #{NGINX_ROOT_DIR}")
    end

    # Revert any local changes in the test project
    def self.clean_git
        system("git clean -xdf #{E2E_COCOAPODS_SAMPLE_DIR}")
    end

    # Cleans all extra locations that a test creates
    def self.clean
        clean_git
        clean_server
    end

    # xcremotecache configuration to add to Podfile
    def self.cocoapods_configuration_string(extra_configs = {})
        configuration_lines = ['xcremotecache({']
        all_properties = SHARED_COCOAPODS_CONFIG.merge(extra_configs)
        config_lines = all_properties.map {|key, value| "    \"#{key}\" => #{value.inspect},"} 
        configuration_lines.push(*config_lines)
        configuration_lines << '})'
        configuration_lines.join("\n")
    end

    def self.dump_podfile(config, source)
        # Create producer Podfile
        File.open("#{E2E_COCOAPODS_SAMPLE_DIR}/Podfile", 'w') do |f|
            # Copy podfile template
            File.foreach(source) { |line| f.puts line }
            f.write(config)
        end
    end

    def self.build_project(workspace, project, scheme, extra_args = {})
        xcodebuild_args = {
            'workspace' => workspace,
            'project' => project,
            'scheme' => scheme,
            'configuration' => 'Debug',
            'sdk' => 'iphonesimulator',
            'destination' => 'generic/platform=iOS Simulator',
            'derivedDataPath' => DERIVED_DATA_PATH,
        }.merge(extra_args).compact
        xcodebuild_vars = {
            'EXCLUDED_ARCHS' => 'arm64 i386'
        }
        args = ['xcodebuild']
        args.push(*xcodebuild_args.map {|k,v| "-#{k} '#{v}'"})
        args.push(*xcodebuild_vars.map {|k,v| "#{k}='#{v}'"})
        args.push('clean build')
        args.push("> #{LOG_NAME}")
        puts 'Building a project with xcodebuild...'
        system(args.join(' '))
        unless $?.success?
            system("tail #{LOG_NAME}")
            raise "xcodebuild failed."
        end
    end

    def self.build_project_cocoapods(extra_args = {})
        system('pod install')
        build_project('XCRemoteCacheSample.xcworkspace', nil, 'XCRemoteCacheSample', extra_args)
    end

    def self.read_stats 
        stats_json_string = JSON.parse(`#{XCRC_BINARIES}/xcprepare stats --format json`)
        misses = stats_json_string.fetch('miss_count', 0)
        hits = stats_json_string.fetch('hit_count', 0)
        all_targets = misses + hits
        raise "Failure: No XCRemoteCache targets invoked" if all_targets == 0
        hit_rate = hits * 100 / all_targets
        Stats.new(hits, misses, hit_rate)
    end

    # validate 100% hit rate
    def self.valide_hit_rate
        status = read_stats()
        all_targets = status.misses + status.hits
        raise "Failure: Hit rate is only #{status.hit_rate}% (#{all_targets})" if status.misses > 0
        puts("Hit rate: #{status.hit_rate}% (#{status.hits}/#{all_targets})")
    end

    def self.run_cocoapods_scenario(template_path)
        producer_configuration = cocoapods_configuration_string({'mode' => 'producer'})
        consumer_configuration = cocoapods_configuration_string()

        puts("****** Scenario: #{template_path}")
            
        # Run producer build
        pre_producer_setup
        dump_podfile(producer_configuration, template_path)
        puts('Building producer ...')
        Dir.chdir(E2E_COCOAPODS_SAMPLE_DIR) do
            build_project_cocoapods
            # reset XCRemoteCache stats
            system("#{XCRC_BINARIES}/xcprepare stats --reset --format json")
        end

        # Run consumer build
        pre_consumer_setup
        dump_podfile(consumer_configuration, template_path)
        puts('Building consumer ...')
        Dir.chdir(E2E_COCOAPODS_SAMPLE_DIR) do
            build_project_cocoapods({'derivedDataPath' => "#{DERIVED_DATA_PATH}_consumer"})
            valide_hit_rate
        end
    end

    def self.prepare_for_standalone(dir)
        clean_git
        system("ln -s $(pwd)/releases #{dir}/#{XCRC_BINARIES}")
    end
end
