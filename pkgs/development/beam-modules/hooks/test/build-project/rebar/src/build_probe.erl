-module(build_probe).
-export([message/0]).
-include("message.hrl").

message() -> ?MESSAGE.
