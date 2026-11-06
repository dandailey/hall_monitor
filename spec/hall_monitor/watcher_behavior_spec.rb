require "spec_helper"

RSpec.describe HallMonitor::WatcherBase do
  def build_watcher(&definition)
    Class.new(described_class, &definition)
  end

  let(:watcher) { HallMonitor.watchers.last }

  it "registers a watcher using a block" do
    build_watcher { react_to_changes_on(TestModel, [:name]) { |_data_change| } }

    expect(watcher.field_map.map).to eq({"test_models" => ["name"]})
    expect(watcher.operations).to be_nil
  end

  it "registers a watcher using a named class method" do
    received = []
    build_watcher do
      define_singleton_method(:handle) { |data_change| received << data_change }
      react_to_changes_on TestModel, with: :handle
    end

    data_change = HallMonitor::DataChange.new(table: "test_models", operation: :update, changes: {"name" => ["a", "b"]})
    HallMonitor.consume_data_change(data_change)

    expect(received).to eq([data_change])
  end

  it "accepts a whole field map" do
    build_watcher { react_to_changes_on({TestModel => :name}, with: ->(_data_change) {}) }

    expect(watcher.field_map.map).to eq({"test_models" => ["name"]})
  end

  it "limits operations with only" do
    build_watcher { react_to_changes_on(TestModel, only: :create) { |_data_change| } }

    expect(watcher.operations).to eq([:create])
  end

  it "limits operations with except" do
    build_watcher { react_to_changes_on(TestModel, except: [:update]) { |_data_change| } }

    expect(watcher.operations).to eq([:create, :destroy])
  end

  it "registers nothing without a callback" do
    expect { build_watcher { react_to_changes_on(TestModel) } }.not_to change { HallMonitor.watchers.size }
  end
end
