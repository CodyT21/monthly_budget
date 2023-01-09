require 'sinatra'
require 'tilt/erubis'

require_relative 'database_persistance'

configure do
  enable :sessions
  set :session_secret, 'secret'

  set :erb, :escape_html => true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'database_persistance.rb' if development?
end

before do
  @storage = DatabasePersistance.new(logger)
end

# render home page
get '/' do
  redirect '/budget'
end

get '/budget' do
  @budgets = @storage.budget_amounts_remaining
  @expenses = @storage.last_n_expenses(5)
  
  erb :budget
end

# display all expenses
get '/budget/expenses' do
  @expenses = @storage.all_expenses

  erb :expenses
end

# display new expense form
get '/budget/expenses/new' do
  erb :new_expense
end

# add new expense
post '/budget/expenses' do
  description = params[:description].strip
  amount = params[:amount].to_f.round(2)
  category = params[:category].strip
  category_id = @storage.find_category(category)
  @storage.add_new_expense(description, amount, category_id)
  session[:message] = 'Successfully added expense.'

  redirect '/budget'
end
  
