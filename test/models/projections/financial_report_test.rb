require "test_helper"

class Projections::FinancialReportTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @cash_account = @family.accounts.create!(
      owner: @user,
      name: "Operating cash",
      currency: @family.currency,
      balance: 8_000,
      accountable: Depository.new(subtype: "checking"),
      status: "active"
    )
    @loan = @family.accounts.create!(
      owner: @user,
      name: "Term loan",
      currency: @family.currency,
      balance: 2_000,
      accountable: Loan.new,
      status: "active"
    )
    @revenue_category = @family.categories.create!(name: "Services revenue")
    @expense_category = @family.categories.create!(name: "Software")
  end

  test "builds an income statement balance sheet and direct cash flow statement" do
    as_of = Date.new(2026, 8, 15)
    create_transaction(
      account: @cash_account,
      category: @revenue_category,
      date: Date.new(2026, 7, 5),
      amount: -5_000,
      name: "Customer payment"
    )
    create_transaction(
      account: @cash_account,
      category: @expense_category,
      date: Date.new(2026, 7, 10),
      amount: 2_000,
      name: "Software"
    )

    projection = Projections::Calculator.new(
      family: @family,
      user: @user,
      as_of: as_of,
      history_months: 3
    ).call
    report = Projections::FinancialReport.new(
      family: @family,
      user: @user,
      projection: projection,
      as_of: as_of
    ).call

    assert_equal Date.new(2026, 5, 1)..Date.new(2026, 7, 31), report.period
    assert_equal "Cash-basis management report", report.basis

    assert_equal Money.new(5_000, @family.currency), report.income_statement.total_revenue
    assert_equal Money.new(2_000, @family.currency), report.income_statement.total_expenses
    assert_equal Money.new(3_000, @family.currency), report.income_statement.net_income
    assert_equal "Services revenue", report.income_statement.revenue_lines.first.name

    assert_equal Money.new(8_000, @family.currency), report.balance_sheet.total_assets
    assert_equal Money.new(2_000, @family.currency), report.balance_sheet.total_liabilities
    assert_equal Money.new(6_000, @family.currency), report.balance_sheet.equity

    assert_equal Money.new(5_000, @family.currency), report.cash_flow.operating_receipts
    assert_equal Money.new(2_000, @family.currency), report.cash_flow.operating_payments
    assert_equal Money.new(3_000, @family.currency), report.cash_flow.net_operating_cash_flow
  end
end
