module Projections
  class Calculator
    HISTORY_MONTH_OPTIONS = [ 1, 3, 6 ].freeze
    DEFAULT_HISTORY_MONTHS = 1
    FORECAST_MONTHS = 6
    FORECAST_DAYS_PER_MONTH = 30

    Point = Data.define(:month, :cash_balance, :revenue, :operating_expenses, :net_income)
    Result = Data.define(
      :history_months,
      :forecast_months,
      :currency,
      :liquid_assets,
      :burn_rate,
      :recurring_revenue,
      :net_burn,
      :runway_months,
      :out_of_money_date,
      :actual_points,
      :projected_points,
      :recurring_enabled,
      :recurring_items_present,
      :warnings
    )
    Estimate = Data.define(:recurring_transaction, :monthly_amount)

    def initialize(family:, user:, as_of: Date.current, history_months: DEFAULT_HISTORY_MONTHS)
      @family = family
      @user = user
      @as_of = as_of.to_date
      @history_months = normalize_history_months(history_months)
      @warnings = []
    end

    def call
      revenue_estimates = recurring_revenue_estimates
      liquid_assets = current_liquid_assets
      actuals = actual_points
      burn_rate = average_operating_expenses(actuals)
      recurring_revenue = money(revenue_estimates.sum { |estimate| [ -estimate.monthly_amount, 0 ].max })
      net_burn = burn_rate - recurring_revenue

      Result.new(
        history_months: history_months,
        forecast_months: FORECAST_MONTHS,
        currency: family.currency,
        liquid_assets: liquid_assets,
        burn_rate: burn_rate,
        recurring_revenue: recurring_revenue,
        net_burn: net_burn,
        runway_months: runway_months(liquid_assets, net_burn),
        out_of_money_date: out_of_money_date(liquid_assets, net_burn),
        actual_points: actuals,
        projected_points: projected_points(liquid_assets, burn_rate, recurring_revenue),
        recurring_enabled: !family.recurring_transactions_disabled?,
        recurring_items_present: revenue_estimates.any?,
        warnings: warnings.uniq.freeze
      )
    end

    private
      attr_reader :family, :user, :as_of, :history_months, :warnings

      def normalize_history_months(value)
        parsed = value.to_i
        parsed.positive? ? parsed : DEFAULT_HISTORY_MONTHS
      end

      def money(amount)
        Money.new(amount, family.currency)
      end

      def history_start
        @history_start ||= history_end.beginning_of_month - (history_months - 1).months
      end

      def history_end
        @history_end ||= as_of.beginning_of_month - 1.day
      end

      def report_period
        @report_period ||= Period.custom(start_date: history_start, end_date: history_end)
      end

      def liquid_accounts
        @liquid_accounts ||= begin
          scope = family.accounts
            .visible
            .included_in_reports
            .where(accountable_type: "Depository")
            .included_in_finances_for(user)

          tax_advantaged_ids = family.tax_advantaged_account_ids
          scope = scope.where.not(id: tax_advantaged_ids) if tax_advantaged_ids.present?
          scope.to_a
        end
      end

      def current_liquid_assets
        liquid_accounts.sum(money(0)) do |account|
          convert_money(account.balance_money, date: as_of, source: account.name)
        end
      end

      def historical_cash_balances
        return {} if liquid_accounts.empty?

        period = Period.custom(
          start_date: history_start.end_of_month,
          end_date: history_end.end_of_month
        )
        series = Balance::ChartSeriesBuilder.new(
          account_ids: liquid_accounts.map(&:id),
          currency: family.currency,
          period: period,
          interval: "1 month"
        ).balance_series

        series.values.to_h { |value| [ value.date.end_of_month, value.value ] }
      rescue StandardError => error
        warnings << "Historical cash balances are unavailable: #{error.class}"
        {}
      end

      def actual_points
        cash_by_month = historical_cash_balances
        income_statement = family.income_statement(user: user)

        month_ends.map do |month_end|
          period = Period.custom(start_date: month_end.beginning_of_month, end_date: month_end)
          revenue = money(income_statement.income_totals(period: period).total)
          expenses = money(income_statement.expense_totals(period: period).total)

          Point.new(
            month: month_end,
            cash_balance: cash_by_month.fetch(month_end, money(0)),
            revenue: revenue,
            operating_expenses: expenses,
            net_income: revenue - expenses
          )
        end
      end

      def average_operating_expenses(points)
        return money(0) if points.empty?

        money(points.sum { |point| point.operating_expenses.amount } / points.size)
      end

      def month_ends
        @month_ends ||= history_months.times.map do |offset|
          (history_start + offset.months).end_of_month
        end
      end

      def recurring_revenue_estimates
        return [] if family.recurring_transactions_disabled?

        eligible_account_ids = family.income_statement(user: user).eligible_accounts.pluck(:id).to_set

        family.recurring_transactions
          .active
          .accessible_by(user)
          .includes(:account, :destination_account, :merchant)
          .filter_map do |recurring|
            next if recurring.transfer?
            next if recurring.account_id.present? && !eligible_account_ids.include?(recurring.account_id)
            next unless recurring.amount.negative?

            Estimate.new(
              recurring_transaction: recurring,
              monthly_amount: estimated_monthly_amount(recurring)
            )
          end
      end

      def estimated_monthly_amount(recurring)
        matching_amounts = recurring.matching_transactions
          .select { |entry| entry.date.between?(history_start, history_end) }
          .reject { |entry| entry.entryable&.one_time? || entry.entryable&.transfer? }
          .map(&:amount)

        amount = if matching_amounts.any?
          matching_amounts.sum / matching_amounts.size
        elsif recurring.expected_amount_avg.present?
          recurring.expected_amount_avg
        else
          recurring.amount
        end

        convert_money(
          Money.new(amount, recurring.currency),
          date: history_end,
          source: recurring.name || recurring.merchant&.name
        ).amount
      end

      def projected_points(liquid_assets, burn_rate, recurring_revenue)
        cash = liquid_assets

        forecast_month_ends.map do |month_end|
          net_income = recurring_revenue - burn_rate
          cash += net_income

          Point.new(
            month: month_end,
            cash_balance: cash,
            revenue: recurring_revenue,
            operating_expenses: burn_rate,
            net_income: net_income
          )
        end
      end

      def forecast_month_ends
        @forecast_month_ends ||= FORECAST_MONTHS.times.map do |offset|
          (as_of.next_month.beginning_of_month + offset.months).end_of_month
        end
      end

      def runway_months(liquid_assets, net_burn)
        return nil unless net_burn.positive?

        (liquid_assets / net_burn).round(1)
      end

      def out_of_money_date(liquid_assets, net_burn)
        return as_of unless liquid_assets.positive?
        return nil unless net_burn.positive?

        days_until_depletion = (liquid_assets / net_burn * FORECAST_DAYS_PER_MONTH).ceil
        as_of + days_until_depletion
      end

      def convert_money(value, date:, source:)
        value.exchange_to(family.currency, date: date)
      rescue Money::ConversionError
        warnings << "Excluded #{source || "an item"} because no #{value.currency.iso_code}/#{family.currency} exchange rate was available."
        money(0)
      end
  end
end
