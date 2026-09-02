require "test_helper"

class ProjectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "show renders the monthly projections dashboard" do
    get projections_path(history_months: 3)

    assert_response :ok
    assert_select "h1", text: I18n.t("projections.show.title")
    assert_select "[data-projections-history-months='3']"
    assert_select "h2", text: I18n.t("projections.show.charts.cash_balance")
    assert_select "h2", text: I18n.t("projections.show.charts.net_income")
    assert_select "h2", text: I18n.t("projections.show.charts.revenue")
    assert_select "h2", text: I18n.t("projections.show.charts.operating_expenses")
    assert_select "form[action=?][method='get']", pdf_projections_path(history_months: 3, format: :pdf)
    assert_select "button", text: I18n.t("projections.show.export_pdf")
  end

  test "show defaults to the last completed month" do
    get projections_path

    assert_response :ok
    assert_select "[data-projections-history-months='1']"
  end

  test "show labels one three and six-month lookback controls and renders cash as bars" do
    get projections_path(history_months: 1)

    assert_response :ok
    assert_select "[data-projections-history-months='1']"
    assert_select "span", text: "Lookback period"
    assert_select "a[href=?]", projections_path(history_months: 1), text: "1 month"
    assert_select "a[href=?]", projections_path(history_months: 3), text: "3 months"
    assert_select "a[href=?]", projections_path(history_months: 6), text: "6 months"
    assert_select "[data-projection-chart-metric-value='cash_balance'][data-projection-chart-type-value='bar']"
  end

  test "show accepts a custom completed-month lookback" do
    get projections_path(history_months: 4)

    assert_response :ok
    assert_select "[data-projections-history-months='4']"
    assert_select "input[name='history_months'][type='number'][value='4']"
  end

  test "pdf exports a visual dashboard and all three financial statements" do
    get pdf_projections_path(history_months: 6, format: :pdf)

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_match(/attachment; filename="financial-projections-\d{4}-\d{2}-\d{2}\.pdf"/, response.headers["Content-Disposition"])
    assert response.body.start_with?("%PDF")

    reader = PDF::Reader.new(StringIO.new(response.body))
    text = reader.pages.map(&:text).join("\n")

    assert_operator reader.page_count, :>=, 4
    assert_includes text, "Financial Projections"
    assert_includes text, "Income Statement"
    assert_includes text, "Balance Sheet"
    assert_includes text, "Cash Flow Statement"
    assert_includes text, "Cash-basis management report"
  end

  test "pdf applies and identifies the selected one-month lookback period" do
    travel_to Date.new(2026, 8, 15) do
      get pdf_projections_path(history_months: 1, format: :pdf)

      assert_response :ok
      reader = PDF::Reader.new(StringIO.new(response.body))
      text = reader.pages.map(&:text).join("\n")

      assert_includes reader.pages.first.text, "Lookback period: 1 month"
      assert_includes text, "July 1, 2026 to July 31, 2026"
    end
  end

  test "pdf applies a custom month count to both period-based statements" do
    travel_to Date.new(2026, 8, 15) do
      get pdf_projections_path(history_months: 4, format: :pdf)

      assert_response :ok
      reader = PDF::Reader.new(StringIO.new(response.body))
      text = reader.pages.map(&:text).join("\n")

      assert_includes reader.pages.first.text, "Lookback period: 4 months"
      assert_equal 2, text.scan("April 1, 2026 to July 31, 2026").size
    end
  end
end
