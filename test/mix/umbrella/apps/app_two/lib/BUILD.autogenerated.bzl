load("@rules_elixir//impl:autogenerated_helpers.bzl", "elixir_libraries")

def autogenerated_targets(overrides = {}):
  attrs = {
    "app_two": {
                 "name": "app_two",
                 "srcs": ["app_two.ex"],
                 "compile_deps": ["//test/mix/umbrella:config"],
                 "visibility": ["//visibility:public"]
               },
    "mock_action": {
                     "name": "mock_action",
                     "srcs": ["mock_action.ex"],
                     "compile_deps": [],
                     "visibility": ["//visibility:public"]
                   },
    "real_action": {
                     "name": "real_action",
                     "srcs": ["real_action.ex"],
                     "compile_deps": [],
                     "visibility": ["//visibility:public"]
                   },
    "some_module": {
                     "name": "some_module",
                     "srcs": ["some_module.ex"],
                     "compile_deps": [],
                     "visibility": ["//visibility:public"]
                   }
  }
  elixir_libraries(attrs, overrides)

