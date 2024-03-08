# frozen_string_literal: true

namespace :tags do
  desc 'create a new tag locally and remotely'
  task :create do
    # check that the current branch is develop
    puts "checking that current branch is 'develop'"
    current_branch = `git branch --show-current`
    if !Process.last_status.success? || current_branch != "develop\n"
      raise "this rake can only be run from 'develop' branch\n"
    end

    # fetch latest xing_mobile_fork state
    puts 'fetching remote branch & tags'
    `git fetch xing_mobile_fork --tags`
    raise "this rake can only be run with an 'xing_mobile_fork' remote setup\n" unless Process.last_status.success?

    # check that there are no differences between develop and remote develop
    puts 'checking diffs between local and remote develop'
    differences = `git diff --name-only develop xing_mobile_fork/develop`
    raise "please pull the latest changes to 'develop' branch\n" if !Process.last_status.success? || differences != ''

    # check that there are no remote tags with same number
    current_version = Calabash::VERSION
    current_version_name = "v#{current_version}"
    puts "checking that no tag '#{current_version_name}' exists"
    tags_string = `git tag`
    tags_array = tags_string.split "\n"
    if tags_array.include? current_version_name
      raise "the tag '#{current_version_name}' already exists in the 'xing_mobile_fork' remote, please bump the version further\n"
    end

    # create a local tag
    puts "creating local tag '#{current_version_name}'"
    `git tag -a #{current_version_name} -m "Version #{current_version}"`
    raise "failed to create the tag '#{current_version_name}' locally\n" unless Process.last_status.success?

    # push the tag to remote (or rollback)
    puts "pushing the tag '#{current_version_name}' to remote"
    `git push xing_mobile_fork #{current_version_name}`
    unless Process.last_status.success?
      puts "deleting the local tag '#{current_version_name}' because pushing failed"
      `git tag -d #{current_version_name}`

      raise "failed to push the tag '#{current_version_name}' to remote\n"
    end
  end
end
