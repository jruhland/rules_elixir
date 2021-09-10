elixir_versions = [
    "1.8.1",
    "1.8.2",
    "1.9.0",
    "1.9.1",
    "1.9.2",
    "1.9.3",
    "1.9.4",
    "1.10.0",
    "1.10.1",
    "1.10.2",
    "1.10.3",
    "1.10.4",
    "1.11.0",
    "1.11.1",
    "1.11.2",
    "1.11.3",
    "local",
]

def define_constraint():
    native.constraint_setting(
        name = "version",
        default_constraint_value = "1.8.1",
    )

    for v in elixir_versions:
        native.constraint_value(
            constraint_setting = ":version",
            name = v,
        )
