# Native Gems Sample

A sample application that uses native extension gems (nokogiri, sqlite3, and msgpack) to verify kompo can correctly bundle and run binaries with native dependencies.

## What it does

1. Parses HTML using Nokogiri
2. Creates an in-memory SQLite database
3. Serializes user data using MessagePack
4. Stores serialized data in SQLite
5. Retrieves and deserializes the data
6. Outputs the results

## Build

```sh
bundle install
kompo -o .
```

## Expected output

```text
=== Native Gems Test ===

--- Nokogiri Test ---
Title: Hello
Paragraph: World

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

SUCCESS: nokogiri, sqlite3 and msgpack are working correctly!
```
