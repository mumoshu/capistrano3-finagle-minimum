set :application, 'finagle_sample_app'
set :repo_url, 'git@github.com:mumoshu/finagle_sample_app'
set :deploy_to, '/opt/testapps'

framework_tasks = [:starting, :started, :updating, :updated, :publishing, :published, :finishing, :finished]

framework_tasks.each do |t|
  Rake::Task["deploy:#{t}"].clear
#  task t do; end
end

Rake::Task[:deploy].clear
#task :deploy do; end

task :uptime do
  run_locally do
    output = capture "uptime"
    info output
  end
  on roles(:web) do
    output = capture "uptime"
    info output
  end
end

task :update do
  run_locally do
    application = fetch :application
    if test "[ -d #{application} ]"
      execute "cd #{application}; git pull"
    else
      execute "git clone #{fetch :repo_url} #{application}"
    end
  end
end

task :archive => :update do
  run_locally do
    sbt_output = capture "cd #{fetch :application}; sbt pack-archive"

    sbt_output_without_escape_sequences = sbt_output.lines.map { |line| line.gsub(/\e\[\d{1,2}m/, '') }.join

    archive_relative_path = sbt_output_without_escape_sequences.match(/\[info\] Generating (?<archive_path>.+\.tar\.gz)\s*$/)[:archive_path]
    archive_name = archive_relative_path.match(/(?<archive_name>[^\/]+\.tar\.gz)$/)[:archive_name]
    archive_absolute_path = File.join(capture("cd #{fetch(:application)}; pwd").chomp, archive_relative_path)

    info archive_absolute_path
    info archive_name

    set :archive_absolute_path, archive_absolute_path
    set :archive_name, archive_name
  end
end

task :deploy => :archive do
  archive_path = fetch :archive_absolute_path
  archive_name = fetch :archive_name
  release_path = File.join(fetch(:deploy_to), fetch(:application))

  on roles(:web) do
    begin
      old_project_dir = File.join(release_path, capture("cd #{release_path}; ls -d */").chomp)
      if test "[ -d #{old_project_dir} ]"
        running_pid = capture("cd #{old_project_dir}; cat RUNNING_PID")
        execute "kill #{running_pid}"
      end
    rescue => e
      info "No previous release directory exists"
    end

    unless test "[ -d #{release_path} ]"
      execute "mkdir -p #{release_path}"
    end
  
    upload! archive_path, release_path
    
    execute "cd #{release_path}; tar -zxvf #{archive_name}"
    
    project_dir = File.join(release_path, capture("cd #{release_path}; ls -d */").chomp)
    
    launch = capture("cd #{project_dir}; ls bin/*").chomp
    
    execute "cd #{project_dir}; ( ( nohup #{launch} &>/dev/null ) & echo $! > RUNNING_PID)"
  end
end
