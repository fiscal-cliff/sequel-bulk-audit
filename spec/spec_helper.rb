require "bundler/setup"
require "sequel"
require "sequel/extensions/migration"
require "sequel-bulk-audit"
require "sequel/plugins/bulk_audit"
require 'yaml'
require 'pry'

DB_NAME = (ENV['DB_NAME'] || "audit_test").freeze

def connect
  Sequel.connect("postgres:///#{DB_NAME}")
rescue Sequel::DatabaseConnectionError => e
  raise unless e.message.include? "database \"#{DB_NAME}\" does not exist"
  Sequel.connect('postgres:///postgres') do |connect|
    connect.run("create database #{DB_NAME}")
  end
  Sequel.connect("postgres:///#{DB_NAME}")
end

db = connect

Sequel::DATABASES.first.extension :pg_json
::Sequel::Migrator.run(db, 'lib/generators/audit_migration/templates')

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  tables = %i[data1 data2 data3]

  config.before(:all) do
    data = YAML.load(IO.read("spec/fixtures/data.yml"))

    tables.each do |t|
      db.drop_table?(t)
      db.create_table(t) do
        primary_key :id
        DateTime :created_at
        DateTime :updated_at
        String :value
      end
      db[t].multi_insert(data)
      id = db[t].max(:id) + 1
      db.execute(<<-SQL)
        ALTER SEQUENCE #{t}_id_seq RESTART WITH #{id};
      SQL
      db.run(<<~SQL)
        CREATE TRIGGER audit_changes_on_data BEFORE INSERT OR UPDATE OR DELETE ON #{t}
        FOR EACH ROW EXECUTE PROCEDURE audit_changes();
      SQL
    end
  end

  config.after(:all) do
    tables.each do |t|
      db.drop_table?(t)
    end
  end
end
