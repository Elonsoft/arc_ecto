defmodule Arc.Ecto.Schema do
  @moduledoc false

  def cast_attachments(data = %_{__meta__: _}, params, allowed, options) do
    # Cast supports both atom and string keys, ensure we're matching on both.
    allowed_param_keys = Enum.map(allowed, &to_string/1)

    arc_params =
      params
      |> convert_params_to_binary
      |> Map.take(allowed_param_keys)
      |> Enum.reduce([], &cast_param(data, options, &1, &2))
      |> Enum.into(%{})

    Ecto.Changeset.cast(data, arc_params, allowed)
  end

  def cast_attachments(data = %_{__meta__: _}, params, allowed) do
    cast_attachments(data, params, allowed, [])
  end

  def cast_attachments(changeset = %Ecto.Changeset{params: params}, allowed, options) do
    changeset
    |> do_apply_changes
    |> cast_attachments(params, allowed, options)
  end

  def cast_attachments(changeset = %Ecto.Changeset{}, allowed) do
    cast_attachments(changeset, allowed, [])
  end

  defp do_apply_changes(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.apply_changes(changeset)
  end

  defp do_apply_changes(%{__meta__: _} = data) do
    data
  end

  defp convert_params_to_binary(params) do
    Enum.reduce(params, nil, fn
      {key, _value}, nil when is_binary(key) ->
        nil

      {key, _value}, _ when is_binary(key) ->
        raise ArgumentError, "expected params to be a map with atoms or string keys, " <>
                             "got a map with mixed keys: #{inspect params}"

      {key, value}, acc when is_atom(key) ->
        Map.put(acc || %{}, Atom.to_string(key), value)

    end) || params
  end

  defp base64_to_binary(image_base64) do
    # Decode the image
    {start, length} = :binary.match(image_base64, ";base64,")

    base64_string =
      :binary.part(image_base64, start + length, byte_size(image_base64) - start - length)

    {:ok, image_binary} = Base.decode64(base64_string)

    # Generate a unique filename
    filename = unique_filename(image_binary)

    %{filename: filename, binary: image_binary}
  end

  # NOTE: Generates a unique filename with a given extension
  defp unique_filename(binary) do
    "document_" <> Ecto.UUID.generate() <> image_extension(binary)
  end

  # NOTE: Helper functions to read the binary to determine the image extension
  defp image_extension(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: ".png"
  defp image_extension(<<0xFF, 0xD8, _::binary>>), do: ".jpg"

  # Don't wrap nil casts in the scope object
  defp cast_param(_scope, _options, {field, nil}, fields) do
    [{field, nil} | fields]
  end

  # Allow casting Plug.Uploads
  defp cast_param(_scope, _options, {field, upload = %{__struct__: Plug.Upload}}, fields) do
    [{field, {upload, scope}} | fields]
  end

  # Allow updating
  defp cast_param(_scope, _options, {_field, %{file_name: filename, updated_at: _}}, fields)
  when is_binary(filename) do
    fields
  end

  # Allow casting binary data structs
  defp cast_param(_scope, _options, {field, upload = %{filename: filename, binary: binary}}, fields)
  when is_binary(filename) and is_binary(binary) do
    [{field, {upload, scope}} | fields]
  end

  # Allow base64.
  defp cast_param(_scope, _options, {field, base64 = <<"data:image/"::binary, _::binary>>}, fields) do
    image = base64_to_binary(base64)
    [{field, {image, scope}} | fields]
  end

  # If casting a binary (path), ensure we've explicitly allowed paths
  defp cast_param(scope, options, {field, path}, fields) when is_binary(path) do
    cond do
      Keyword.get(options, :allow_urls, false) and Regex.match?( ~r/^https?:\/\// , path) -> [{field, {path, scope}} | fields]
      Keyword.get(options, :allow_paths, false) -> [{field, {path, scope}} | fields]
      true -> fields
    end
  end
end
