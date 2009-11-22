-define (JSON_ENCODE(V), mochijson2:encode(V)).
-define (BINIFY (PropList),
  lists:map(fun({K, V}) ->
    {K, misc_utils:to_bin(V)}
  end, PropList)).
-define (JSONIFY (V), ?JSON_ENCODE(V)).

% Base page
-define (HOME_HTML, "<html>
  <head><title>Beehive</title></head>
  <body>
    <h1>Beehive homepage.</h1>
  </body></html>").

-define (CONTENT_HTML (Cont), io_lib:format("<html>
  <head><title>Beehive</title></head>
  <body id='beehive'>
    <div class='content'>
      <h1>Beehive</h1>
      <p>~s</p>
    </div>
  </body></html>", [Cont])).

-define (APP_ERROR (Msg), io_lib:format("<html>
  <head><title>Uh oh! We made a boo boo</title></head>
  <body>
    <h1>Beehive Error</h1>
    <p>~s</p>
  </body></html>", [Msg])).


% Error page
-define (ERROR_HTML (App), io_lib:format("HTTP/1.1 200 Internal Server Error\r\n\r\n<html>
  <head><title>Error - ~s Not found</title></head>
  <body>
    <h1>Beehive Error | The site you have requested was not found.</h1>
    <p>Check the url again to make sure you typed it correctly</p>
  </body></html>", [App])).
