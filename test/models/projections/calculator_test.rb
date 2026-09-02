require "test_helper"

class Projections::CalculatorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @cash_account = @family.accounts.create!(
      owner: @user,
      name: "Operating cash",
      currency: @family.currency,
      balance: 12_000,
      accountable: Depository.new(subtype: "checking"),
      status: "active"
    )
    @revenue_category = @family.categories.create!(name: "Revenue")
    @expense_category = @family.categories.create!(name: "Operations")
  end

  test "builds three historical months and six monthly projections" do
    as_of = Date.new(2026, 8, 15)

    create_transaction(
      account: @cash_account,
      category: @revenue_category,
      date: Date.new(2026, 7, 5),
      amount: -4_000,
      name: "Customer revenue"
    )
    create_transaction(
      account: @cash_account,
      category: @expense_category,
      date: Date.new(2026, 7, 10),
      amount: 2_000,
      name: "Operations"
    )
    create_transaction(
      account: @cash_account,
      category: @expense_category,
      date: as_of,
      amount: 9_000,
      name: "Current partial month"
    )

    create_recurring(name: "Subscription revenue", amount: -3_000, day: 5, next_date: Date.new(2026, 9, 5))
    create_recurring(name: "Operating expenses", amount: 4_000, day: 10, next_date: Date.new(2026, 9, 10))

    result = Projections::Calculator.new(
      family: @family,
      user: @user,
      as_of: as_of,
      history_months: 3
    ).call

    assert_equal 3, result.actual_points.size
    assert_equal 6, result.projected_points.size
    assert_equal Date.new(2026, 5, 31), result.actual_points.first.month
    assert_equal Date.new(2026, 7, 31), result.actual_points.last.month
    assert_equal Date.new(2026, 9, 30), result.projected_points.first.month
    assert_equal Date.new(2027, 2, 28), result.projected_points.last.month

    july = result.actual_points.last
    assert_equal Money.new(4_000, @family.currency), july.revenue
    assert_equal Money.new(2_000, @family.currency), july.operating_expenses
    assert_equal Money.new(2_000, @family.currency), july.net_income

    september = result.projected_points.first
    assert_equal Money.new(3_000, @family.currency), september.revenue
    assert_equal Money.new(4_000, @family.currency), september.operating_expenses
    assert_equal Money.new(-1_000, @family.currency), september.net_income
  end

  test "calculates liquid assets burn runway and the scheduled cash out date" do
    as_of = Date.new(2026, 8, 15)
    @cash_account.update!(balance: 2_500)
    create_recurring(name: "Operating expenses", amount: 1_000, day: 10, next_date: Date.new(2026, 9, 10))

    result = Projections::Calculator.new(family: @family, user: @user, as_of: as_of).call

    assert_equal Money.new(2_500, @family.currency), result.liquid_assets
    assert_equal Money.new(1_000, @family.currency), result.burn_rate
    assert_equal Money.new(0, @family.currency), result.recurring_revenue
    assert_equal Money.new(1_000, @family.currency), result.net_burn
    assert_equal 2.5, result.runway_months
    assert_equal Date.new(2026, 11, 10), result.cash_out_date
  end

  test "uses the selected completed-month lookback to estimate recurring amounts" do
    as_of = Date.new(2026, 8, 15)
    recurring = create_recurring(
      name: "Variable hosting",
      amount: 600,
      day: 10,
      next_date: Date.new(2026, 9, 10),
      expected_min: 100,
      expected_max: 900
    )

    [ 100, 100, 100, 300, 600, 900 ].each_with_index do |amount, index|
      month = Date.new(2026, 2 + index, 10)
      create_transaction(
        account: @cash_account,
        category: @expense_category,
        date: month,
        amount: amount,
        name: recurring.name
      )
    end

    three_month = Projections::Calculator.new(
      family: @family,
      user: @user,
      as_of: as_of,
      history_months: 3
    ).call
    six_month = Projections::Calculator.new(
      family: @family,
      user: @user,
      as_of: as_of,
      history_months: 6
    ).call

    assert_equal Money.new(600, @family.currency), three_month.burn_rate
    assert_equal Money.new(350, @family.currency), six_month.burn_rate
  end

  test "excludes inactive recurring items and recurring transfers" do
    as_of = Date.new(2026, 8, 15)
    destination = @family.accounts.create!(
      owner: @user,
      name: "Savings",
      currency: @family.currency,
      balance: 0,
      accountable: Depository.new(subtype: "savings"),
      status: "active"
    )

    create_recurring(name: "Active expense", amount: 500, day: 10, next_date: Date.new(2026, 9, 10))
    create_recurring(name: "Inactive expense", amount: 800, day: 11, next_date: Date.new(2026, 9, 11), status: "inactive")
    create_recurring(
      name: "Savings transfer",
      amount: 2_000,
      day: 12,
      next_date: Date.new(2026, 9, 12),
      destination_account: destination
    )

    result = Projections::Calculator.new(family: @family, user: @user, as_of: as_of).call

    assert_equal Money.new(500, @family.currency), result.burn_rate
  end

  test "does not project a runway or cash out date when recurring cash flow is nonnegative" do
    as_of = Date.new(2026, 8, 15)
    create_recurring(name: "Revenue", amount: -2_000, day: 5, next_date: Date.new(2026, 9, 5))
    create_recurring(name: "Expenses", amount: 1_000, day: 10, next_date: Date.new(2026, 9, 10))

    result = Projections::Calculator.new(family: @family, user: @user, as_of: as_of).call

    assert_equal Money.new(-1_000, @family.currency), result.net_burn
    assert_nil result.runway_months
    assert_nil result.cash_out_date
  end

  private
    def create_recurring(name:, amount:, day:, next_date:, status: "active", expected_min: nil, expected_max: nil, destination_account: nil)
      @family.recurring_transactions.create!(
        account: @cash_account,
        destination_account: destination_account,
        name: name,
        amount: amount,
        currency: @family.currency,
        expected_day_of_month: day,
        last_occurrence_date: next_date.prev_month,
        next_expected_date: next_date,
        status: status,
        occurrence_count: 1,
        manual: true,
        expected_amount_min: expected_min,
        expected_amount_max: expected_max,
        expected_amount_avg: amount
      )
    end
end
