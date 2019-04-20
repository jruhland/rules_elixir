File.cd!(System.get_env("BUILD_WORKING_DIRECTORY"))
Application.ensure_all_started(:mix)
Code.compile_file("mix.exs")



