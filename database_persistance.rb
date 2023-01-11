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
      tuple_to_hash_for_expense(tuple)
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
      tuple_to_hash_for_expense(tuple)
    end
  end

  def find_expense(id)
    sql = <<~SQL
      SELECT e.id, e.description, e.amount, e.expense_date, c.name AS "category_name"
        FROM expenses e
        INNER JOIN categories c ON e.category_id = c.id
        WHERE e.id = $1
    SQL
    result = query(sql, id)

    tuple_to_hash_for_expense(result.first)
  end

  def budget_amounts_remaining
    sql = <<~SQL
      SELECT categories.id, categories.name, budgets.max_amount
        FROM categories
        INNER JOIN budgets ON categories.id = budgets.category_id
        WHERE category_id IN (SELECT category_id FROM expenses)
        ORDER BY categories.name
    SQL
    result = query(sql)

    result.map do |tuple|
      amount_remaining_in_category = tuple['max_amount'].to_f - category_expenses_total(tuple['id'])
      { id: tuple['id'],
        category: tuple['name'],
        max_amount: tuple['max_amount'],
        amount_remaining: "%.2f" % (amount_remaining_in_category) }
    end
  end

  def find_budget(category_id)
    sql = <<~SQL
      SELECT categories.id, categories.name, budgets.max_amount
        FROM categories
        INNER JOIN budgets ON categories.id = budgets.category_id
        WHERE category_id = $1
    SQL
    result = query(sql, category_id)

    tuple = result.first
    { id: tuple['id'],
      category: tuple['name'],
      max_amount: tuple['max_amount'] }
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

  def add_new_expense(description, amount, category_id, date)
    sql = <<~SQL
      INSERT INTO expenses (description, amount, category_id, expense_date)
        VALUES ($1, $2, $3, $4)
    SQL
    query(sql, description, amount, category_id, date)
  end

  def delete_expense(id)
    sql = "DELETE FROM expenses WHERE id = $1"
    query(sql, id)
  end

  def edit_expense(id, description, amount, category_id, date)
    sql = <<~SQL
      UPDATE expenses
        SET description = $1, amount = $2, category_id = $3, expense_date = $4
        WHERE id = $5
    SQL
    query(sql, description, amount, category_id, date, id)
  end

  def add_bill(description, amount, due_date)
  end

  def delete_bill(id)
  end

  def create_new_category(name)
    sql = "INSERT INTO categories (name) VALUES ($1)"
    query(sql, name.capitalize)

    category_id = find_category_id(name)
    create_new_budget(category_id)

    category_id
  end

  def delete_category(category_id)
    add_uncategorized_to_categories if uncategorized?
    uncategorized_id = find_category_id('Uncategorized')
    update_expense_categories(category_id, uncategorized_id)
    
    sql = "DELETE FROM categories WHERE id = $1"
    query(sql, category_id)
  end

  def edit_category(id, name, max_amount)
    sql = <<~SQL
      UPDATE categories
        SET name = $1
        WHERE id = $2
    SQL
    query(sql, name, id)

    update_budget_amount(id, max_amount)
  end

  def update_budget_amount(category_id, max_amount)
    sql = <<~SQL
      UPDATE budgets
        SET max_amount = $1
        WHERE category_id = $2
    SQL
    query(sql, max_amount, category_id)
  end

  def find_category_id(name)
    sql = "SELECT id FROM categories WHERE name ILIKE $1"
    result = query(sql, name)
    result.ntuples == 0 ? nil : result.first['id']
  end

  def find_category(category_id)
    sql = "SELECT * FROM categories WHERE id = $1"
    result = query(sql, category_id)

    result.map do |tuple|
      { id: tuple['id'], name: tuple['name'] }
    end
  end

  def create_new_budget(category_id, max_amount=0)
    sql = "INSERT INTO budgets (category_id, max_amount) VALUES ($1, $2)"
    query(sql, category_id, max_amount)
  end

  def calculate_monthly_total
  end

  def calculate_yearly_total
  end

  private

  def tuple_to_hash_for_expense(tuple)
    { id: tuple['id'],
      description: tuple['description'],
      amount: tuple['amount'],
      date: tuple['expense_date'],
      category: tuple['category_name'] }
  end

  def uncategorized?
    sql = "SELECT id FROM categories WHERE name ILIKE 'Uncategorized'"
    result = query(sql)
    result.ntuples == 0
  end

  def add_uncategorized_to_categories
    sql = "INSERT INTO categories (name) VALUES ('Uncategorized')"
    query(sql)
  end

  def update_expense_categories(current_category_id, new_category_id)
    sql = <<~SQL
      UPDATE expenses
        SET category_id = $1
        WHERE category_id = $2
    SQL
    query(sql, new_category_id, current_category_id)
  end
end