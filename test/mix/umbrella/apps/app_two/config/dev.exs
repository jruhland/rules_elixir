use Mix.Config

config :app_two,
  env_dependent: "MIX_ENV is dev",
  action_provider: RealAction
