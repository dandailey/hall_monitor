# Manages a mapping of fields to tables in a standardized way.
# Flexible input, but gets converted to a standard format for easy comparison.

# ALLOWABLE INPUT FORMAT
# - nil - empty map. No fields are included.
# - {} - wildcard. All fields are included.
# - A string or symbol representing a table name. All fields for this table are included.
# - An ActiveRecord model class, from which a table name will be inferred. All fields are included.
# - A hash with a single key that is a string, symbol, or ActiveRecord model class, where the value is:
#   - Nil - All fields for this table are included
#   - A string or symbol representing a field name
#   - An array of strings or symbols representing field names
#   - A dotted name such as "metadata.status", which watches one path inside a JSON
#     column rather than the whole column. Array elements are addressed by index,
#     for example "metadata.items.0.sku".
# - An array of any of the above options. Each element is treated as a separate table.

# STANDARDIZED FORMAT
# {
#  "table_name" => ["field_name", "field_name", ...],
#  "table_name" => nil, # all fields for this table
#  ...
# }
# All keys and values are strings. Empty hash means all fields are included.
# Can also be a nil, which means no fields are included.
# Nested paths are kept apart from the map, which only ever holds column names:
# { "table_name" => { "field_name" => [["path", "to", "value"], ...] } }

module HallMonitor
  class FieldMap
    attr_reader :map, :nested_paths

    def initialize(map)
      self.map = map
    end

    def map=(map)
      @map, @nested_paths = self.class.parse(map)
    end

    def table_names
      map&.keys
    end

    def includes_everything?
      map == {}
    end

    def excludes_everything?
      map.nil?
    end

    def includes_table?(table_name)
      return true if includes_everything?
      return false if excludes_everything?
      map.key?(table_name)
    end

    def includes_everything_for_table?(table_name)
      return true if includes_everything?
      return false unless includes_table?(table_name)
      map[table_name].nil? # nil means all fields for this table
    end

    def includes_field?(table_name, field)
      return false unless includes_table?(table_name)
      return true if includes_everything_for_table?(table_name)
      map[table_name].include?(field.to_s)
    end

    def nested_paths?(table_name)
      nested_paths.key?(table_name)
    end

    # The JSON paths watched within this field. Empty means the whole field is watched.
    def nested_paths_for(table_name, field)
      nested_paths.dig(table_name, field.to_s) || []
    end

    # Returns true if this field map shares any fields with the other field map.
    def overlaps_with?(other)
      other = self.class.new(other) unless other.is_a?(self.class)
      return false if excludes_everything? || other.excludes_everything?
      return true if includes_everything? || other.includes_everything?

      table_names.any? do |table_name|
        next false unless other.includes_table?(table_name)
        next true if includes_everything_for_table?(table_name) || other.includes_everything_for_table?(table_name)
        (map[table_name] & other.map[table_name]).any?
      end
    end

    def self.build(input)
      input.is_a?(self) ? input : new(input)
    end

    def self.standardize(map)
      parse(map).first
    end

    # Returns the standardized map and the nested paths that go with it.
    def self.parse(map)
      return [nil, {}] if map.nil?
      return [nil, {}] if map.is_a?(Array) && map.empty?

      map = [map] unless map.is_a?(Array)
      standardized = {}
      nested_paths = {}
      whole_fields = {}

      map.each do |option|
        next if option.nil?
        option = {option => nil} unless option.is_a?(Hash)

        option.each do |key, value|
          next if key.nil? || key.to_s.strip.empty?

          table_name = (key.is_a?(Class) && key < ActiveRecord::Base) ? key.table_name : key.to_s

          if value.nil?
            standardized[table_name] = nil # all columns for this table
            next
          end
          next if standardized.key?(table_name) && standardized[table_name].nil?

          fields = standardized[table_name] ||= []
          Array(value).map(&:to_s).each do |attribute|
            field, *path = attribute.split(".")
            fields << field unless fields.include?(field)

            if path.empty?
              (whole_fields[table_name] ||= []) << field
            else
              paths = ((nested_paths[table_name] ||= {})[field] ||= [])
              paths << path unless paths.include?(path)
            end
          end
        end
      end

      [standardized, prune_nested_paths(nested_paths, standardized, whole_fields)]
    end

    # Watching a whole column or table is broader than watching a path inside it, so the broader watch wins.
    def self.prune_nested_paths(nested_paths, standardized, whole_fields)
      nested_paths.each_with_object({}) do |(table_name, fields), pruned|
        next if standardized[table_name].nil?

        remaining = fields.reject { |field, _paths| whole_fields.fetch(table_name, []).include?(field) }
        pruned[table_name] = remaining unless remaining.empty?
      end
    end
    private_class_method :prune_nested_paths
  end
end
