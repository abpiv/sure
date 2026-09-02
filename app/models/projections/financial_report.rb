module Projections
  class FinancialReport
    BASIS = "Cash-basis management report"

    Line = Data.define(:name, :amount)
    IncomeStatement = Data.define(
      :revenue_lines,
      :expense_lines,
      :total_revenue,
      :total_expenses,
      :net_income
    )
    BalanceSheet = Data.define(
      :asset_lines,
      :liability_lines,
      :total_assets,
      :total_liabilities,
      :equity
    )
    CashFlowStatement = Data.define(
      :beginning_cash,
      :operating_receipts,
      :operating_payments,
      :net_operating_cash_flow,
      :investing_inflows,
      :investing_outflows,
      :net_investing_cash_flow,
      :financing_inflows,
      :financing_outflows,
      :net_financing_cash_flow,
      :other_cash_movements,
      :net_change_in_cash,
      :ending_cash
    )
    Report = Data.define(:as_of, :period, :basis, :income_statement, :balance_sheet, :cash_flow)

    def initialize(family:, user:, projection:, as_of: Date.current)
      @family = family
      @user = user
      @projection = projection
      @as_of = as_of.to_date
    end

    def call
      Report.new(
        as_of: as_of,
        period: period.start_date..period.end_date,
        basis: BASIS,
        income_statement: income_statement,
        balance_sheet: balance_sheet,
        cash_flow: cash_flow
      )
    end

    private
      attr_reader :family, :user, :projection, :as_of

      def period
        @period ||= Period.custom(
          start_date: projection.actual_points.first.month.beginning_of_month,
          end_date: projection.actual_points.last.month.end_of_month
        )
      end

      def income_statement
        @income_statement ||= begin
          statement = family.income_statement(user: user)
          revenue = statement.income_totals(period: period)
          expenses = statement.expense_totals(period: period)
          total_revenue = money(revenue.total)
          total_expenses = money(expenses.total)

          IncomeStatement.new(
            revenue_lines: category_lines(revenue),
            expense_lines: category_lines(expenses),
            total_revenue: total_revenue,
            total_expenses: total_expenses,
            net_income: total_revenue - total_expenses
          )
        end
      end

      def category_lines(period_total)
        period_total.category_totals
          .reject { |category_total| category_total.category.subcategory? || category_total.total.zero? }
          .sort_by { |category_total| -category_total.total }
          .map { |category_total| Line.new(name: category_total.category.name, amount: money(category_total.total)) }
      end

      def balance_sheet
        @balance_sheet ||= begin
          statement = family.balance_sheet(user: user)
          total_assets = statement.assets.total_money
          total_liabilities = statement.liabilities.total_money

          BalanceSheet.new(
            asset_lines: statement.assets.account_groups.map { |group| Line.new(name: group.name, amount: group.total_money) },
            liability_lines: statement.liabilities.account_groups.map { |group| Line.new(name: group.name, amount: group.total_money) },
            total_assets: total_assets,
            total_liabilities: total_liabilities,
            equity: total_assets - total_liabilities
          )
        end
      end

      def cash_flow
        @cash_flow ||= begin
          operating = operating_totals
          operating_receipts = operating.income_money
          operating_payments = operating.expense_money
          net_operating = operating_receipts - operating_payments

          investment = InvestmentFlowStatement.new(family, user: user).period_totals(period: period)
          investing_inflows = investment.withdrawals
          investing_outflows = investment.contributions
          net_investing = investing_inflows - investing_outflows

          financing_inflows = money(0)
          financing_outflows = loan_payments
          net_financing = financing_inflows - financing_outflows

          beginning_cash = projection.actual_points.first.cash_balance
          ending_cash = projection.actual_points.last.cash_balance
          net_change = ending_cash - beginning_cash
          classified_change = net_operating + net_investing + net_financing

          CashFlowStatement.new(
            beginning_cash: beginning_cash,
            operating_receipts: operating_receipts,
            operating_payments: operating_payments,
            net_operating_cash_flow: net_operating,
            investing_inflows: investing_inflows,
            investing_outflows: investing_outflows,
            net_investing_cash_flow: net_investing,
            financing_inflows: financing_inflows,
            financing_outflows: financing_outflows,
            net_financing_cash_flow: net_financing,
            other_cash_movements: net_change - classified_change,
            net_change_in_cash: net_change,
            ending_cash: ending_cash
          )
        end
      end

      def operating_totals
        scope = family.transactions
          .visible
          .excluding_pending
          .in_period(period)
          .where(kind: "standard")

        family.income_statement(user: user).totals(
          transactions_scope: scope,
          date_range: period.date_range
        )
      end

      def loan_payments
        scope = family.transactions
          .visible
          .excluding_pending
          .joins(entry: :account)
          .where(kind: "loan_payment")
          .where(entries: { date: period.date_range })
          .where(accounts: { accountable_type: "Depository" })
          .merge(Account.included_in_reports)
          .merge(Account.included_in_finances_for(user))

        scope.includes(:entry).sum(money(0)) do |transaction|
          convert(transaction.entry.amount_money.abs, transaction.entry.date)
        end
      end

      def money(amount)
        Money.new(amount, family.currency)
      end

      def convert(value, date)
        value.exchange_to(family.currency, date: date)
      rescue Money::ConversionError
        money(0)
      end
  end
end
