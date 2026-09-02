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

  test "show defaults invalid history to six months" do
    get projections_path(history_months: 12)

    assert_response :ok
    assert_select "[data-projections-history-months='6']"
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
end
