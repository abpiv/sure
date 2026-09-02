require "prawn"

module Projections
  class PdfReport
    COLORS = {
      ink: "17212B",
      secondary: "667085",
      subdued: "98A2B3",
      border: "D0D5DD",
      panel: "F8FAFC",
      blue: "1570EF",
      blue_tint: "EFF8FF",
      green: "079455",
      red: "D92D20",
      white: "FFFFFF"
    }.freeze

    DASHBOARD_HEIGHT = 539

    def initialize(family:, projection:, financial_report:)
      @family = family
      @projection = projection
      @financial_report = financial_report
    end

    def render
      @pdf = Prawn::Document.new(
        page_size: "A4",
        page_layout: :landscape,
        margin: 28,
        info: {
          Title: "Financial Projections and Three-Statement Report",
          Author: safe_text(family.name),
          Subject: financial_report.basis,
          Creator: "Sure"
        }
      )

      draw_dashboard
      draw_income_statement
      draw_balance_sheet
      draw_cash_flow_statement
      draw_page_footers

      pdf.render
    end

    private
      attr_reader :family, :projection, :financial_report, :pdf

      def draw_dashboard
        pdf.fill_color COLORS[:ink]
        pdf.text_box "Financial Projections", at: [ 0, pdf.bounds.top ], width: 300, height: 28, size: 22, style: :bold
        pdf.text_box safe_text(family.name), at: [ 300, pdf.bounds.top ], width: 486, align: :right, size: 10, color: COLORS[:secondary]
        pdf.move_cursor_to pdf.bounds.top - 28
        pdf.text "#{financial_report.basis}  |  Generated #{financial_report.as_of.strftime("%B %-d, %Y")}", size: 8.5, color: COLORS[:secondary]

        metric_width = (pdf.bounds.width - 30) / 4.0
        metric_y = pdf.bounds.top - 55
        metric_cards.each_with_index do |metric, index|
          x = index * (metric_width + 10)
          draw_metric_card(x: x, y: metric_y, width: metric_width, label: metric.fetch(:label), value: metric.fetch(:value), hint: metric[:hint])
        end

        draw_chart_panel(
          x: 0,
          y: metric_y - 78,
          width: pdf.bounds.width,
          height: 155,
          title: "Cash balance over time",
          metric: :cash_balance,
          type: :line
        )

        chart_width = (pdf.bounds.width - 20) / 3.0
        [
          [ :net_income, "Net income" ],
          [ :revenue, "Revenue" ],
          [ :operating_expenses, "Operating expenses" ]
        ].each_with_index do |(metric, title), index|
          draw_chart_panel(
            x: index * (chart_width + 10),
            y: metric_y - 248,
            width: chart_width,
            height: 150,
            title: title,
            metric: metric,
            type: :bar
          )
        end

        pdf.bounding_box([ 0, 58 ], width: pdf.bounds.width, height: 10) do
          pdf.text "Actual: completed months  |  Projected: active recurring transactions  |  Forecast horizon: #{projection.forecast_months} months",
            size: 7.5, color: COLORS[:secondary]
        end
      end

      def metric_cards
        [
          { label: "Liquid assets", value: format_money(projection.liquid_assets), hint: "Accessible cash accounts" },
          { label: "Monthly burn", value: format_money(projection.burn_rate), hint: "Recurring operating expenses" },
          { label: "Runway", value: format_runway, hint: "At projected net burn" },
          { label: "Projected cash-out", value: format_cash_out_date, hint: "From scheduled recurring activity" }
        ]
      end

      def draw_metric_card(x:, y:, width:, label:, value:, hint:)
        pdf.bounding_box([ x, y ], width: width, height: 64) do
          pdf.fill_color COLORS[:panel]
          pdf.stroke_color COLORS[:border]
          pdf.fill_and_stroke_rounded_rectangle [ 0, 64 ], width, 64, 6
          pdf.fill_color COLORS[:secondary]
          pdf.text_box label, at: [ 11, 51 ], width: width - 22, height: 14, size: 8.5
          pdf.fill_color COLORS[:ink]
          pdf.text_box value, at: [ 11, 33 ], width: width - 22, height: 22, size: 14, style: :bold, overflow: :shrink_to_fit
          pdf.fill_color COLORS[:subdued]
          pdf.text_box hint, at: [ 11, 12 ], width: width - 22, height: 10, size: 6.8, overflow: :shrink_to_fit
        end
      end

      def draw_chart_panel(x:, y:, width:, height:, title:, metric:, type:)
        pdf.bounding_box([ x, y ], width: width, height: height) do
          pdf.fill_color COLORS[:white]
          pdf.stroke_color COLORS[:border]
          pdf.fill_and_stroke_rounded_rectangle [ 0, height ], width, height, 6
          pdf.fill_color COLORS[:ink]
          pdf.text_box title, at: [ 11, height - 10 ], width: width - 22, height: 14, size: 9, style: :bold

          origin_x = width > 300 ? 52 : 39
          origin_y = 22
          chart_width = width - origin_x - 12
          chart_height = height - 52
          draw_chart_axes(origin_x: origin_x, origin_y: origin_y, width: chart_width, height: chart_height, metric: metric)

          if type == :line
            draw_line_chart(origin_x: origin_x, origin_y: origin_y, width: chart_width, height: chart_height, metric: metric)
          else
            draw_bar_chart(origin_x: origin_x, origin_y: origin_y, width: chart_width, height: chart_height, metric: metric)
          end
        end
      end

      def draw_chart_axes(origin_x:, origin_y:, width:, height:, metric:)
        min_value, max_value = chart_domain(metric)

        3.times do |index|
          ratio = index / 2.0
          y = origin_y + ratio * height
          value = min_value + ratio * (max_value - min_value)
          pdf.stroke_color COLORS[:border]
          pdf.line_width 0.4
          pdf.dash 1, space: 2
          pdf.stroke_horizontal_line origin_x, origin_x + width, at: y
          pdf.undash
          pdf.fill_color COLORS[:subdued]
          pdf.text_box compact_amount(value), at: [ 0, y + 3 ], width: origin_x - 5, height: 9, align: :right, size: 6.2
        end

        points = chart_points
        label_step = points.length > 10 ? 2 : 1
        points.each_with_index do |point, index|
          next unless (index % label_step).zero? || index == points.length - 1

          x = x_position(index, points.length, origin_x, width)
          pdf.fill_color COLORS[:subdued]
          pdf.text_box(point.month.strftime("%b"), at: [ x - 12, origin_y - 8 ], width: 24, height: 8, align: :center, size: 6.2)
        end

        actual_count = projection.actual_points.length
        return if actual_count.zero? || actual_count == points.length

        boundary_x = x_position(actual_count - 0.5, points.length, origin_x, width)
        pdf.stroke_color COLORS[:blue]
        pdf.dash 2, space: 2
        pdf.line_width 0.6
        pdf.stroke_vertical_line origin_y, origin_y + height, at: boundary_x
        pdf.undash
        pdf.fill_color COLORS[:blue]
        pdf.text_box "Forecast", at: [ boundary_x + 3, origin_y + height - 1 ], width: 35, height: 8, size: 5.8
      end

      def draw_line_chart(origin_x:, origin_y:, width:, height:, metric:)
        points = chart_points
        return if points.empty?

        min_value, max_value = chart_domain(metric)
        actual_count = projection.actual_points.length
        actual_values = points.first(actual_count)
        projected_values = points.drop([ actual_count - 1, 0 ].max)

        stroke_series(actual_values, offset: 0, color: COLORS[:ink], origin_x: origin_x, origin_y: origin_y, width: width, height: height, min_value: min_value, max_value: max_value, metric: metric)
        stroke_series(projected_values, offset: [ actual_count - 1, 0 ].max, color: COLORS[:blue], origin_x: origin_x, origin_y: origin_y, width: width, height: height, min_value: min_value, max_value: max_value, metric: metric, dashed: true)

        points.each_with_index do |point, index|
          x = x_position(index, points.length, origin_x, width)
          y = y_position(point.public_send(metric).amount.to_f, min_value, max_value, origin_y, height)
          pdf.fill_color index < actual_count ? COLORS[:ink] : COLORS[:blue]
          pdf.fill_circle [ x, y ], 1.8
        end
      end

      def stroke_series(points, offset:, color:, origin_x:, origin_y:, width:, height:, min_value:, max_value:, metric:, dashed: false)
        return if points.length < 2

        pdf.stroke_color color
        pdf.line_width 1.7
        pdf.dash 4, space: 3 if dashed
        coordinates = points.each_with_index.map do |point, index|
          [
            x_position(index + offset, chart_points.length, origin_x, width),
            y_position(point.public_send(metric).amount.to_f, min_value, max_value, origin_y, height)
          ]
        end
        pdf.stroke do
          pdf.move_to coordinates.first
          coordinates.drop(1).each { |coordinate| pdf.line_to coordinate }
        end
        pdf.undash if dashed
      end

      def draw_bar_chart(origin_x:, origin_y:, width:, height:, metric:)
        points = chart_points
        return if points.empty?

        min_value, max_value = chart_domain(metric)
        zero_y = y_position(0, min_value, max_value, origin_y, height)
        slot_width = width / points.length.to_f
        bar_width = [ slot_width * 0.58, 14 ].min
        actual_count = projection.actual_points.length

        points.each_with_index do |point, index|
          value = point.public_send(metric).amount.to_f
          value_y = y_position(value, min_value, max_value, origin_y, height)
          bar_y = [ zero_y, value_y ].min
          bar_height = [ (zero_y - value_y).abs, 0.8 ].max
          x = origin_x + index * slot_width + (slot_width - bar_width) / 2.0

          color = if value.negative?
            COLORS[:red]
          elsif index < actual_count
            COLORS[:secondary]
          else
            COLORS[:blue]
          end
          pdf.fill_color color
          pdf.fill_rounded_rectangle [ x, bar_y + bar_height ], bar_width, bar_height, 1.5
        end
      end

      def chart_points
        @chart_points ||= projection.actual_points + projection.projected_points
      end

      def chart_domain(metric)
        values = chart_points.map { |point| point.public_send(metric).amount.to_f }
        values << 0
        min_value, max_value = values.minmax
        if min_value == max_value
          padding = min_value.zero? ? 1 : min_value.abs * 0.2
          [ min_value - padding, max_value + padding ]
        else
          padding = (max_value - min_value) * 0.1
          [ min_value - padding, max_value + padding ]
        end
      end

      def x_position(index, count, origin_x, width)
        return origin_x + width / 2.0 if count <= 1

        origin_x + index * width / (count - 1).to_f
      end

      def y_position(value, min_value, max_value, origin_y, height)
        origin_y + (value - min_value) * height / (max_value - min_value).to_f
      end

      def draw_income_statement
        start_statement_page(
          "Income Statement",
          "#{format_date(financial_report.period.begin)} to #{format_date(financial_report.period.end)}"
        )
        statement = financial_report.income_statement
        rows = []
        rows << section_row("Revenue")
        rows.concat line_rows(statement.revenue_lines)
        rows << total_row("Total revenue", statement.total_revenue)
        rows << section_row("Operating expenses")
        rows.concat line_rows(statement.expense_lines)
        rows << total_row("Total operating expenses", statement.total_expenses)
        rows << grand_total_row("Net income", statement.net_income)
        draw_statement_table(rows, continued_title: "Income Statement")
      end

      def draw_balance_sheet
        start_statement_page("Balance Sheet", "As of #{format_date(financial_report.as_of)}")
        statement = financial_report.balance_sheet
        rows = []
        rows << section_row("Assets")
        rows.concat line_rows(statement.asset_lines)
        rows << total_row("Total assets", statement.total_assets)
        rows << section_row("Liabilities")
        rows.concat line_rows(statement.liability_lines)
        rows << total_row("Total liabilities", statement.total_liabilities)
        rows << grand_total_row("Net assets / equity", statement.equity)
        draw_statement_table(rows, continued_title: "Balance Sheet")
      end

      def draw_cash_flow_statement
        start_statement_page(
          "Cash Flow Statement",
          "#{format_date(financial_report.period.begin)} to #{format_date(financial_report.period.end)}"
        )
        statement = financial_report.cash_flow
        rows = []
        rows << [ safe_text("Beginning cash"), format_money(statement.beginning_cash) ]
        rows << section_row("Operating activities")
        rows << [ safe_text("Cash received from operations"), format_money(statement.operating_receipts) ]
        rows << [ safe_text("Cash paid for operating expenses"), format_money(-statement.operating_payments) ]
        rows << total_row("Net cash from operating activities", statement.net_operating_cash_flow)
        rows << section_row("Investing activities")
        rows << [ safe_text("Investment withdrawals"), format_money(statement.investing_inflows) ]
        rows << [ safe_text("Investment contributions"), format_money(-statement.investing_outflows) ]
        rows << total_row("Net cash from investing activities", statement.net_investing_cash_flow)
        rows << section_row("Financing activities")
        rows << [ safe_text("Financing inflows"), format_money(statement.financing_inflows) ]
        rows << [ safe_text("Debt principal payments"), format_money(-statement.financing_outflows) ]
        rows << total_row("Net cash from financing activities", statement.net_financing_cash_flow)
        rows << [ safe_text("Other / unclassified cash movements"), format_money(statement.other_cash_movements) ]
        rows << total_row("Net change in cash", statement.net_change_in_cash)
        rows << grand_total_row("Ending cash", statement.ending_cash)
        draw_statement_table(rows, continued_title: "Cash Flow Statement")
        pdf.move_down 14
        pdf.text "The reconciliation line captures cash movements that Sure cannot classify from transaction metadata. It keeps beginning and ending cash tied without implying audited GAAP classification.",
          size: 8, color: COLORS[:secondary], leading: 2
      end

      def start_statement_page(title, period_label)
        pdf.start_new_page(page_size: "A4", layout: :portrait, margin: 36)
        pdf.fill_color COLORS[:ink]
        pdf.draw_text title, at: [ 0, pdf.bounds.top - 21 ], size: 21, style: :bold
        draw_right_aligned_text(safe_text(family.name), y: pdf.bounds.top - 12, size: 9, color: COLORS[:ink])
        pdf.fill_color COLORS[:secondary]
        pdf.draw_text period_label, at: [ 0, pdf.bounds.top - 46 ], size: 9.5
        pdf.draw_text financial_report.basis, at: [ 0, pdf.bounds.top - 61 ], size: 8
        pdf.move_cursor_to pdf.bounds.top - 82
      end

      def draw_statement_table(rows, continued_title:)
        styles = rows.map { |row| row_style(row) }
        amount_column_width = 140
        table_width = pdf.bounds.width
        label_column_width = table_width - amount_column_width

        rows.each_with_index do |row, index|
          style = styles[index]
          row_height = style == :section ? 27 : 25
          start_continued_statement_page(continued_title) if pdf.cursor - row_height < 50

          row_top = pdf.cursor
          background_color = case style
          when :section then COLORS[:panel]
          when :grand_total then COLORS[:blue_tint]
          else COLORS[:white]
          end

          text_color = style == :grand_total ? COLORS[:blue] : (style == :section ? COLORS[:secondary] : COLORS[:ink])
          font_style = %i[section total grand_total].include?(style) ? :bold : :normal
          label = truncate_text(row.fetch(0), width: label_column_width - 18, size: 9, style: font_style)
          amount = row.fetch(1)

          pdf.bounding_box([ 0, row_top ], width: table_width, height: row_height) do
            pdf.fill_color background_color
            pdf.stroke_color COLORS[:border]
            pdf.fill_and_stroke_rectangle [ 0, row_height ], table_width, row_height
            pdf.stroke_vertical_line 0, row_height, at: label_column_width
            pdf.fill_color text_color
            pdf.text_box label, at: [ 9, row_height - 7 ], width: label_column_width - 18, height: row_height - 8, size: 9, style: font_style
            pdf.text_box amount, at: [ label_column_width + 9, row_height - 7 ], width: amount_column_width - 18, height: row_height - 8, size: 9, style: :bold, align: :right unless amount.empty?
          end
          pdf.move_cursor_to row_top - row_height
        end
      end

      def start_continued_statement_page(title)
        pdf.start_new_page(page_size: "A4", layout: :portrait, margin: 36)
        pdf.fill_color COLORS[:ink]
        pdf.draw_text "#{title} (continued)", at: [ 0, pdf.bounds.top - 18 ], size: 18, style: :bold
        draw_right_aligned_text(safe_text(family.name), y: pdf.bounds.top - 12, size: 9, color: COLORS[:ink])
        pdf.fill_color COLORS[:secondary]
        pdf.draw_text financial_report.basis, at: [ 0, pdf.bounds.top - 46 ], size: 8
        pdf.move_cursor_to pdf.bounds.top - 68
      end

      def draw_right_aligned_text(value, y:, size:, color:)
        pdf.fill_color color
        width = pdf.width_of(value, size: size)
        pdf.draw_text value, at: [ pdf.bounds.width - width, y ], size: size
      end

      def truncate_text(value, width:, size:, style:)
        return value if pdf.width_of(value, size: size, style: style) <= width

        text = value.dup
        text = text.chop while text.length > 1 && pdf.width_of("#{text}...", size: size, style: style) > width
        "#{text}..."
      end

      def section_row(label)
        [ safe_text(label), "__SECTION__" ]
      end

      def total_row(label, amount)
        [ safe_text(label), "__TOTAL__#{format_money(amount)}" ]
      end

      def grand_total_row(label, amount)
        [ safe_text(label), "__GRAND_TOTAL__#{format_money(amount)}" ]
      end

      def line_rows(lines)
        return [ [ safe_text("No activity"), format_money(Money.new(0, projection.currency)) ] ] if lines.empty?

        lines.map { |line| [ safe_text(line.name), format_money(line.amount) ] }
      end

      def row_style(row)
        value = row.fetch(1)
        if value == "__SECTION__"
          row[1] = ""
          :section
        elsif value.start_with?("__GRAND_TOTAL__")
          row[1] = value.delete_prefix("__GRAND_TOTAL__")
          :grand_total
        elsif value.start_with?("__TOTAL__")
          row[1] = value.delete_prefix("__TOTAL__")
          :total
        end
      end

      def draw_page_footers
        page_count = pdf.page_count
        (1..page_count).each do |page_number|
          pdf.go_to_page(page_number)
          pdf.fill_color COLORS[:secondary]
          pdf.text_box "Sure  |  #{financial_report.basis}", at: [ 0, 10 ], width: pdf.bounds.width - 80, height: 10, size: 6.8
          pdf.text_box "Page #{page_number} of #{page_count}", at: [ pdf.bounds.width - 80, 10 ], width: 80, height: 10, align: :right, size: 6.8
        end
      end

      def format_money(value)
        amount = value.amount.to_f
        sign = amount.negative? ? "-" : ""
        numeric = ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", amount.abs), delimiter: ",", separator: ".")
        "#{value.currency.iso_code} #{sign}#{numeric}"
      end

      def compact_amount(value)
        absolute = value.abs
        formatted = if absolute >= 1_000_000
          "#{(absolute / 1_000_000.0).round(1)}M"
        elsif absolute >= 1_000
          "#{(absolute / 1_000.0).round(1)}K"
        else
          absolute.round.to_s
        end
        "#{value.negative? ? "-" : ""}#{formatted}"
      end

      def format_runway
        projection.runway_months ? "#{projection.runway_months} months" : "Not projected"
      end

      def format_cash_out_date
        projection.cash_out_date ? projection.cash_out_date.strftime("%b %-d, %Y") : "Not projected"
      end

      def format_date(date)
        date.strftime("%B %-d, %Y")
      end

      def safe_text(value)
        value.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?")
      end
  end
end
