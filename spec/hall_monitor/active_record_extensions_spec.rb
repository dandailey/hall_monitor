require "spec_helper"

RSpec.describe HallMonitor::ActiveRecordExtensions do
  let!(:changes) { capture_changes }

  it "emits a create with the new values" do
    record = TestModel.create!(name: "a")

    expect(changes.size).to eq(1)
    expect(changes.first.operation).to eq("c")
    expect(changes.first.table).to eq("test_models")
    expect(changes.first.primary_key_name).to eq("id")
    expect(changes.first.primary_key_value).to eq(record.id)
    expect(changes.first.old_value_for(:name)).to be_nil
    expect(changes.first.new_value_for(:name)).to eq("a")
  end

  it "emits an update with only the fields that changed" do
    record = TestModel.create!(name: "a", description: "same")
    changes.clear

    TestModel.find(record.id).update!(name: "b")

    expect(changes.size).to eq(1)
    expect(changes.first.operation).to eq("u")
    expect(changes.first.changed_fields).to eq(["name"])
    expect(changes.first.old_value_for(:name)).to eq("a")
    expect(changes.first.new_value_for(:name)).to eq("b")
  end

  it "tracks consecutive updates on the same instance" do
    record = TestModel.create!(name: "a")
    record.update!(name: "b")
    changes.clear

    record.update!(name: "c")

    expect(changes.first.old_value_for(:name)).to eq("b")
    expect(changes.first.new_value_for(:name)).to eq("c")
  end

  it "emits a destroy with the old values" do
    record = TestModel.create!(name: "a")
    changes.clear

    TestModel.find(record.id).destroy!

    expect(changes.size).to eq(1)
    expect(changes.first.operation).to eq("d")
    expect(changes.first.old_value_for(:name)).to eq("a")
    expect(changes.first.new_value_for(:name)).to be_nil
  end

  it "waits for the transaction to commit" do
    emitted_inside_transaction = nil

    TestModel.transaction do
      TestModel.create!(name: "a")
      TestModel.create!(name: "b")
      emitted_inside_transaction = changes.size
    end

    expect(emitted_inside_transaction).to eq(0)
    expect(changes.size).to eq(2)
  end

  it "emits nothing for a rolled back transaction" do
    TestModel.transaction do
      TestModel.create!(name: "a")
      raise ActiveRecord::Rollback
    end
    TestModel.create!(name: "b")

    expect(changes.map { |change| change.new_value_for(:name) }).to eq(["b"])
  end

  it "finds the record from a change" do
    record = TestModel.create!(name: "a")

    expect(changes.first.record).to eq(record)
  end

  describe "with watchers routed from the emitter" do
    let(:fired) { [] }

    before do
      HallMonitor.configure { |config| config.emitter = ->(data_change) { HallMonitor.consume_data_change(data_change) } }
    end

    def watch(field_map, **options)
      HallMonitor.register_watcher(
        HallMonitor::Watcher.new(field_map: field_map, callback: ->(data_change) { fired << data_change.operation }, **options)
      )
    end

    it "fires only for changes to the watched path in a JSON column" do
      watch({TestModel => ["metadata.status"]})
      record = TestModel.create!(metadata: {"status" => "new", "other" => 1})
      fired.clear

      TestModel.find(record.id).update!(metadata: {"status" => "new", "other" => 2})
      expect(fired).to be_empty

      TestModel.find(record.id).update!(metadata: {"status" => "paid", "other" => 2})
      expect(fired).to eq(["u"])
    end

    it "fires a whole-table destroy watcher" do
      watch(TestModel, operations: [:destroy])
      record = TestModel.create!(name: "a")

      TestModel.find(record.id).destroy!

      expect(fired).to eq(["d"])
    end
  end
end
