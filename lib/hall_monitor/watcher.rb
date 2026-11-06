require "json"

module HallMonitor
  class Watcher
    attr_reader :field_map, :operations, :callback

    def initialize(field_map:, callback:, operations: nil)
      @field_map = HallMonitor::FieldMap.build(field_map)
      @operations = operations&.map(&:to_sym) # normalize
      @callback = callback
    end

    def execute_if_interested(data_change)
      return unless interested_in?(data_change)
      callback.call(data_change)
    rescue => e
      # Use a safe logger approach that works in both Rails and non-Rails environments
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger.error("[HallMonitor] Watcher encountered an error: #{e.message}")
      else
        puts "[HallMonitor] Watcher encountered an error: #{e.message}"
      end
      raise e
    end

    def interested_in?(data_change)
      return false if operations && !operations.include?(data_change_operation(data_change))
      return false unless field_map.overlaps_with?(data_change.table => data_change.changed_fields)
      return true unless field_map.nested_paths?(data_change.table)

      data_change.changed_fields.any? do |field|
        next false unless field_map.includes_field?(data_change.table, field)

        paths = field_map.nested_paths_for(data_change.table, field)
        paths.empty? || paths.any? { |path| nested_value_changed?(data_change, field, path) }
      end
    end

    private

    def nested_value_changed?(data_change, field, path)
      old_value = dig_path(data_change.old_value_for(field), path)
      new_value = dig_path(data_change.new_value_for(field), path)
      old_value != new_value
    end

    def dig_path(value, path)
      path.reduce(parse_json_string(value)) do |current, key|
        case current
        when Hash then current.key?(key) ? current[key] : current[key.to_sym]
        when Array then key.match?(/\A\d+\z/) ? current[key.to_i] : nil
        end
      end
    end

    # Change events that arrive from outside Rails can carry JSON columns as raw strings.
    def parse_json_string(value)
      return value unless value.is_a?(String)
      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def data_change_operation(data_change)
      case data_change.operation
      when "c" then :create
      when "u" then :update
      when "d" then :destroy
      else
        :unknown
      end
    end
  end
end
