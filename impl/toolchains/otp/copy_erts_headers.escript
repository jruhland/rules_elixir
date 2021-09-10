#!/usr/bin/env escript
%% Copy the erts C include header files from the running ERTS and place them in the current directory under a path such as `erts-10.4.4/include`
main([OutputBaseDir]) -> 
    ErtsIncludePath = filename:join("erts-" ++ erlang:system_info(version), "include"),
    IncludeDir = filename:join(code:root_dir(), ErtsIncludePath),
    {ok, Ls} = file:list_dir(IncludeDir),
    OutputDir = filename:join(OutputBaseDir, ErtsIncludePath),
    filelib:ensure_dir(OutputDir ++ "/"),
    lists:foreach(fun(H) -> io:put_chars([H, "\n"]), file:copy(filename:join(IncludeDir, H), filename:join(OutputDir, H)) end, Ls).
