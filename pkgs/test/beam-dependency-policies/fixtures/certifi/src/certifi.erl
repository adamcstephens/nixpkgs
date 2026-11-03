-module(certifi).
-export([cacertfile/0]).

cacertfile() -> filename:join(code:priv_dir(certifi), "cacerts.pem").
