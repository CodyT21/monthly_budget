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

def error_for_new_expense(description, amount, category)
  if !(1..255).cover? description.size
    return 'Expense description must be between 1 and 255 characters.'
  elsif !(amount =~ /^\d{1,4}(?:\.\d{1,2})?$/)
    return 'Enter a valid amount between 0.00 and 9999.99.'
  elsif !(1..100).cover? category.size
    return 'Category name must be between 1 and 100 characters.'
  end
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
  amount = params[:amount].strip
  category = params[:category].strip

  error = error_for_new_expense(description, amount, category)
  if error
    session[:message] = error
    erb :new_expense
  else
    category_id = @storage.find_category(category) || @storage.create_new_category(category)
    @storage.add_new_expense(description, amount, category_id)
    session[:message] = 'Successfully added expense.'

    redirect '/budget'
  end
end
  
