class ProjectionsController < ApplicationController
  def show
    setup_projection
  end

  def pdf
    setup_projection
    financial_report = Projections::FinancialReport.new(
      family: Current.family,
      user: Current.user,
      projection: @projection,
      as_of: Date.current
    ).call
    pdf = Projections::PdfReport.new(
      family: Current.family,
      projection: @projection,
      financial_report: financial_report
    ).render

    send_data pdf,
      filename: "financial-projections-#{Date.current.iso8601}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  private
    def setup_projection
      @history_months = normalized_history_months
      @projection = Projections::Calculator.new(
        family: Current.family,
        user: Current.user,
        history_months: @history_months
      ).call
      @chart_points = chart_points
      @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("projections.show.title"), nil ] ]
    end

    def normalized_history_months
      requested = params[:history_months].to_i
      requested.positive? ? requested : Projections::Calculator::DEFAULT_HISTORY_MONTHS
    end

    def chart_points
      actual = @projection.actual_points.map { |point| serialize_point(point, projected: false) }
      projected = @projection.projected_points.map { |point| serialize_point(point, projected: true) }
      actual + projected
    end

    def serialize_point(point, projected:)
      {
        label: I18n.l(point.month, format: :month_year),
        short_label: I18n.l(point.month, format: :short_month_year),
        projected: projected,
        cash_balance: point.cash_balance.amount.to_f,
        net_income: point.net_income.amount.to_f,
        revenue: point.revenue.amount.to_f,
        operating_expenses: point.operating_expenses.amount.to_f
      }
    end
end
