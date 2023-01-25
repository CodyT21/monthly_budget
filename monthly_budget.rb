require 'simplecov'
SimpleCov.start

require 'sinatra'
require 'tilt/erubis'
require 'date'
require 'sinatra/content_for'

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

helpers do
  MONTHS = { 1 => 'January',
             2 => 'February',
             3 => 'March',
             4 => 'April',
             5 => 'May',
             6 => 'June',
             7 => 'July',
             8 => 'August',
             9 => 'September',
             10 => 'October',
             11 => 'November',
             12 => 'December' }

  def current_month
    month_number = Date.today.month
    MONTHS[month_number]
  end

  def month_to_string(month_num)
    MONTHS[month_num]
  end
end

def error_for_transaction(description, amount, category)
  if !(1..255).cover? description.size
    return 'Transaction description must be between 1 and 255 characters.'
  elsif !valid_amount?(amount)
    return 'Enter a valid amount between 0.00 and 9999.99.'
  elsif !valid_category_name(category)
    return 'Category name must be between 1 and 100 characters.'
  end
end

def error_for_category(name, max_amount, new_category=true)
  if !valid_category_name(name)
    return 'Category name must be between 1 and 100 characters.'
  elsif @storage.find_category_id(name) && new_category
    return 'Category name already exists.'
  elsif !valid_amount?(max_amount)
    return 'Enter a valid amount between 0.00 and 9999.99.'
  end
end

def valid_amount?(amount)
  amount =~ /^\d{1,4}(?:\.\d{1,2})?$/
end

def valid_category_name(name)
  (1..100).cover? name.size
end

before do
  @storage = DatabasePersistance.new(logger)
end

# render home page
get '/' do
  redirect '/budget'
end

get '/budget' do
  @budgets = @storage.category_amounts_remaining
  @transactions = @storage.last_n_transactions(5)
  @total_spent = @storage.find_transactions_total
  @total_budget_amount = @storage.find_categories_total
  @remaining_amount = '%.2f' % (@total_budget_amount.to_f - @total_spent.to_f)
  @monthly_total = @storage.monthly_total
  @year_to_date_total = @storage.year_to_date_total
  
  erb :budget
end

# display all transactions
get '/budget/transactions' do
  if params[:month]
    month = params[:month].strip
    @transactions = @storage.all_transactions_by_month(month)
  else
    @transactions = @storage.all_transactions
  end

  erb :transactions
end

# display new transaction form
get '/budget/transactions/new' do
  @categories = @storage.all_categories
  erb :new_transaction
end

# add new transaction
post '/budget/transactions' do
  @categories = @storage.all_categories
  description = params[:description].strip
  amount = params[:amount].strip
  category = params[:category].strip
  date = if params[:date] == ''
           Date.today
         else
           params[:date]
         end

  error = error_for_transaction(description, amount, category)
  if error
    session[:message] = error
    erb :new_transaction
  else
    category_id = @storage.find_category_id(category) || @storage.create_new_category(category)
    @storage.add_new_transaction(description, amount, category_id, date)
    session[:message] = 'Successfully added transaction.'

    redirect '/budget'
  end
end

# delete an transaction
post '/budget/transactions/:transaction_id/destroy' do
  id = params[:transaction_id].to_i
  @storage.delete_transaction(id)
  session[:message] = 'The transaction has been deleted successfully.'

  redirect '/budget'
end

# render edit transaction page
get '/budget/transactions/:transaction_id/edit' do
  id = params[:transaction_id].to_i
  @transaction = @storage.find_transaction(id)
  @categories = @storage.all_categories

  erb :edit_transaction
end

# edit an transaction
post '/budget/transactions/:transaction_id' do
  id = params[:transaction_id].to_i
  description = params[:description].strip
  amount = params[:amount].strip
  category_name = params[:category].strip
  date = params[:date].strip

  error = error_for_transaction(description, amount, category_name)
  if error
    @transaction = @storage.find_transaction(id)
    session[:message] = error
    erb :edit_transaction
  else
    @storage.create_new_category(category_name) unless @storage.find_category_id(category_name)
    category_id = @storage.find_category_id(category_name)
    @storage.edit_transaction(id, description, amount, category_id, date)
    session[:message] = 'Successfully updated transaction.'

    redirect '/budget'
  end
end

# delete a category
post '/budget/categories/:category_id/destroy' do
  category_id = params[:category_id].to_i
  @storage.delete_category(category_id)
  session[:message] = 'The category was successfully deleted.'

  redirect '/budget'
end

# render edit category page
get '/budget/categories/:category_id/edit' do
  category_id = params[:category_id].to_i
  @category = @storage.find_category(category_id)

  erb :edit_category
end

# edit a category
post '/budget/categories/:category_id' do
  category_id = params[:category_id].to_i
  category_name = params[:name].strip
  max_amount = params[:max_amount].strip

  error = error_for_category(category_name, max_amount, new_category=false)
  if error
    @category = @storage.find_category(category_id)
    session[:message] = error
    erb :edit_category
  else
    @storage.edit_category(category_id, category_name, max_amount)
    session[:message] = 'Successfully updated category.'
    
    redirect '/budget'
  end
end
    
# render new category page
get '/budget/categories/new' do
  erb :new_category
end

# create new category
post '/budget/categories' do
  category_name = params[:name].strip
  max_amount = params[:max_amount].strip

  error = error_for_category(category_name, max_amount)
  if error
    session[:message] = error
    erb :new_category
  else
    @storage.create_new_category(category_name, max_amount)
    session[:message] = 'Successfully added category.'

    redirect '/budget'
  end
end
