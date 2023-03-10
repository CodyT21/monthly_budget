ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'pg'

require_relative '../monthly_budget'

class MonthlyBudget < Minitest::Test
  include Rack::Test::Methods

  def setup_test_database!
    @db.exec('TRUNCATE expenses CASCADE;')
    @db.exec('TRUNCATE categories CASCADE;')
    @db.exec('TRUNCATE bills CASCADE;')
    insert_test_data
  end

  def insert_test_data
    add_test_categories
    add_test_expenses
  end

  def add_test_expenses
    sql = <<~SQL
      INSERT INTO expenses(id, description, amount, category_id, expense_date)
        VALUES (1, 'Lunch', 12.02, 1, '2023-01-11'),
        (2, 'Paint', 15.00, 3, '2023-01-11'),
        (3, 'Xcel', 36.25, 2, '2023-01-11'),
        (4, 'Video Game', 60.56, 3, '2023-01-11'),
        (5, 'Rent', 1723.24, 4, '2023-01-11'),
        (6, 'Dinner', 13.56, 1, '2023-01-10');
    SQL
    @db.exec(sql)
  end

  def add_test_categories
    sql = <<~SQL
      INSERT INTO categories (id, name, max_amount)
        VALUES (1, 'Food', 100),
        (2, 'Utilities', 80),
        (3, 'Personal', 100),
        (4, 'Housing', 1750);
      SQL
    @db.exec(sql)
  end

  def add_new_expense(description, amount, category_id, date)
    sql = <<~SQL
      INSERT INTO expenses (description, amount, category_id, expense_date)
        VALUES ($1, $2, $3, $4)
    SQL
    @db.exec_params(sql, [description, amount, category_id, date])
  end

  def setup
    @db = PG.connect(dbname: 'budget_test')
    setup_test_database!
  end

  def session
    last_request.env['rack.session']
  end

  def app
    Sinatra::Application
  end

  def test_render_budget
    get '/'
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h1>Monthly Budget</h1>'
    assert_includes last_response.body, '<h4>Monthly Budget Progress:</h4>'
    assert_includes last_response.body, '<h4>Recent Monthly Expenses:</h4>'
    assert_includes last_response.body, '<button>View All Expenses</button>'
  end

  def test_render_add_expense
    get '/budget/expenses/new'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Add New Expense</h2>'
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_add_expense
    post '/budget/expenses', { description: 'Lunch', amount: '12.06', category: 'Food', date: '2023-01-11' }
    assert_equal 302, last_response.status
    assert_equal 'Successfully added expense.', session[:message]

    get last_response['Location']
    assert_includes last_response.body, 'Lunch | 12.06 | 2023-01-11 | Food'
  end

  def test_invalid_expense_description
    post '/budget/expenses', { description: '', amount: '0', category: 'Uncategorized', date: '2023-01-11' }
    assert_includes last_response.body, 'Expense description must be between 1 and 255 characters.'
  end

  def test_invalid_expense_amount
    post '/budget/expenses', { description: 'Lunch', amount: 'Ten', category: 'Uncategorized', date: '2023-01-11' }
    assert_includes last_response.body, 'Enter a valid amount between 0.00 and 9999.99.'
  end

  def test_invalid_expense_category
    post '/budget/expenses', { description: 'Lunch', amount: '0', category: '', date: '2023-01-11' }
    assert_includes last_response.body, 'Category name must be between 1 and 100 characters.'
  end

  def test_view_all_expenses
    get '/budget'
    refute_includes last_response.body, 'Dinner | 13.56 | 2023-01-10 | Food'
    
    get '/budget/expenses'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Dinner | 13.56 | 2023-01-10 | Food'
  end

  def test_render_edit_expense_page
    get '/budget/expenses/1/edit'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Editing Expense Lunch</h2>'
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_edit_expense
    post '/budget/expenses/1', { description: 'New Description', amount: '9.99', category: 'New Category', date: '2023-01-12' }
    assert_equal 302, last_response.status
    assert_equal 'Successfully updated expense.', session[:message]

    get last_response['Location']
    assert_includes last_response.body, 'New Description | 9.99 | 2023-01-12 | New Category'
  end

  def test_delete_expense
    post 'budget/expenses/1/destroy'
    assert_equal 302, last_response.status
    assert_equal 'The expense has been deleted successfully.', session[:message]

    get last_response['Location']
    refute_includes last_response.body, 'Lunch | 12.02 | 2023-01-10 | Food'
  end

  def test_delete_category
    post '/budget/categories/3/destroy'
    assert_equal 302, last_response.status
    assert_equal 'The category was successfully deleted.', session[:message]

    get last_response['Location']
    refute_includes last_response.body, 'Personal | 100.00 | 85.00'
    assert_includes last_response.body, 'Paint | 15.00 | 2023-01-11 | Uncategorized'
  end

  def test_render_edit_category_page
    get '/budget/categories/1/edit'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Editing Category: Food</h2>'
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_edit_category_name
    post '/budget/categories/1', { name: 'Meals', max_amount: 100 }
    assert_equal 302, last_response.status
    assert_equal 'Successfully updated category.', session[:message]

    get last_response['Location']
    refute_includes last_response.body, 'Food | 100.00 | 74.42'
    assert_includes last_response.body, 'Meals | 100.00 | 74.42'
    assert_includes last_response.body, 'Lunch | 12.02 | 2023-01-11 | Meals'
  end

  def test_view_all_expenses_by_month
    add_new_expense('Lunch', 10.00, 1, '2023-03-01')
    
    get '/budget/expenses'
    assert_includes last_response.body, 'Lunch | 12.02 | 2023-01-11 | Food'
    assert_includes last_response.body, 'Lunch | 10.00 | 2023-03-01 | Food'
    assert_includes last_response.body, '<button>January</button>'
    
    get '/budget/expenses?month=3'
    refute_includes last_response.body, 'Lunch | 12.02 | 2023-01-11 | Food'
    assert_includes last_response.body, 'Lunch | 10.00 | 2023-03-01 | Food'
  end

  def test_render_new_category_page
    get '/budget/categories/new'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Create New Budget Category</h2>'
    assert_includes last_response.body, %q(<option value="Food")
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_non_unique_new_category_name
    post '/budget/categories', { name: 'Food', max_amount: '100.00' }
    assert_includes last_response.body, 'Category name already exists.'
  end

  def test_invalid_new_category_name
    post '/budget/categories', { name: '', max_amount: '100.00' }
    assert_includes last_response.body, 'Category name must be between 1 and 100 characters.'
  end

  def test_invalid_new_category_amount
    post '/budget/categories', { name: 'New Category', max_amount: 'amount' }
    assert_includes last_response.body, 'Enter a valid amount between 0.00 and 9999.99.'
  end

  def test_new_category
    post '/budget/categories', { name: 'New Category', max_amount: '200.00' }
    assert_equal 302, last_response.status
    assert_equal 'Successfully added category.', session[:message]

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'New Category | 200.00 | 200.00'
  end
end
