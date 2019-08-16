use Mix.Config

config :app_two,
  two: 2,
  string: "hello"

import_config "#{Mix.env}.exs"
