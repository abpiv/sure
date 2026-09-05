class Assistant::Function::ExportProjectionsReport < Assistant::Function
  MAX_HISTORY_MONTHS = 120
  MAX_PDF_BYTES = 5.megabytes

  class << self
    def name
      "export_projections_report"
    end

    def description
      <<~INSTRUCTIONS
        Generate the existing Projections PDF: dashboard, income statement,
        balance sheet and cash flow statement. history_months defaults to 1;
        use 3 for a three-month lookback. Historical statements cover completed
        calendar months. Balances and forecasts are current at generation time.

        Returns filename, mime_type, content_base64, byte_size, sha256, as_of,
        history_months, period_start and period_end. Decode content_base64 into
        a PDF attachment; never print it in chat. This reads only accounts the
        authenticated user can access. It sends no email, saves no document and
        changes no financial records. A caller may retry generation, but must
        separately control retries of downstream email delivery.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(properties: {
      history_months: {
        type: "integer", minimum: 1, maximum: MAX_HISTORY_MONTHS,
        description: "Completed months in the lookback; defaults to 1."
      }
    })
  end

  def call(params = {})
    unless params.is_a?(Hash) && (params.keys - [ "history_months" ]).empty?
      raise ArgumentError, "Only history_months is accepted"
    end

    history_months = params.fetch("history_months", 1)
    unless history_months.is_a?(Integer) && (1..MAX_HISTORY_MONTHS).cover?(history_months)
      raise ArgumentError, "history_months must be an integer between 1 and #{MAX_HISTORY_MONTHS}"
    end

    as_of = Date.current
    projection = Projections::Calculator.new(
      family: family, user: user, as_of: as_of, history_months: history_months
    ).call
    financial_report = Projections::FinancialReport.new(
      family: family, user: user, projection: projection, as_of: as_of
    ).call
    pdf = Projections::PdfReport.new(
      family: family, projection: projection, financial_report: financial_report
    ).render
    raise Assistant::Error, "Report exceeds the 5 MiB export limit" if pdf.bytesize > MAX_PDF_BYTES

    {
      filename: "financial-projections-#{as_of.iso8601}.pdf",
      mime_type: "application/pdf",
      content_base64: Base64.strict_encode64(pdf),
      byte_size: pdf.bytesize,
      sha256: Digest::SHA256.hexdigest(pdf),
      as_of: as_of.iso8601,
      history_months: history_months,
      period_start: (as_of.beginning_of_month - history_months.months).iso8601,
      period_end: (as_of.beginning_of_month - 1.day).iso8601
    }
  end
end
