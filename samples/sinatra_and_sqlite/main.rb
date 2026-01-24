# frozen_string_literal: true

require_relative 'src/server'
require 'sinatra'

set :bind, '0.0.0.0'
set :run, true

get '/' do
  rows = $db.execute 'select * from numbers;'
  rows.to_s
end

get '/hello' do
  Hello::World
end
