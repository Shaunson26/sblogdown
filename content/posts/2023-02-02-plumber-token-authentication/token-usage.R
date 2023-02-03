rp <- callr::r_bg(function(){ plumber::pr_run(plumber::pr('plumber.R'), port = 8999)})
rp$kill()
rp$is_alive()
cat(rp$read_error())
cat(rp$read_output())
rp$get_wd()

library(httr2)

requrl <- httr2::request('http://127.0.0.1:8999')

my_token <-
  requrl %>% 
  req_url_path_append('refresh-token') %>% 
  req_body_json(
    list(user = 'jbrown',
         password = '1234')
  ) %>% 
  req_perform() %>% 
  resp_header('set-cookie') %>% 
  sub('token=', '', .)

requrl %>% 
  req_url_path_append('need-token') %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  resp_body_json() %>% 
  print()

requrl %>% 
  req_url_path_append('need-token') %>% 
  req_headers(token = my_token) %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  resp_body_json() %>% 
  print()
