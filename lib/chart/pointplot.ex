defmodule Contex.PointPlot do

  alias __MODULE__
  alias Contex.{Scale, ContinuousScale, TimeScale}
  alias Contex.CategoryColourScale
  alias Contex.Dataset
  alias Contex.Axis
  alias Contex.Utils

  defstruct [:data, :width, :height, :x_col, :y_cols, :fill_col, :size_col, :x_scale, :y_scale, :fill_scale, :colour_palette]

  def new(%Dataset{} = data) do
    %PointPlot{data: data, width: 100, height: 100}
    |> defaults()
  end

  def defaults(%PointPlot{} = plot) do
    x_col_index = 0
    y_col_index = 1

    x_col_name = Dataset.column_name(plot.data, x_col_index)
    y_col_names = [Dataset.column_name(plot.data, y_col_index)]

    %{plot | colour_palette: :default}
    |> set_x_col_name(x_col_name)
    |> set_y_col_names(y_col_names)
  end

  def colours(plot, colour_palette) when is_list(colour_palette) or is_atom(colour_palette) do
    %{plot | colour_palette: colour_palette}
    |> set_y_col_names(plot.y_cols)
  end
  def colours(plot, _) do
    %{plot | colour_palette: :default}
    |> set_y_col_names(plot.y_cols)
  end

  def set_size(%PointPlot{} = plot, width, height) do
    # We pretend to set the x & y columns to force a recalculation of scales - may be expensive.
    # We only really need to set the range, not recalculate the domain
    %{plot | width: width, height: height}
    |> set_x_col_name(plot.x_col)
    |> set_y_col_names(plot.y_cols)
  end

  def get_svg_legend(%PointPlot{fill_scale: scale}) do
    Contex.Legend.to_svg(scale)
  end
  def get_svg_legend(_), do: ""

  def to_svg(%PointPlot{x_scale: x_scale, y_scale: y_scale} = plot) do
    axis_x = get_x_axis(x_scale, plot.height)
    axis_y = Axis.new_left_axis(y_scale) |> Axis.set_offset(plot.width)

    [
      Axis.to_svg(axis_x),
      Axis.to_svg(axis_y),
      "<g>",
      get_svg_points(plot),
      "</g>"
      #,get_svg_line(plot)
    ]
  end

  defp get_x_axis(x_scale, offset) do
    axis
      = Axis.new_bottom_axis(x_scale)
        |> Axis.set_offset(offset)

    case length(Scale.ticks_range(x_scale)) > 8 do
      true -> %{axis | rotation: 45}
      _ -> axis
    end
  end

  defp get_svg_points(%PointPlot{data: dataset} = plot) do
    x_col_index = Dataset.column_index(dataset, plot.x_col)
    y_col_indices = Enum.map(plot.y_cols, fn col -> Dataset.column_index(dataset, col) end)

    fill_col_index = Dataset.column_index(dataset, plot.fill_col)

    dataset.data
    |> Enum.map(fn row ->
      get_svg_point(row, plot, x_col_index, y_col_indices, fill_col_index)
    end)
  end

  defp get_svg_line(%PointPlot{data: dataset, x_scale: x_scale, y_scale: y_scale} = plot) do
    x_col_index = Dataset.column_index(dataset, plot.x_col)
    y_col_index = Dataset.column_index(dataset, plot.y_col)
    x_tx_fn = x_scale.domain_to_range_fn
    y_tx_fn = y_scale.domain_to_range_fn

    style = ~s|stroke="red" stroke-width="2" fill="none" stroke-dasharray="13,2" stroke-linejoin="round" |

    last_item = Enum.count(dataset.data) - 1
    path = ["M",
        dataset.data
         |> Enum.map(fn row ->
              x = Dataset.value(row, x_col_index)
              y = Dataset.value(row, y_col_index)
              {x_tx_fn.(x), y_tx_fn.(y)}
            end)
         |> Enum.with_index()
         |> Enum.map(fn {{x_plot, y_plot}, i} ->
            case i < last_item do
              true -> ~s|#{x_plot} #{y_plot} L |
              _ -> ~s|#{x_plot} #{y_plot}|
            end
          end)
    ]

    [~s|<path d="|, path, ~s|"|, style, "></path>"]
  end


  defp get_svg_point(row, %PointPlot{x_scale: x_scale, y_scale: y_scale, fill_scale: fill_scale}=plot, x_col_index, [y_col_index]=y_col_indices, fill_col_index) when length(y_col_indices) == 1 do
    x_data = Dataset.value(row, x_col_index)
    y_data = Dataset.value(row, y_col_index)

    fill_data = if is_integer(fill_col_index) and fill_col_index >= 0 do
      Dataset.value(row, fill_col_index)
    else
      Enum.at(plot.y_cols, 0)
    end

    x = x_scale.domain_to_range_fn.(x_data)
    y = y_scale.domain_to_range_fn.(y_data)
    fill = CategoryColourScale.colour_for_value(fill_scale, fill_data)

    get_svg_point(x, y, fill)
  end

  defp get_svg_point(row, %PointPlot{x_scale: x_scale, y_scale: y_scale, fill_scale: fill_scale, y_cols: y_cols}, x_col_index, y_col_indices, _fill_col_index) do
    x_data = Dataset.value(row, x_col_index)
    x = x_scale.domain_to_range_fn.(x_data)

    Enum.zip(y_col_indices, y_cols)
    |> Enum.map(fn {index, name} ->
      y_data = Dataset.value(row, index)
      y = y_scale.domain_to_range_fn.(y_data)
      fill = CategoryColourScale.colour_for_value(fill_scale, name)
      get_svg_point(x, y, fill)
    end)
  end

  defp get_svg_point(x, y, fill) when is_number(x) and is_number(y) do
    [~s|<circle cx="#{x}" cy="#{y}"|, ~s| r="3" style="fill: ##{fill};"></circle>|]
  end
  defp get_svg_point(_x, _y, _fill), do: ""

  def set_x_col_name(%PointPlot{width: width} = plot, x_col_name) do
    x_scale = create_scale_for_column(plot.data, x_col_name, {0, width})
    %{plot | x_col: x_col_name, x_scale: x_scale}
  end

  def set_y_col_names(%PointPlot{height: height} = plot, y_col_names) when is_list(y_col_names) do
    {min, max} =
      get_overall_domain(plot.data, y_col_names)
      |> Utils.fixup_value_range()

    y_scale = ContinuousScale.new_linear()
      |> ContinuousScale.domain(min, max)
      |> Scale.set_range(height, 0)

    series_fill_colours
      = CategoryColourScale.new(y_col_names)
      |> CategoryColourScale.set_palette(plot.colour_palette)

    %{plot | y_cols: y_col_names, y_scale: y_scale, fill_scale: series_fill_colours}
  end

  defp get_overall_domain(data, col_names) do
    combiner = fn {min1, max1}, {min2, max2} -> {Utils.safe_min(min1, min2), Utils.safe_max(max1, max2)} end

    Enum.reduce(col_names, {nil, nil}, fn col, acc_extents ->
          inner_extents = Dataset.column_extents(data, col)
          combiner.(acc_extents, inner_extents)
        end )
  end

  defp create_scale_for_column(data, column, {r_min, r_max}) do
    {min, max} = Dataset.column_extents(data, column)

    case Dataset.guess_column_type(data, column) do
      :datetime ->
        TimeScale.new()
          |> TimeScale.domain(min, max)
          |> Scale.set_range(r_min, r_max)
      :number ->
        ContinuousScale.new_linear()
          |> ContinuousScale.domain(min, max)
          |> Scale.set_range(r_min, r_max)
    end
  end

  def set_colour_col_name(%PointPlot{} = plot, colour_col_name) do
    vals = Dataset.unique_values(plot.data, colour_col_name)
    colour_scale = CategoryColourScale.new(vals)

    %{plot | fill_col: colour_col_name, fill_scale: colour_scale}
  end

  def set_x_range(%PointPlot{x_scale: scale} = plot, start, finish) when not is_nil(scale) do
    %{plot | x_scale: Scale.set_range(scale, start, finish)}
  end

  def set_y_range(%PointPlot{y_scale: scale} = plot, start, finish) when not is_nil(scale) do
    %{plot | y_scale: Scale.set_range(scale, start, finish)}
  end
end
