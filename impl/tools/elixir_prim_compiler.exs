# Primitive elixir compiler driver.  Has to be a script becuase who would compile us?
# Used to compile simple elixir_library targets such as used in the other tools

{opts, files_to_compile} = OptionParser.parse!(System.argv(), strict: [output_base_dir: :string, loadpath: :keep])

for {:loadpath, entry} <- opts do
    Code.prepend_path(entry)
end

output_base_dir = opts[:output_base_dir]
File.mkdir_p!(output_base_dir)

{:ok, agent} = Agent.start_link(fn -> [] end)

{:ok, _mods, _infos} = Kernel.ParallelCompiler.compile_to_path(
  files_to_compile,
  output_base_dir,
  each_module: fn _source_file, mod, bin ->
    beamfile = "#{output_base_dir}/#{mod}.beam"
    Agent.update(agent, fn vs -> [{beamfile, bin} | vs] end)
  end
)

RulesElixir.Tools.BeamStripper.start_link()
for {beamfile, bin} <- Agent.get(agent, fn x -> x end) do
    File.write!(beamfile, RulesElixir.Tools.BeamStripper.debazelify_bin(bin))
end
