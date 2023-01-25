ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'pg'

require_relative '../monthly_budget'

class MonthlyBudget < Minitest::Test
  include Rack::Test::Methods

  def setup_test_database!
    @db.exec('TRUNCATE transactions CASCADE;')
    @db.exec('TRUNCATE categories CASCADE;')
    @db.exec('TRUNCATE bills CASCADE;')
    insert_test_data
  end

  def insert_test_data
    add_test_categories
    add_test_transactions
  end

  def add_test_transactions
    sql = <<~SQL
      INSERT INTO transactions(id, description, amount, category_id, transaction_date)
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
        (4, 'Housing', 1750),
        (5, 'Test', 0.00);
      SQL
    @db.exec(sql)
  end

  def add_new_transaction(description, amount, category_id, date)
    sql = <<~SQL
      INSERT INTO transactions (description, amount, category_id, transaction_date)
        VALUES ($1, $2, $3, $4)
    SQL
    @db.exec_params(sql, [description, amount, category_id, date])
  end

  def setup
    @db = PG.connect(dbname: 'budgets_test')
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
    assert_includes last_response.body, '<h3>Monthly Budget Progress</h3>'
    assert_includes last_response.body, '<h3>Recent Monthly Transactions</h3>'
    assert_includes last_response.body, '<h3>Net Totals</h3>'
    assert_includes last_response.body, '<button>View All Transactions</button>'
  end

  def test_render_add_transaction
    get '/budget/transactions/new'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Add New Transaction</h2>'
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_add_transaction
    post '/budget/transactions', { description: 'New Expense', amount: '99.99', category: 'Test', date: '2023-01-30' }
    assert_equal 302, last_response.status
    assert_equal 'Successfully added transaction.', session[:message]

    get last_response['Location']
    assert_includes last_response.body, '<td>New Expense</td>'
    assert_includes last_response.body, '<td>99.99</td>'
    assert_includes last_response.body, '<td>2023-01-30</td>'
    assert_includes last_response.body, '<td>Test</td>'
  end

  def test_invalid_transaction_description
    post '/budget/transactions', { description: '', amount: '0', category: 'Uncategorized', date: '2023-01-11' }
    assert_includes last_response.body, 'Transaction description must be between 1 and 255 characters.'
  end

  def test_invalid_transaction_amount
    post '/budget/transactions', { description: 'Lunch', amount: 'Ten', category: 'Uncategorized', date: '2023-01-11' }
    assert_includes last_response.body, 'Enter a valid amount between 0.00 and 9999.99.'
  end

  def test_invalid_transaction_category
    post '/budget/transactions', { description: 'Lunch', amount: '0', category: '', date: '2023-01-11' }
    assert_includes last_response.body, 'Category name must be between 1 and 100 characters.'
  end

  def test_view_all_transactions
    get '/budget'
    refute_includes last_response.body, '<td>New Description</td>'
    refute_includes last_response.body, '<td>New Category</td>'
    
    get '/budget/transactions'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<td>Dinner</td>'
    assert_includes last_response.body, '<td>13.56</td>'
    assert_includes last_response.body, '<td>2023-01-10</td>'
    assert_includes last_response.body, '<td>Food</td>'
  end

  def test_render_edit_transaction_page
    get '/budget/transactions/1/edit'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Editing Transaction Lunch</h2>'
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_edit_transaction
    post '/budget/transactions/1', { description: 'New Description', amount: '9.99', category: 'New Category', date: '2023-01-12' }
    assert_equal 302, last_response.status
    assert_equal 'Successfully updated transaction.', session[:message]

    get last_response['Location']
    assert_includes last_response.body, '<td>New Description</td>'
    assert_includes last_response.body, '<td>New Category</td>'
  end

  def test_delete_transaction
    post 'budget/transactions/1/destroy'
    assert_equal 302, last_response.status
    assert_equal 'The transaction has been deleted successfully.', session[:message]

    get last_response['Location']
    refute_includes last_response.body, '<td>Lunch</td>'
    refute_includes last_response.body, '<td>12.02</td>'
  end

  def test_delete_category
    post '/budget/categories/3/destroy'
    assert_equal 302, last_response.status
    assert_equal 'The category was successfully deleted.', session[:message]

    get last_response['Location']
    refute_includes last_response.body, '<td>Personal</td>'

    assert_includes last_response.body, '<td>Paint</td>'
    assert_includes last_response.body, '<td>15.00</td>'
    assert_includes last_response.body, '<td>2023-01-11</td>'
    assert_includes last_response.body, '<td>Uncategorized</td>'
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
    refute_includes last_response.body, '<td>Food</td>'

    assert_includes last_response.body, '<td>Meals</td>'
    assert_includes last_response.body, '<td>100.00</td>'
    assert_includes last_response.body, '<td>74.42</td>'
  end

  def test_view_all_transactions_by_month
    add_new_transaction('March Expense', 10.00, 1, '2023-03-01')
    
    get '/budget/transactions'
    assert_includes last_response.body, '<td>Lunch</td>'
    assert_includes last_response.body, '<td>12.02</td>'
    assert_includes last_response.body, '<td>2023-01-11</td>'
    assert_includes last_response.body, '<td>Food</td>'

    assert_includes last_response.body, '<td>March Expense</td>'
    assert_includes last_response.body, '<td>10.00</td>'
    assert_includes last_response.body, '<td>2023-03-01</td>'
    assert_includes last_response.body, '<td>Food</td>'

    assert_includes last_response.body, '<button>January</button>'
    
    get '/budget/transactions?month=3'
    refute_includes last_response.body, '<td>Lunch</td>'
    refute_includes last_response.body, '<td>12.02</td>'

    assert_includes last_response.body, '<td>March Expense</td>'
  end

  def test_render_new_category_page
    get '/budget/categories/new'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h2>Create New Budget Category</h2>'
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
    assert_includes last_response.body, '<td>New Category</td>'
    assert_includes last_response.body, '<td>200.00</td>'
    assert_includes last_response.body, '<td>200.00</td>'
  end
end
