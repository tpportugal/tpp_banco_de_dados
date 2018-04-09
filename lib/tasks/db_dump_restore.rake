namespace :db do

    desc "Dumps the database to backups"
    task :dump => :environment do
        cmd = nil
        with_config do |app, host, db, user|
            cmd = "pg_dump -F c -v -h #{host} -d #{db} -f #{Rails.root}/db/backups/#{Time.now.strftime("%Y%m%d%H%M%S")}_#{db}.psql"
        end
        puts cmd
        exec cmd
    end

    desc "Restores the database from backups"
    task :restore, [:date] => :environment do |task,args|
        if args.date.present?
            cmd = nil
            with_config do |app, host, db, user|
                cmd = "pg_restore -v -c -C #{Rails.root}/db/backups/#{args.date}_#{db}.psql"
            end
            Rake::Task["db:drop"].invoke
            Rake::Task["db:create"].invoke
            puts cmd
            exec cmd
        else
            puts 'Please pass a date to the task'
        end
    end

    private

    def with_config
        yield Rails.application.class.parent_name.underscore,
        ActiveRecord::Base.connection_config[:hostname],
        ActiveRecord::Base.connection_config[:database],
        ActiveRecord::Base.connection_config[:user]
    end

end
