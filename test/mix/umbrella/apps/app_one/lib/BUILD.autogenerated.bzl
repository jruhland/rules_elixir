load("@rules_elixir//impl:autogenerated_helpers.bzl", "elixir_libraries")

def autogenerated_targets(overrides = {}):
  attrs = {
    "app_one": {
                 "name": "app_one",
                 "srcs": ["app_one.ex"],
                 "compile_deps": [":macros", "//test/mix/umbrella:config",
                                  "//test/mix/umbrella:third_party"],
                 "visibility": ["//visibility:public"]
               },
    "macros": {
                "name": "macros",
                "srcs": ["macros.ex"],
                "compile_deps": [],
                "exported_deps": ["//test/mix/umbrella/apps/common/lib:compiletime_util"],
                "visibility": ["//visibility:public"]
              }
  }
  elixir_libraries(attrs, overrides)

