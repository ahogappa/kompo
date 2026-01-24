# frozen_string_literal: true

require 'sqlite3'

require_relative './hello'

File.delete('/tmp/sample.db') if File.exist?('/tmp/sample.db')

$db = SQLite3::Database.new '/tmp/sample.db'

$db.execute <<-SQL
  create table numbers (
    name varchar(30),
    val int
  );
SQL

{
  'one' => 1,
  'two' => 2
}.each do |pair|
  $db.execute 'insert into numbers values ( ?, ? )', pair
end
