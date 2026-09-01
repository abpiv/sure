class BurnRate
  TRAILING_MONTHS = 3

  Result = Data.define(:amount, :previous_amount, :change_percent, :period, :previous_period)

  def initialize(family, user: nil, as_of: Date.current, income_statement: nil)
    @family = family
    @as_of = as_of.to_date
    @income_statement = income_statement || family.income_statement(user: user)
  end

  def call
    current_period = trailing_period_ending(@as_of.beginning_of_month - 1.day)
    previous_period = trailing_period_ending(current_period.start_date - 1.day)

    amount = average_expenses(current_period)
    previous_amount = average_expenses(previous_period)

    Result.new(
      amount: amount,
      previous_amount: previous_amount,
      change_percent: percentage_change(previous_amount, amount),
      period: current_period,
      previous_period: previous_period
    )
  end

  private
    def trailing_period_ending(end_date)
      Period.custom(
        start_date: (end_date + 1.day - TRAILING_MONTHS.months).beginning_of_month,
        end_date: end_date
      )
    end

    def average_expenses(period)
      scope = @family.transactions
        .visible
        .excluding_pending
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)
        .in_period(period)

      total = @income_statement.totals(
        transactions_scope: scope,
        date_range: period.date_range
      ).expense_money

      total / TRAILING_MONTHS
    end

    def percentage_change(previous_amount, amount)
      return nil if previous_amount.zero?

      ((amount - previous_amount) / previous_amount * 100).round(1)
    end
end
