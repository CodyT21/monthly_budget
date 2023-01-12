ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require'rack/test'
require 'pg'

require_relative '../monthly_budget'

class MonthlyBudget < Minitest::Test
  include Rack::Test::Methods

  def setup_test_database!
    @db.exec('TRUNCATE budgets;')
    @db.exec('TRUNCATE expenses CASCADE;')
    @db.exec('TRUNCATE categories CASCADE;')
    @db.exec('TRUNCATE bills CASCADE;')
  end

  def add_test_expenses
    category_ids = %w(Food Utilities Personal Housing).map do |category|
      find_category_id(category)
    end

    sql = <<~SQL
      INSERT INTO expenses(description, amount, category_id, expense_date)
        VALUES ('Lunch', 12.02, $1, '2023-01-11'),
        ('Paint', 15.12, $3, '2023-01-11'),
        ('Xcel', 36.25, $2, '2023-01-11'),
        ('Video Game', 60.56, $3, '2023-01-11'),
        ('Rent', 1723.24, $4, '2023-01-11'),
        ('Dinner', 13.56, $1, '2023-01-10');
    SQL
    @db.exec_params(sql, category_ids)
  end

  def add_test_categories
    sql = <<~SQL
      INSERT INTO categories (name)
        VALUES ('Food'),
        ('Utilities'),
        ('Personal'),
        ('Housing');
      SQL
    @db.exec(sql)
  end

  def find_category_id(name)
    sql = "SELECT id FROM categories WHERE name ILIKE $1"
    result = @db.exec_params(sql, [name])
    result.ntuples == 0 ? nil : result.first['id']
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
    assert_includes last_response.body, '<h2>Monthly Budget</h2>'
    assert_includes last_response.body, '<h4>Budget Progress:</h4>'
    assert_includes last_response.body, '<h4>Recent Expenses:</h4>'
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

    get '/budget'
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
    add_test_categories
    add_test_expenses

    get '/budget'
    refute_includes last_response.body, 'Dinner | 13.56 | 2023-01-10 | Food'
    
    get '/budget/expenses'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Dinner | 13.56 | 2023-01-10 | Food'
  end
end
