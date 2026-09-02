import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import { CHART_TOOLTIP_CLASSES } from "utils/chart_tooltip";

export default class extends Controller {
  static values = {
    data: Array,
    metric: String,
    type: { type: String, default: "bar" },
    currency: { type: String, default: "USD" },
  };

  _resizeObserver = null;

  connect() {
    this._install();
    document.addEventListener("turbo:load", this._reinstall);
    this._resizeObserver = new ResizeObserver(this._reinstall);
    this._resizeObserver.observe(this.element);
  }

  disconnect() {
    this._teardown();
    document.removeEventListener("turbo:load", this._reinstall);
    this._resizeObserver?.disconnect();
  }

  _reinstall = () => {
    this._teardown();
    this._install();
  };

  _teardown() {
    d3.select(this.element).selectAll("*").remove();
  }

  _install() {
    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    const data = this.dataValue || [];
    if (width < 80 || height < 80 || data.length === 0) return;

    const margin = { top: 16, right: 10, bottom: 28, left: 42 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;
    const values = data.map((datum) => Number(datum[this.metricValue]));
    const extent = d3.extent([...values, 0]);
    const padding =
      extent[0] === extent[1]
        ? Math.max(Math.abs(extent[0]) * 0.2, 1)
        : (extent[1] - extent[0]) * 0.1;

    const x = d3
      .scaleBand()
      .domain(data.map((_datum, index) => index))
      .range([0, innerWidth])
      .padding(this.typeValue === "bar" ? 0.34 : 0.05);
    const y = d3
      .scaleLinear()
      .domain([extent[0] - padding, extent[1] + padding])
      .nice()
      .range([innerHeight, 0]);

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height]);
    const group = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    this._drawGrid(group, y, innerWidth);
    this._drawAxes(group, x, y, data, innerHeight);
    this._drawForecastBoundary(group, x, data, innerHeight);

    const tooltip = d3
      .select(this.element)
      .append("div")
      .attr("class", `${CHART_TOOLTIP_CLASSES} opacity-0 top-0`);
    const showTooltip = (event, datum) => {
      const expectedWidth = 210;
      const preferredX = event.pageX + 10;
      const left =
        preferredX + expectedWidth > document.body.clientWidth
          ? event.pageX - expectedWidth - 10
          : preferredX;
      tooltip
        .html(this._tooltipTemplate(datum))
        .style("opacity", 1)
        .style("left", `${left}px`)
        .style("top", `${event.pageY - 10}px`);
    };
    const hideTooltip = () => tooltip.style("opacity", 0);

    if (this.typeValue === "line") {
      this._drawLine(group, x, y, data, showTooltip, hideTooltip);
    } else {
      this._drawBars(group, x, y, data, showTooltip, hideTooltip);
    }
  }

  _drawGrid(group, y, width) {
    group
      .append("g")
      .call(d3.axisLeft(y).ticks(4).tickSize(-width).tickFormat(""))
      .call((axis) => axis.select(".domain").remove())
      .call((axis) =>
        axis
          .selectAll("line")
          .attr("stroke", "var(--color-gray-200)")
          .attr("stroke-dasharray", "2,3"),
      );
  }

  _drawAxes(group, x, y, data, height) {
    const visibleLabels = new Set(
      data
        .map((_datum, index) => index)
        .filter(
          (index) =>
            data.length <= 9 || index % 2 === 0 || index === data.length - 1,
        ),
    );
    group
      .append("g")
      .attr("transform", `translate(0,${height})`)
      .call(
        d3
          .axisBottom(x)
          .tickSize(0)
          .tickFormat((index) =>
            visibleLabels.has(index) ? data[index].short_label : "",
          ),
      )
      .call((axis) => axis.select(".domain").remove())
      .selectAll("text")
      .attr("class", "text-secondary fill-current")
      .style("font-size", "11px");

    group
      .append("g")
      .call(
        d3
          .axisLeft(y)
          .ticks(4)
          .tickSize(0)
          .tickFormat((value) => this._formatCompact(value)),
      )
      .call((axis) => axis.select(".domain").remove())
      .selectAll("text")
      .attr("class", "text-subdued fill-current")
      .style("font-size", "10px");
  }

  _drawForecastBoundary(group, x, data, height) {
    const firstProjected = data.findIndex((datum) => datum.projected);
    if (firstProjected < 0) return;

    const boundaryX = x(firstProjected) - x.step() * x.paddingOuter();
    group
      .append("line")
      .attr("x1", boundaryX)
      .attr("x2", boundaryX)
      .attr("y1", 0)
      .attr("y2", height)
      .attr("stroke", "var(--color-link)")
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "4,4");
  }

  _drawBars(group, x, y, data, showTooltip, hideTooltip) {
    const zeroY = y(0);
    group
      .selectAll("rect.projection-bar")
      .data(data)
      .join("rect")
      .attr("class", "projection-bar")
      .attr("x", (_datum, index) => x(index))
      .attr("y", (datum) => Math.min(y(Number(datum[this.metricValue])), zeroY))
      .attr("width", x.bandwidth())
      .attr("height", (datum) =>
        Math.max(1, Math.abs(zeroY - y(Number(datum[this.metricValue])))),
      )
      .attr("rx", 3)
      .attr("fill", (datum) => this._colorFor(datum))
      .on("mousemove", showTooltip)
      .on("mouseleave", hideTooltip);
  }

  _drawLine(group, x, y, data, showTooltip, hideTooltip) {
    const centerX = (index) => x(index) + x.bandwidth() / 2;
    const actual = data.filter((datum) => !datum.projected);
    const projected = data.filter((datum) => datum.projected);
    if (actual.length > 0 && projected.length > 0)
      projected.unshift(actual[actual.length - 1]);

    const line = d3
      .line()
      .x((datum) => centerX(data.indexOf(datum)))
      .y((datum) => y(Number(datum[this.metricValue])))
      .curve(d3.curveMonotoneX);

    [
      { points: actual, color: "var(--color-gray-700)", dash: null },
      { points: projected, color: "var(--color-link)", dash: "6,4" },
    ].forEach((series) => {
      if (series.points.length < 2) return;
      group
        .append("path")
        .datum(series.points)
        .attr("fill", "none")
        .attr("stroke", series.color)
        .attr("stroke-width", 2.5)
        .attr("stroke-linecap", "round")
        .attr("stroke-linejoin", "round")
        .attr("stroke-dasharray", series.dash)
        .attr("d", line);
    });

    group
      .selectAll("circle.projection-point")
      .data(data)
      .join("circle")
      .attr("class", "projection-point")
      .attr("cx", (_datum, index) => centerX(index))
      .attr("cy", (datum) => y(Number(datum[this.metricValue])))
      .attr("r", 4)
      .attr("fill", (datum) => this._colorFor(datum))
      .attr("stroke", "var(--color-container)")
      .attr("stroke-width", 2)
      .on("mousemove", showTooltip)
      .on("mouseleave", hideTooltip);
  }

  _colorFor(datum) {
    const value = Number(datum[this.metricValue]);
    if (value < 0) return "var(--color-destructive)";
    return datum.projected ? "var(--color-link)" : "var(--color-gray-500)";
  }

  _tooltipTemplate(datum) {
    const phase = datum.projected ? "Projected" : "Actual";
    return `
      <div class="text-xs text-secondary mb-1">${datum.label} · ${phase}</div>
      <div class="text-primary font-medium tabular-nums">${this._formatCurrency(datum[this.metricValue])}</div>
    `;
  }

  _formatCurrency(value) {
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this.currencyValue,
        maximumFractionDigits: 0,
      }).format(value);
    } catch {
      return value;
    }
  }

  _formatCompact(value) {
    try {
      return new Intl.NumberFormat(undefined, {
        notation: "compact",
        maximumFractionDigits: 1,
      }).format(value);
    } catch {
      return value;
    }
  }
}
