# Native Gems Sample

A sample application that uses native extension gems (sqlite3 and msgpack) to verify kompo can correctly bundle and run binaries with native dependencies.

## What it does

1. Creates an in-memory SQLite database
2. Serializes user data using MessagePack
3. Stores serialized data in SQLite
4. Retrieves and deserializes the data
5. Outputs the results

## Build

```sh
bundle install
kompo -o .
```

## Expected output

```text
=== Native Gems Test ===

--- SQLite3 Test ---
--- MessagePack Test ---
Packed data size: 51 bytes

--- Combined Test (SQLite + MessagePack) ---
User 1: Alice
  Role: admin
  Permissions: read, write, delete
  Active: true

User 2: Bob
  Role: user
  Permissions: read
  Active: true

SUCCESS: sqlite3 and msgpack are working correctly!
```
