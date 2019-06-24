# collect everything that we define into one file for ease of use
load("//impl:elixir_rules.bzl",
     _elixir_library="elixir_library",
     _elixir_script="elixir_script",
     _elixir_test="elixir_test",
)
load("//impl:mix_rules.bzl",
     _mix_project="mix_project"
)

elixir_library = _elixir_library
elixir_script  = _elixir_script
elixir_test    = _elixir_test

mix_project = _mix_project
