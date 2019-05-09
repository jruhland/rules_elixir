load("@rules_elixir//impl:defs.bzl", "elixir_library", "elixir_script", "mix_project")

def _modified_value(value, options):
    if value != None and type(value) != "list":
        return value

    removed = options.get("remove", [])
    return options.get("add", []) + [v for v in (value or []) if v not in removed]

def _modified_attrs(attrs, overrides):
    updates = [
        (attr_name, _modified_value(attrs.get(attr_name), options))
        for attr_name, options in overrides.items()
    ]

    # argument to `update` does not need to be a dict in newer bazel...
    attrs.update(dict(updates))
    return attrs

def _do_overrides(all_attrs, overrides):
    for k in overrides.keys():
        if k not in all_attrs:
            fail("attempting to override attrs of generated target \"{}\", which does not exist".format(k))

    return [
        (name, _modified_attrs(attrs, overrides.get(name, {})))
        for name, attrs in all_attrs.items()
    ]

def elixir_libraries(all_attrs, overrides):
    for name, attrs in _do_overrides(all_attrs, overrides):
        elixir_library(**attrs)

