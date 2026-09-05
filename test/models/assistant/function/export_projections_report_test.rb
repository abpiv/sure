require "test_helper"

class Assistant::Function::ExportProjectionsReportTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @fn = Assistant::Function::ExportProjectionsReport.new(@user)
  end

  test "exports the existing report for the last completed month" do
    travel_to Date.new(2026, 9, 1) do
      result = @fn.call
      pdf = Base64.strict_decode64(result[:content_base64])
      reader = PDF::Reader.new(StringIO.new(pdf))
      text = reader.pages.map(&:text).join("\n")

      assert_equal "application/pdf", result[:mime_type]
      assert_equal "financial-projections-2026-09-01.pdf", result[:filename]
      assert_equal pdf.bytesize, result[:byte_size]
      assert_equal Digest::SHA256.hexdigest(pdf), result[:sha256]
      assert_equal "2026-08-01", result[:period_start]
      assert_equal "2026-08-31", result[:period_end]
      assert_operator reader.page_count, :>=, 4
      assert_includes text, "Lookback period: 1 month"
      assert_includes text, "August 1, 2026 to August 31, 2026"
      [ "Financial Projections", "Income Statement", "Balance Sheet", "Cash Flow Statement" ].each do |heading|
        assert_includes text, heading
      end
    end
  end

  test "three-month lookback crosses a year boundary" do
    travel_to Date.new(2026, 2, 1) do
      result = @fn.call("history_months" => 3)
      text = PDF::Reader.new(StringIO.new(Base64.strict_decode64(result[:content_base64]))).pages.map(&:text).join("\n")

      assert_equal 3, result[:history_months]
      assert_equal "2025-11-01", result[:period_start]
      assert_equal "2026-01-31", result[:period_end]
      assert_includes text, "Lookback period: 3 months"
      assert_includes text, "November 1, 2025 to January 31, 2026"
    end
  end

  test "rejects malformed or excessive lookbacks before querying financial records" do
    Projections::Calculator.expects(:new).never
    [ 0, -1, 1.5, "3", nil, true, 121, [ 1 ], { months: 1 } ].each do |months|
      assert_raises(ArgumentError) { @fn.call("history_months" => months) }
    end
  end

  test "caller cannot choose another user or family" do
    Projections::Calculator.expects(:new).never
    assert_raises(ArgumentError) { @fn.call("family_id" => families(:empty).id) }
    assert_raises(ArgumentError) { @fn.call("user_id" => users(:empty).id) }
  end

  test "passes the authenticated user to both financial calculators" do
    Current.session = users(:empty).sessions.build
    projection = mock
    calculator = mock(call: projection)
    report = mock
    Projections::Calculator.expects(:new).with(
      family: @user.family, user: @user, as_of: Date.current, history_months: 1
    ).returns(calculator)
    Projections::FinancialReport.expects(:new).with(
      family: @user.family, user: @user, projection: projection, as_of: Date.current
    ).returns(mock(call: report))
    Projections::PdfReport.expects(:new).with(
      family: @user.family, projection: projection, financial_report: report
    ).returns(mock(render: "%PDF-test"))

    @fn.call
  ensure
    Current.reset
  end
end
