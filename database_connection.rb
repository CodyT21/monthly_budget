require 'pg'

module DatabaseConnection
  def initialize(logger=nil)
    @db = if ENV['RACK_ENV'] == 'test'
            PG.connect(dbname: 'budgets_test')
          else
            PG.connect(dbname: 'budgets')
          end

    @logger = logger
  end
  
  def query(statement, *params)
    @logger.info("#{statement}: #{params}") if @logger
    @db.exec_params(statement, params)
  end

  def clear
    @db.exec("DELETE FROM transactions;")
    @db.exec("ALTER SEQUENCE transactions_id_seq RESTART WITH 1;")
    @db.exec("DELETE FROM bills;")
    @db.exec("ALTER SEQUENCE bills_id_seq RESTART WITH 1;")
    @db.exec("DELETE FROM categories;")
    @db.exec("ALTER SEQUENCE categories_id_seq RESTART WITH 1;")
  end


  def disconnect
    @db.close
  end
end