use Mix.Config

config :app_two,
  env_dependent: "MIX_ENV is TEST",
  action_provider: MockAction
