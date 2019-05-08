load("@rules_elixir//impl:defs.bzl", "elixir_library", "elixir_script", "mix_project")

def _modified_value(value, options):
    if type(value) != "list":
        return value
    
    removed = options.get("remove", [])
    return options.get("add", []) + [v for v in value if v not in removed]

def do_overrides(all_attrs, overrides):
    return [
        (name, 
         dict([
             (attr_name, _modified_value(original_value, overrides.get(name, {}).get(attr_name, {})))
             for attr_name, original_value in attrs.items()
         ])
        )
        for name, attrs in all_attrs.items()
    ]


def elixir_libraries(all_attrs, overrides):
    for name, attrs in do_overrides(all_attrs, overrides):
        elixir_library(**attrs)

