require "test_helper"

class BurnRateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @category = @family.categories.create!(name: "Operations")
    @account = @family.accounts.create!(
      name: "Operating account",
      currency: @family.currency,
      balance: 0,
      accountable: Depository.new
    )
  end

  test "averages recurring expenses from the last three complete months" do
    as_of = Date.new(2026, 8, 15)

    create_expense(date: Date.new(2026, 2, 15), amount: 100)
    create_expense(date: Date.new(2026, 3, 15), amount: 200)
    create_expense(date: Date.new(2026, 4, 15), amount: 300)
    create_expense(date: Date.new(2026, 5, 15), amount: 300)
    create_expense(date: Date.new(2026, 6, 15), amount: 600)
    create_expense(date: Date.new(2026, 7, 15), amount: 900)

    create_expense(date: Date.new(2026, 8, 1), amount: 9_000)
    create_expense(date: Date.new(2026, 5, 20), amount: 1_500, kind: "one_time")

    result = BurnRate.new(@family, as_of: as_of).call

    assert_equal Money.new(600, @family.currency), result.amount
    assert_equal Money.new(200, @family.currency), result.previous_amount
    assert_equal 200.0, result.change_percent
  end

  test "omits the comparison when the previous three months have no recurring expenses" do
    as_of = Date.new(2026, 8, 15)
    create_expense(date: Date.new(2026, 7, 15), amount: 300)

    result = BurnRate.new(@family, as_of: as_of).call

    assert_equal Money.new(100, @family.currency), result.amount
    assert_equal Money.new(0, @family.currency), result.previous_amount
    assert_nil result.change_percent
  end

  private
    def create_expense(date:, amount:, kind: "standard")
      create_transaction(
        account: @account,
        category: @category,
        date: date,
        amount: amount,
        kind: kind
      )
    end
end
