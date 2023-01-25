require 'date'

require_relative 'database_connection'

class DatabasePersistance
  include DatabaseConnection

  CURRENT_DATE = Date.today

  def all_transactions
    sql = <<~SQL
      SELECT t.id, t.description, t.amount, t.transaction_date, c.name AS "category_name"
        FROM transactions t
        INNER JOIN categories c ON t.category_id = c.id
        ORDER BY t.transaction_date, t.id
    SQL
    result = query(sql)

    result.map do |tuple|
      tuple_to_hash_for_transaction(tuple)
    end
  end

  def all_transactions_by_month(month)
    sql = <<~SQL
    SELECT t.id, t.description, t.amount, t.transaction_date, c.name AS "category_name"
      FROM transactions t
      INNER JOIN categories c ON t.category_id = c.id
      WHERE DATE_PART('month', t.transaction_date) = $1
      ORDER BY t.transaction_date, t.id
    SQL
    result = query(sql, month)

    result.map do |tuple|
      tuple_to_hash_for_transaction(tuple)
    end
  end

  def last_n_transactions(limit)
    sql = <<~SQL
      SELECT t.id, t.description, t.amount, t.transaction_date, c.name AS "category_name"
        FROM transactions t
        INNER JOIN categories c ON t.category_id = c.id
        WHERE DATE_PART('month', transaction_date) = $2
        ORDER BY t.transaction_date DESC, t.id DESC
        LIMIT $1
    SQL
    result = query(sql, limit, CURRENT_DATE.month)

    result.map do |tuple|
      tuple_to_hash_for_transaction(tuple)
    end
  end

  def find_transaction(id)
    sql = <<~SQL
      SELECT t.id, t.description, t.amount, t.transaction_date, c.name AS "category_name"
        FROM transactions t
        INNER JOIN categories c ON t.category_id = c.id
        WHERE t.id = $1
    SQL
    result = query(sql, id)

    tuple_to_hash_for_transaction(result.first)
  end

  def all_categories
    sql = "SELECT name FROM categories"
    result = query(sql)
    result.map { |tuple| capitalize_all_words(tuple['name']) }
  end
  
  def category_amounts_remaining
    sql = <<~SQL
      SELECT id, name, max_amount
        FROM categories
        ORDER BY name
    SQL
    result = query(sql)

    result.map do |tuple|
      amount_remaining_in_category = tuple['max_amount'].to_f - category_transactions_total(tuple['id'])
      { id: tuple['id'],
        category: tuple['name'],
        max_amount: tuple['max_amount'],
        amount_remaining: "%.2f" % (amount_remaining_in_category) }
    end
  end

  def find_category(category_id)
    sql = <<~SQL
      SELECT id, name, max_amount
        FROM categories
        WHERE id = $1
    SQL
    result = query(sql, category_id)

    tuple = result.first
    { id: tuple['id'],
      name: tuple['name'],
      max_amount: tuple['max_amount'] }
  end

  def category_transactions_total(category_id)
    sql = <<~SQL
      SELECT ROUND(SUM(amount), 2) AS "category_total"
        FROM transactions
        WHERE category_id = $1 AND DATE_PART('month', transaction_date) = $2
    SQL
    result = query(sql, category_id, CURRENT_DATE.month)
    result.first['category_total'].to_f
  end

  def add_new_transaction(description, amount, category_id, date)
    sql = <<~SQL
      INSERT INTO transactions (description, amount, category_id, transaction_date)
        VALUES ($1, $2, $3, $4)
    SQL
    query(sql, description, amount, category_id, date)
  end

  def delete_transaction(id)
    sql = "DELETE FROM transactions WHERE id = $1"
    query(sql, id)
  end

  def edit_transaction(id, description, amount, category_id, date)
    sql = <<~SQL
      UPDATE transactions
        SET description = $1, amount = $2, category_id = $3, transaction_date = $4
        WHERE id = $5
    SQL
    query(sql, description, amount, category_id, date, id)
  end

  def add_bill(description, amount, due_date)
  end

  def delete_bill(id)
  end

  def create_new_category(name, max_amount=0)
    name = capitalize_all_words(name)
    sql = "INSERT INTO categories (name, max_amount) VALUES ($1, $2)"
    query(sql, capitalize_all_words(name), max_amount)

    category_id = find_category_id(name)
    category_id
  end

  def delete_category(category_id)
    add_uncategorized_to_categories if uncategorized?
    uncategorized_id = find_category_id('Uncategorized')
    update_transaction_categories(category_id, uncategorized_id)
    
    sql = "DELETE FROM categories WHERE id = $1"
    query(sql, category_id)
  end

  def edit_category(id, name, max_amount)
    sql = <<~SQL
      UPDATE categories
        SET name = $1, max_amount = $2
        WHERE id = $3
    SQL
    query(sql, name, max_amount, id)
  end

  def find_category_id(name)
    sql = "SELECT id FROM categories WHERE name LIKE $1"
    result = query(sql, capitalize_all_words(name))
    result.ntuples == 0 ? nil : result.first['id']
  end

  def find_transactions_total
    sql = "SELECT SUM(amount) FROM transactions WHERE DATE_PART('month', transaction_date) = $1"
    result = query(sql, CURRENT_DATE.month)
    total = result.first['sum']
    total ? '%.2f' % total : '0.00'
  end

  def find_categories_total
    sql = <<~SQL
      SELECT SUM(max_amount) 
        FROM categories
    SQL
    result = query(sql)

    total = result.first['sum']
    total ? '%.2f' % total : '0.00'
  end

  def monthly_total
    sql = <<~SQL
      SELECT SUM(amount)
        FROM transactions
        WHERE DATE_PART('month', transaction_date) = $1
    SQL
    result = query(sql, CURRENT_DATE.month)
    
    total = result.first['sum']
    total ? '%.2f' % total : '0.00'
  end

  def year_to_date_total
    sql = <<~SQL
      SELECT SUM(amount)
        FROM transactions
        WHERE DATE_PART('year', transaction_date) = $1
    SQL
    result = query(sql, CURRENT_DATE.year)
    
    total = result.first['sum']
    total ? '%.2f' % total : '0.00'
  end

  private

  def tuple_to_hash_for_transaction(tuple)
    { id: tuple['id'],
      description: tuple['description'],
      amount: tuple['amount'],
      date: tuple['transaction_date'],
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

  def update_transaction_categories(current_category_id, new_category_id)
    sql = <<~SQL
      UPDATE transactions
        SET category_id = $1
        WHERE category_id = $2
    SQL
    query(sql, new_category_id, current_category_id)
  end

  def capitalize_all_words(text)
    text.split.map(&:capitalize).join(' ')
  end
end
