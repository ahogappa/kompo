# frozen_string_literal: true

require 'nokogiri'
require 'sqlite3'
require 'msgpack'

puts '=== Native Gems Test ==='
puts ''

# Test 1: Nokogiri
puts '--- Nokogiri Test ---'
html = '<html><body><h1>Hello</h1><p>World</p></body></html>'
doc = Nokogiri::HTML(html)
puts "Title: #{doc.at('h1').text}"
puts "Paragraph: #{doc.at('p').text}"
puts ''

# Test 2: SQLite3
puts '--- SQLite3 Test ---'
db = SQLite3::Database.new(':memory:')

db.execute <<-SQL
  CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    data BLOB
  );
SQL

# Test 2: MessagePack - serialize data to store in SQLite
puts '--- MessagePack Test ---'
user_data = { role: 'admin', permissions: %w[read write delete], active: true }
packed = MessagePack.pack(user_data)
puts "Packed data size: #{packed.bytesize} bytes"

# Insert user with MessagePack serialized data
db.execute('INSERT INTO users (name, data) VALUES (?, ?)', ['Alice', packed])
db.execute('INSERT INTO users (name, data) VALUES (?, ?)',
           ['Bob', MessagePack.pack({ role: 'user', permissions: ['read'], active: true })])

# Retrieve and deserialize
puts ''
puts '--- Combined Test (SQLite + MessagePack) ---'
db.execute('SELECT id, name, data FROM users') do |row|
  id, name, data = row
  unpacked = MessagePack.unpack(data)
  puts "User #{id}: #{name}"
  puts "  Role: #{unpacked['role']}"
  puts "  Permissions: #{unpacked['permissions'].join(', ')}"
  puts "  Active: #{unpacked['active']}"
  puts ''
end

puts 'SUCCESS: nokogiri, sqlite3 and msgpack are working correctly!'
