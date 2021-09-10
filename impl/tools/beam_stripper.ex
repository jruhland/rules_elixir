defmodule RulesElixir.Tools.BeamStripper do
  @moduledoc """
  When we compile in bazel, we are actually running inside a temporary directory with a very
  long and non-deterministic name.  Compilers like to embed paths things as absolute paths
  in the compiled .beam file, which is poor UX as well as a perpetual cache buster.

  So in this file we parse various sections of the .beam format which can contain embedded
  absolute paths, and rewrite all of those paths to be relative to the bazel execroot instead.

  NOTE: we effectively look for the string `/execroot/` in these paths; in practice all bazel local
  actions do have their execroots under such a path, but in remote execution this may not be true,
  which would render this script useless.
  """

  @counter_agent :counter_mapper_agent
  def start_link(), do: Agent.start_link(fn -> %{} end, name: @counter_agent)

  
  def debazelify(dirs) do
    start_link()
    for d <- dirs, beam_file <- Path.wildcard("#{d}/*.beam") do
      bin = File.read!(beam_file)
      new_bin = debazelify_bin(bin)
      File.write!(beam_file, new_bin)
    end
  end

  def debazelify_bin(bin) do
    {:ok, new_bin} = map_filename_strings(bin, &relative_to_workspace/1)
    new_bin
  end

  @marker "execroot"
  def relative_to_workspace(weird_bazel_path = <<"/", _rest::binary>>) do
    case Enum.drop_while(Path.split(weird_bazel_path), &@marker != &1) do
      [@marker, _workspace_name | path_in_workspace] ->
        Path.join(path_in_workspace)
      _ -> weird_bazel_path
    end
  end
  def relative_to_workspace(non_absolute_path), do: non_absolute_path

  def map_filename_strings!(beam, mapper) do
    {:ok, v} = map_filename_strings(beam, mapper)
    v
  end

  def map_filename_strings(beam, mapper) do
    {:ok, _mod, chunks} = :beam_lib.all_chunks(beam)
    charlist_mapper = fn chars when is_list(chars) -> to_charlist(mapper.(to_string(chars))) end

    for {ch, bin} <- chunks do
      case ch do
        # Line number table includes filenames and is encoded in a horrid BEAM-file-specific format
        'Line' -> {ch, rewrite_filenames_in_line_chunk(bin, mapper)}

        # Literals table can also have filenames stored in Macro.Env structs and stuff like that
        'LitT' -> {ch, rewrite_literals_table(bin, mapper)}

        # Funs table includes `ouniq` aka `old_uniq` which is based on the nondeterministic MD5
        # 'FunT' -> {ch, rewrite_functions_table(bin)}

        # Rest of the chunks are just encoded in regular external term format
        'Attr' ->
          :erlang.binary_to_term(bin)
          |> keyword_update_lazy(:external_resource, fn resources ->
               Enum.map(resources, mapper)
          end)
          # the version is gonna be based on the md5 of the nondeterminstic BEAM
          |> keyword_update_lazy(:vsn, fn _ -> [511572] end)
          |> :erlang.term_to_binary
          |> case do new_chunk -> {ch, new_chunk} end

        'CInf' ->
          :erlang.binary_to_term(bin)
          |> keyword_update_lazy(:source, charlist_mapper)
          |> keyword_update_lazy(:options, fn opts -> keyword_update_lazy(opts, :i, charlist_mapper) end)
          |> :erlang.term_to_binary
          |> case do new_chunk -> {ch, new_chunk} end

        'Dbgi' ->
          case :erlang.binary_to_term(bin) do
            {:debug_info_v1, :erl_abstract_code, {abs_code, props}} ->
              {:debug_info_v1, :erl_abstract_code,
               {walk(abs_code, mapper),
                keyword_update_lazy(props, :i, charlist_mapper)}}
              |> :erlang.term_to_binary([:compressed])
              |> case do new_chunk -> {ch, new_chunk} end

            {:debug_info_v1, :elixir_erl, {:elixir_v1, props, specs}} ->
              new_props =
                props
                |> map_update_lazy(:file, fn f when is_binary(f) -> mapper.(f) end)
                |> map_update_lazy(:attributes, fn attrs ->
                  keyword_update_lazy(attrs, :external_resource, mapper)
                end)
                |> map_update_lazy(:definitions, fn code -> walk(code, mapper) end)

              # This has since been fixed upstream in Elixir but we can just hack it here
              # https://github.com/elixir-lang/elixir/commit/3fd6cf5e917e2f1383d4ecf1f3de5726337f66dc
              new_specs =
                specs
                |> Enum.sort_by(fn s ->
                     case s do
                       {:attribute, line, _, _} -> line
                       _ ->
                         IO.warn("Found unsupported type spec attribute in elixir debug info")
                         0
                     end
                end)

              {:debug_info_v1, :elixir_erl, {:elixir_v1, new_props, new_specs}}
              |> :erlang.term_to_binary([:compressed])
              |> case do new_chunk -> {ch, new_chunk} end

            other_debug_info ->
              IO.warn("Found unsupported debug info format -- it will not be modified but may cause non-hermetic builds!")
              other_debug_info

          end

        _other_chunk_type  -> {ch, bin}

      end
    end
# some tests depend on this info
#     |> strip_chunks()
    |> :beam_lib.build_module
  end

  def strip_chunks(chunks) do
    for {ch, bin} <- chunks, ch in ['Atom', 'AtU8', 'Attr', 'Code', 'StrT', 'ImpT', 'ExpT', 'FunT', 'LitT', 'Line'] do
      {ch, bin}
    end
  end

  def map_update_lazy(m, k, f) do
    if Map.has_key?(m, k) do
      Map.update!(m, k, f)
    else
      m
    end
  end

  def keyword_update_lazy(ks, uk, f) do
    for item <- ks do
      case item do
        {k, v} when k == uk -> {k, f.(v)}
        # Pass through items which are not keywords
        _ -> item
      end
    end
  end

  # Elixir macro expansion adds a `counter` key to AST metadata, which then goes into 
  # It may indeed be a counter, but it start out as :erlang.unique_integer(), which simply will not do 
  # The numeric value does not matter, so we can just map each new counter to our own counter...
  # ... which starts from 0 and is therefore determinstic.  
  def map_counter(c) when is_number(c) do
    Agent.get_and_update(@counter_agent, fn state ->
      case Map.fetch(state, c) do
        {:ok, v} ->
          {v, state}
        _ ->
          next = Enum.count(state)
          {next, Map.put(state, c, next)}
      end
    end)
  end
  def map_counter(e), do: e
  
  # update filename metadata in some AST-like thing in the debug info 
  defp walk(e, f) do
    case e do
      _ when is_number(e) or is_atom(e) -> e
      [] -> []
      # :file always comes with :line so we have at least 2 keys
      [{k1, _v1}, {k2, _v2} | _more_kvs] when is_atom(k1) and is_atom(k2) ->
          case Keyword.fetch(e, :file) do
            {:ok, file} when is_binary(file) ->
              Keyword.put(e, :file, f.(file))
            {:ok, {file, n}} when is_binary(file) and is_number(n) ->
              Keyword.put(e, :file, {f.(file), n})
            _ -> e
          end
          |> Enum.map(fn
            {:counter, c} -> {:counter, map_counter(c)}
            {k, v} -> {k, walk(v, f)}
            e -> walk(e, f)
          end)
      
      {:attribute, n, :file, {old_file, m}} when is_list(old_file) ->
        {:attribute, n, :file, {to_charlist(f.(to_string(old_file))), m}}

      {:string, n, [c | _cs] = ch} when is_number(n) and is_number(c) ->
        {:string, n, to_charlist(f.(to_string(ch)))}

      # Yes, we really need to handle 6-tuples
      {a, b} -> {walk(a, f), walk(b, f)}
      {a, b, c} -> {walk(a, f), walk(b, f), walk(c, f)}
      {a, b, c, d} -> {walk(a, f), walk(b, f), walk(c, f), walk(d, f)}
      {a, b, c, d, e} -> {walk(a, f), walk(b, f), walk(c, f), walk(d, f), walk(e, f)}
      {a, b, c, d, e, f_} -> {walk(a, f), walk(b, f), walk(c, f), walk(d, f), walk(e, f), walk(f_, f)}
      xs when is_list(xs) -> for x <- xs, do: walk(x, f)
      _ when is_binary(e) -> f.(e)
      _ -> e
    end
  end
  
  ################################################################
  ## Line number table
  # See algorithm description at http://beam-wisdoms.clau.se/en/latest/indepth-beam-file.html#line-line-numbers-table
  # See also the relevant Erlang C source:
  # https://github.com/erlang/otp/blob/752911aed2af4a37dcc7abfb2d41067d958c3047/erts/emulator/beam/beam_load.c#L1709-L1804

  # Read tagged value from compressed encoding used in .beam files 
  def get_tag_and_value(<<ext_tag::bitstring-size(5), tag::3, rest::binary>>) do
    case ext_tag do
      # Bit 3 is zero, value is stored in the high 4 bits
      <<value::4, 0::1>> -> {{tag, value}, rest}

      # High 5 bits are 1s, it's some kind of huge value (>8 bytes), don't bother
      <<0b111::3, 0b11::2>> ->
          raise "Big boy"

      # Medium size value
      # See https://github.com/erlang/otp/blob/master/erts/emulator/beam/beam_load.c#L5789-L5792
      <<len_code::3, 0b11::2>> ->
          num_extra_bytes = len_code + 2
          <<extra_bytes::binary-size(num_extra_bytes), rest1::binary>> = rest
          {{tag, extra_bytes}, rest1}
        
      # Single continutation byte,
      # Value is UNDER 2048, so it will fit in 8+3 = 11 bytes
      <<extra_bits::3, 1::2>> ->
        <<nextbyte, rest1::binary>> = rest
        <<value::11>> = <<extra_bits::3, nextbyte>>
        {{tag, value}, rest1}
    end
  end

  # This part of the data is about the mapping between instructions and lines,
  # which we don't actually care about; we just need to parse it enough to
  # know how many bytes to skip before the filename table 
  def ignore_line_items(bin, 0), do: bin
  def ignore_line_items(bin, items_remaining) do
    {{tag, _value}, rest} = get_tag_and_value(bin)
    case tag do
      1 -> ignore_line_items(rest, items_remaining - 1)
      2 -> ignore_line_items(rest, items_remaining)
    end
  end

  # The filenames table comprises the entire rest of the Line chunk
  # Repeated 16-bit length,string pairs
  def rewrite_file_names_table("", _mapper), do: ""
  def rewrite_file_names_table(<<len::big-16, rest::binary>>, mapper) do
    <<filename::binary-size(len), rest1::binary>> = rest
    new_filename = mapper.(filename)
    [<<byte_size(new_filename)::big-16>>, new_filename, rewrite_file_names_table(rest1, mapper)]
  end

  def rewrite_filenames_in_line_chunk(chunk, mapper) do
    <<0::big-32, _flags::big-32, _num_line_instrs::big-32, num_line_items::big-32, _num_filenames::big-32, rest::binary>> = chunk
    file_names_table = ignore_line_items(rest, num_line_items)

    :erlang.iolist_to_binary([
      # Just copy everything before the filenames table
      binary_part(chunk, 0, byte_size(chunk) - byte_size(file_names_table)),
      rewrite_file_names_table(file_names_table, mapper)
    ])
  end
  
  ################################################################
  ## Literals table
  ## zlib-compressed delimited ETF
  ## See http://beam-wisdoms.clau.se/en/latest/indepth-beam-file.html#litt-literals-table
  def rewrite_literals_table(chunk, mapper) do
    <<uncompressed_size::big-32, compressed_contents::binary>> = chunk
    inflate_context = :zlib.open()
    :zlib.inflateInit(inflate_context)
    inflated = :zlib.inflate(inflate_context, compressed_contents)
    :ok = :zlib.inflateEnd(inflate_context)
    inflated_bin = :erlang.iolist_to_binary(inflated)
    
    <<value_count::big-32, delimited_terms::binary>> = inflated_bin

    {items_acc, total_size} = 
      Enum.reduce(1..value_count, {[], 0}, fn _value_index, {items, base_index} ->
        # Documentation says this 32-bit value is ignored but let's propagate it anyway
        <<_alread_parsed::binary-size(base_index), item_size::big-32, rest::binary>> = delimited_terms
        {term, used} = :erlang.binary_to_term(rest, [:used])
        if item_size != used do
          IO.warn("Bad size? #{item_size} used #{used}")
        end
        {[{term, binary_part(rest, 0, used)} | items], base_index + used + 4}
      end)
    
    # +4 accounts for the 32-bit value count
    if (total_size + 4) != uncompressed_size do
      IO.warn("Incomplete read of literals table -- should have #{uncompressed_size} bytes, got #{total_size+4}")
    end

    # items_acc is backwards, but this reduce will also be backwards,
    # so we will end up with the items in the orignal order
    {new_items_iodata, new_items_size} = 
      Enum.reduce(items_acc, {[], 0}, fn {item, original_bin}, {iodata, size} ->
        #IO.inspect(item, label: "Item")
        new_item = 
          case item do
            # only touch things that we for-sure understand
            %Macro.Env{file: f} ->
              :erlang.term_to_binary(%{item | file: mapper.(f)})
            %{file: f, line: _linum, __struct__: _s, expr: _e, params: _p} when is_binary(f) and map_size(item) == 5 ->
              :erlang.term_to_binary(%{item | file: mapper.(f)})
            %{file: f, line: _linum, mfa: _mfa} when is_list(f) and map_size(item) == 3 -> 
              :erlang.term_to_binary(%{item | file: to_charlist(mapper.(to_string(f)))})
            %{file: f} when is_binary(f) ->
              :erlang.term_to_binary(%{item | file: mapper.(to_string(f))})
            s when is_binary(s) ->
              :erlang.term_to_binary(mapper.(s))
            # Unbelievably, certain values (such as MapSets) do not round-trip through ETF with different VMs
            # I think it is due to atoms' hashes being different when they are loaded in a different order.
            _other -> original_bin
          end
        sz = byte_size(new_item)
        {[[<<sz::big-32>>, new_item] | iodata], size + 4 + sz}
    end)

    new_chunk_iodata = [<<value_count::big-32>>, new_items_iodata]
    new_uncompressed_size = 4 + new_items_size

    deflate_context = :zlib.open()
    :zlib.deflateInit(deflate_context)
    new_compressed_contents = :zlib.deflate(deflate_context, new_chunk_iodata, :finish)
    :ok = :zlib.deflateEnd(deflate_context)
    :erlang.iolist_to_binary([<<new_uncompressed_size::big-32>>, new_compressed_contents])
  end

  def rewrite_functions_table(funt) do
    <<size::32, body::binary>> = funt
    new_funt = rewrite_funt_body(body)
    <<size::32>> <> new_funt
  end
  def rewrite_funt_body(""), do: ""
  def rewrite_funt_body(<<actual_data::binary-size(20), _ouniq::32, rest::binary>>) do
    # <<new_old_uniq::32, _::binary>> = :crypto.hash(:md5, actual_data)
    new_old_uniq = 0
    actual_data <> <<new_old_uniq::32>> <> rewrite_funt_body(rest)
  end

  # For debugging
  def which_chunks_differ?(bin1, bin2) do
    ch1 = chunk_hashes(bin1)
    ch2 = chunk_hashes(bin2)

    for {chunk, {size1, hash1}} <- ch1 do
      {size2, hash2} = ch2[chunk]
      if hash1 != hash2 do
        {chunk, %{a_sha: hash1,
                  b_sha: hash2,
                  a_size: size1,
                  b_size: size2}}
      end
    end
    |> Enum.filter(&(&1))
    |> case do
         [] -> :no_difference
         xs -> {:differences, xs}
       end
  end
  
  def chunk_hashes(beam) do
    {:ok, _mod, tups} = :beam_lib.all_chunks(beam)

    tups
    |> Enum.map(fn {chunk, bin} ->
      {chunk, {byte_size(bin), Base.encode16(:crypto.hash(:sha256, bin))}}
    end)
    |> Map.new
  end

  def chunks_map(bin), do: bin |> :beam_lib.all_chunks |> elem(2) |> Map.new 
  def get_chunk(bin, name), do: chunks_map(bin) |> Map.get(name)

  def read_function_table(ft) do
    <<_size::32, rest::binary>> = ft
    rft(rest, [])
  end
  def rft("", acc), do: Enum.reverse(acc)
  def rft(<<fun_atom_index::32, arity::32, offset::32, index::32, nfree::32, ouniq::32, rest::binary>>, acc) do
    rft(rest, [%{fun_atom_index: fun_atom_index, arity: arity, offset: offset, index: index, nfree: nfree, ouniq: ouniq} | acc])
  end

  # def read_literals_table(chunk) do
  #     <<uncompressed_size::big-32, compressed_contents::binary>> = chunk
  #     inflate_context = :zlib.open()
  #     :zlib.inflateInit(inflate_context)
  #     inflated = :zlib.inflate(inflate_context, compressed_contents)
  #     :ok = :zlib.inflateEnd(inflate_context)
  #     inflated_bin = :erlang.iolist_to_binary(inflated)
      
  #     <<value_count::big-32, delimited_terms::binary>> = inflated_bin

  #     {items_acc, _total_size} = 
  #       Enum.reduce(1..value_count, {[], 0}, fn _value_index, {items, base_index} ->
  #         # Documentation says this 32-bit value is ignored but let's propagate it anyway
  #         <<_alread_parsed::binary-size(base_index), item_size::big-32, rest::binary>> = delimited_terms
  #         {term, used} = :erlang.binary_to_term(rest, [:used])
  #         if item_size != used do
  #           IO.warn("Bad size? #{item_size} used #{used}")
  #         end
  #         {[{term, binary_part(rest, 0, used)} | items], base_index + used + 4}
  #       end)
  #     for {item, _bin} <- Enum.reverse(items_acc), do: item
  # end

end
