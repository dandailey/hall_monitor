require "spec_helper"

RSpec.describe HallMonitor::Watcher do
  let(:callback) { ->(data_change) { @change_detected = true } }
  let(:test_model_table) { TestModel.table_name }

  before do
    @change_detected = false
  end

  describe "#initialize" do
    it "creates a watcher with the field_map and callback" do
      watcher = described_class.new(
        field_map: {TestModel => :name},
        callback: callback
      )

      expect(watcher.field_map).to be_a(HallMonitor::FieldMap)
      expect(watcher.callback).to eq(callback)
      expect(watcher.operations).to be_nil
    end

    it "accepts an operations parameter" do
      watcher = described_class.new(
        field_map: {TestModel => :name},
        callback: callback,
        operations: [:create, :update]
      )

      expect(watcher.operations).to contain_exactly(:create, :update)
    end
  end

  describe "#interested_in?" do
    let(:watcher) do
      described_class.new(
        field_map: {TestModel => ["name", "description"]},
        callback: callback
      )
    end

    it "returns true when data change matches the field map" do
      data_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"name" => ["Old Name", "New Name"]}
      )

      expect(watcher.interested_in?(data_change)).to be true
    end

    it "returns false when data change doesn't match the field map" do
      data_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"other_field" => ["Old Value", "New Value"]}
      )

      expect(watcher.interested_in?(data_change)).to be false
    end

    it "respects the operations filter" do
      watcher_with_operations = described_class.new(
        field_map: {TestModel => :name},
        callback: callback,
        operations: [:update]
      )

      create_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :create,
        changes: {"name" => [nil, "New Name"]}
      )

      update_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"name" => ["Old Name", "New Name"]}
      )

      expect(watcher_with_operations.interested_in?(create_change)).to be false
      expect(watcher_with_operations.interested_in?(update_change)).to be true
    end
  end

  describe "#execute_if_interested" do
    let(:watcher) do
      described_class.new(
        field_map: {TestModel => :name},
        callback: callback
      )
    end

    it "executes the callback when interested" do
      data_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"name" => ["Old Name", "New Name"]}
      )

      watcher.execute_if_interested(data_change)

      expect(@change_detected).to be true
    end

    it "doesn't execute the callback when not interested" do
      data_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"other_field" => ["Old Value", "New Value"]}
      )

      watcher.execute_if_interested(data_change)

      expect(@change_detected).to be false
    end

    it "handles errors in the callback" do
      error_callback = ->(data_change) { raise "Test error" }
      error_watcher = described_class.new(
        field_map: {TestModel => :name},
        callback: error_callback
      )

      data_change = HallMonitor::DataChange.new(
        table: test_model_table,
        operation: :update,
        changes: {"name" => ["Old Name", "New Name"]}
      )

      expect { error_watcher.execute_if_interested(data_change) }.to raise_error("Test error")
    end
  end

  describe "#interested_in? with nested paths" do
    def change(old_value, new_value)
      HallMonitor::DataChange.new(table: "orders", operation: :update, changes: {"metadata" => [old_value, new_value]})
    end

    def watcher_for(*fields)
      described_class.new(field_map: {"orders" => fields}, callback: callback)
    end

    it "fires when the watched value changes" do
      expect(watcher_for("metadata.status").interested_in?(change({"status" => "a"}, {"status" => "b"}))).to be true
    end

    it "does not fire when only another value in the column changes" do
      expect(watcher_for("metadata.status").interested_in?(change({"status" => "a", "x" => 1}, {"status" => "a", "x" => 2}))).to be false
    end

    it "checks every path watched in a column" do
      watcher = watcher_for("metadata.a", "metadata.b")
      expect(watcher.interested_in?(change({"a" => 1, "b" => 1}, {"a" => 2, "b" => 1}))).to be true
      expect(watcher.interested_in?(change({"a" => 1, "b" => 1}, {"a" => 1, "b" => 2}))).to be true
    end

    it "fires when the column is watched as a whole as well" do
      expect(watcher_for("metadata", "metadata.a").interested_in?(change({"a" => 1, "b" => 1}, {"a" => 1, "b" => 2}))).to be true
    end

    it "fires on another watched column in the same change" do
      data_change = HallMonitor::DataChange.new(table: "orders", operation: :update, changes: {"name" => ["a", "b"], "metadata" => [{"a" => 1}, {"a" => 1}]})
      expect(watcher_for("metadata.a", "name").interested_in?(data_change)).to be true
    end

    it "reads symbol keys, array indexes and raw JSON strings" do
      expect(watcher_for("metadata.a").interested_in?(change({a: 1}, {a: 2}))).to be true
      expect(watcher_for("metadata.items.0.sku").interested_in?(change({"items" => [{"sku" => "x"}]}, {"items" => [{"sku" => "y"}]}))).to be true
      expect(watcher_for("metadata.a").interested_in?(change('{"a":1}', '{"a":2}'))).to be true
    end

    it "fires when a value appears or disappears" do
      expect(watcher_for("metadata.a").interested_in?(change(nil, {"a" => 1}))).to be true
      expect(watcher_for("metadata.a").interested_in?(change({"a" => 1}, nil))).to be true
    end

    it "does not raise when a path runs through a scalar or unparseable value" do
      watcher = watcher_for("metadata.a.b")
      expect(watcher.interested_in?(change({"a" => "text"}, {"a" => 5}))).to be false
      expect(watcher.interested_in?(change("not json", "still not json"))).to be false
    end

    it "still fires a whole-table watcher for an event with no changed fields" do
      watcher = described_class.new(field_map: "orders", callback: callback)
      data_change = HallMonitor::DataChange.new(table: "orders", operation: :destroy, changes: {})
      expect(watcher.interested_in?(data_change)).to be true
    end
  end
end
