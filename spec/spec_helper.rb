require "bundler/setup"
require "hall_monitor"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :test_models do |t|
    t.string :name
    t.string :description
    t.json :metadata
  end
end

class TestModel < ActiveRecord::Base
  include HallMonitor::ActiveRecordExtensions
end

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset HallMonitor configuration between tests
  config.before(:each) do
    HallMonitor.configure do |c|
      c.publisher_name = "Hall Monitor"
      c.producer_topic = "hall_monitor"
      c.emitter = ->(_data_change) {}
      c.consumer = ->(_data_change) {}
    end
    HallMonitor.watchers.clear
    TestModel.delete_all
  end
end

# Helper methods for testing
def capture_changes
  changes = []
  HallMonitor.configure do |config|
    config.emitter = ->(data_change) {
      changes << data_change
    }
  end
  changes
end
