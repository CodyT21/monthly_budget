CREATE TABLE bills (
  id serial PRIMARY KEY,
  description text NOT NULL,
  amount_due decimal(6, 2) NOT NULL,
  due_date date NOT NULL,
  paid_date date,
  past_due boolean NOT NULL
);

CREATE TABLE categories (
  id serial PRIMARY KEY,
  name text NOT NULL UNIQUE,
  budgeted_amount decimal(6, 2) NOT NULL
);

CREATE TABLE expenses (
  id serial PRIMARY KEY,
  amount decimal(6, 2) NOT NULL DEFAULT 0,
  expense_date date NOT NULL DEFAULT NOW(),
  category_id integer NOT NULL REFERENCES categories (id),
  bill_id integer REFERENCES bills (id)
);
