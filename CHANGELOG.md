# Changelog

This project follows [Semantic Versioning](https://semver.org). Install a release by its git tag.

## [0.7.0] - 2026-11-06

The version jumps from 0.1.0 so that `~> 0.7` cannot match the unrelated `hall_monitor` gem on RubyGems, which stops at 0.6.0.

### Added

- Field maps accept dotted names such as `metadata.status`, which watch a value inside a JSON column. Several paths in one column are supported.

### Changed

- A whole-table entry now wins over a field entry for the same table, in either order. Previously a table followed by a field narrowed the watch to that field.
- Removed the upper limit on `activerecord` and `activesupport` (Brady Dullanty).
- The test suite runs against the real gem and a real database instead of mocks.

### Fixed

- `DataChange#as_hash` no longer raises in an app without a `Current` model.

## [0.1.0] - 2025-03-21

- Initial release
