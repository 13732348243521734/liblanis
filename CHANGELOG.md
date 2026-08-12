## 0.1.2

* Stop duplicating substitution days when a personal-plan shell uses underscore `data-tag` values together with `#tagDD_MM_YYYY` panels.
* Add a production-shaped synthetic fixture and parser tests for that layout.

## 0.1.1

* Update the pub.dev package description and README listing.

## 0.1.0

* Initial package extract of the SPH client stack from lanis-mobile.
* Riverpod providers for accounts, session, connection status, settings, and applets.
* `EasyLanisClient` imperative API without Riverpod.
* Unified optional `sqlite3` database (in-memory by default).
* Injectable `SecretStore`, configurable `StorageManager`, English-only exceptions.
* Fixture-driven hardening for substitutions, timetable, and calendar parsers.
