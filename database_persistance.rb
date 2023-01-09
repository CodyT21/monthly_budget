require 'pg'

class DatabasePersistance
  def initialize(logger)
    @db = PG.connect(dbname: 'budget')
    @logger = logger
  end

  def query(statement, *params)
    @logger.info("#{statement}: #{params}")
    @db.exec_params(statement, params)
  end

  def all_expenses
    sql = <<~SQL
      SELECT e.id, e.description, e.amount, e.expense_date, c.name AS "category_name"
        FROM expenses e
        INNER JOIN categories c ON e.category_id = c.id
        ORDER BY e.expense_date, e.id
    SQL
    result = query(sql)

    result.map do |tuple|
      { description: tuple['description'],
        amount: tuple['amount'],
        date: tuple['expense_date'],
        category: tuple['category_name'] }
    end
  end

  def last_n_expenses(limit)
    sql = <<~SQL
      SELECT e.id, e.description, e.amount, e.expense_date, c.name AS "category_name"
        FROM expenses e
        INNER JOIN categories c ON e.category_id = c.id
        ORDER BY e.expense_date DESC, e.id DESC
        LIMIT $1
    SQL
    result = query(sql, limit)

    result.map do |tuple|
      { description: tuple['description'],
        amount: tuple['amount'],
        date: tuple['expense_date'],
        category: tuple['category_name'] }
    end
  end

  def budget_amounts_remaining
    sql = <<~SQL
      SELECT categories.id, categories.name, budgets.max_amount
        FROM categories
        INNER JOIN budgets ON categories.id = budgets.category_id
        ORDER BY categories.name
    SQL
    result = query(sql)

    result.map do |tuple|
      amount_remaining_in_category = tuple['max_amount'].to_f - category_expenses_total(tuple['id'])
      { category: tuple['name'],
        max_amount: tuple['max_amount'],
        amount_remaining: "%.2f" % (amount_remaining_in_category) }
    end
  end

  def category_expenses_total(category_id)
    sql = <<~SQL
      SELECT ROUND(SUM(amount), 2) AS "category_total"
        FROM expenses
        WHERE category_id = $1
    SQL
    result = query(sql, category_id)
    result.first['category_total'].to_f
  end

  def find_expense(id)
  end

  def add_new_expense(description, amount, category_id, date=Date.today)
    sql = <<~SQL
      INSERT INTO expenses (description, amount, category_id, expense_date)
        VALUES ($1, $2, $3, $4)
    SQL
    query(sql, description, amount, category_id, date)
  end

  def delete_expense(id)
  end

  def add_bill(description, amount, due_date)
  end

  def delete_bill(id)
  end

  def create_new_category(name)
    sql = "INSERT INTO categories (name) VALUES ($1)"
    query(sql, name.capitalize)

    category_id = find_category(name)
    create_new_budget(category_id)

    category_id
  end

  def delete_category(id)
  end

  def find_category(name)
    sql = "SELECT id FROM categories WHERE name ILIKE $1"
    result = query(sql, name)
    result.ntuples == 0 ? nil : result.first['id']
  end

  def create_new_budget(category_id, max_amount=0)
    sql = "INSERT INTO budgets (category_id, max_amount) VALUES ($1, $2)"
    query(sql, category_id, max_amount)
  end

  def calculate_monthly_total
  end

  def calculate_yearly_total
  end
end