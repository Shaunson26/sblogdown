---
title: Plumber token authentication
author: Shaun Nielsen
date: '2023-02-02'
slug: []
categories: ['HTTP API']
tags: ['plumber', 'callr']
weight: 50
show_comments: yes
katex: no
draft: no
---

I'm working on a project that involves using a server to take in user data to
run a bioinformatics pipeline with R and blast+. I am using plumber as the 
HTTP API to receive the user data and send data to background R processes. To
add a layer of (clandestine) security, I tried making a token authentication
system.

<!--more-->

## Background

I have worked with HTTP APIs many times before - from free to highly secure. One
involved POSTing user credentials + a key in order to receive a time-expiring token
for downstream use. I had a go at creating something similar using plumber.

Now, there is this thing called a RESTful API (google it!) which is a set of architectural constraints.
Ideally we want our API to follow these constraints. This following API voids the stateless criteria,
as we keep a DB of information. But that is ok here.

## The logic

1. A plumber HTTP API is up and running ('the API')
2. Users can request a token by POSTing credentials. The API validates the credentials using
a local DB*. If valid, it creates a token (a value of 24 random "0:9, letter, LETTERS") and token_expiry 
time (time + X time, here 10 seconds). It updates the DB with token and token_expiry of the user,
then returns a response with the header 'token' and token value.
- the DB contains user credentials, tokens and token expiry times
3. Another request is made .. it must include the header 'token' with the token value
4. The API checks the request for a header 'token', and if present, compares it to the DB
5. If the token is found, the expiry time is checked, and if valid, the user request is carried out
6. Where any of the validation steps fail, a response is sent with various 400 status codes. 

* Having a DB means this thing is not stateless .. there are other token options, but more exploratory time is required by myself.

## The setup

The API itself required `plumber`, `dplyr` and `RSQLite`. I used `dplyr` as it simplified some
SQL code (which could otherwise be properly written as SQL statements). For development, I used `httr2` for interacting with the API and `callr` to run the API within the same RStudio session.

### User DB

A simple local SQL DB.


```r
users <- RSQLite::dbConnect(RSQLite::SQLite(), "users.sql")

users_values <-
  tibble::tribble(
    ~name, ~user, ~password, ~token, ~token_expiry,
    'John','jbrown','1234','','',
    'Sally','sblue', '4321','',''
  )

RSQLite::dbWriteTable(users, name = 'users', value = users_values)
RSQLite::dbDisconnect(users)
```

### Plumber script


```r
library(plumber)
suppressPackageStartupMessages(library(dplyr))
library(RSQLite)

#* @apiTitle Plumber Example API for token authentication
#* @apiDescription A simple example of creating and verifying a token. It uses
#* a local DB, plumber filters, and returns user data if token verified.

#* API setup
#*
#* Change default serializer
#*
#* @plumber
function(pr){
  pr %>%
    pr_set_serializer(serializer_unboxed_json())
}

#* @filter token_check
#*
#* Check that a token is provided and is valid for carrying out request. This
#* filter is run for every request unless a `@preempt token_check` is used.
#*
#* @param req,res plumber request and response objects
function(req, res) {

  if (is.null(req$HTTP_TOKEN)){
    res$status <- 401
    return(list(error = 'token not found in request header'))
  }

  users <- RSQLite::dbConnect(RSQLite::SQLite(), "users.sql")

  req_token = req$HTTP_TOKEN

  token_row <-
    dplyr::tbl(users, 'users') %>%
    dplyr::filter(token == req_token) %>%
    dplyr::collect()

  if (nrow(token_row) == 0){
    res$status <- 401
    return(list(error = 'token not allocated to user'))
  }

  token_expired <- as.numeric(token_row$token_expiry) - as.numeric(Sys.time()) < 0

  if (is.na(token_expired) || token_expired) {
    res$status <- 401
    return(list(error = 'token expired, please refesh token'))
  }

  plumber::forward()

}

#* Refresh user token
#*
#* Return token in HTTP header 'token'. This function excludes the `token_check`
#* filter.
#*
#* @param req,res plumber request and response objects
#*
#* Expects a request body with `user` and `password`
#*
#* @preempt token_check
#* @post /refresh-token
function(req, res) {

  any_missing_credentials <- any( is.null(req$body$user) | is.null(req$body$password) )

  if (any_missing_credentials){
    res$status <- 400
    return(list(error = 'user or password not included in request body'))
  }

  users <- RSQLite::dbConnect(RSQLite::SQLite(), "users.sql")

  req_user <- req$body$user

  user_row <-
    dplyr::tbl(users, 'users') %>%
    dplyr::filter(user == req_user) %>%
    dplyr::collect()

  if (nrow(user_row) == 0){
    res$status <- 401
    return(list(error = 'user not found'))
  }

  password_incorrect <- req$body$password != user_row$password

  if (password_incorrect){
    res$status <- 401
    return(list(error = 'password incorrect'))
  }

  token <- paste(sample(c(0:9, letters, LETTERS), size = 24, replace = TRUE), collapse = '')

  # A 10 second expiry time
  token_expiry <- Sys.time() + 10

  RSQLite::dbExecute(users, "UPDATE users SET token = ?, token_expiry = ? where user = ? and password = ?",
                     params = c(token, token_expiry, user_row$user, user_row$password))

  RSQLite::dbDisconnect(users)

  res$setHeader('token', token)

}

#* A simple function to return user data in DB
#*
#* This endpoint will only be reached if a user supplies a valid token
#*
#* @param req,res plumber request and response objects
#*
#* @get /return-data
function(req, res) {

  users <- RSQLite::dbConnect(RSQLite::SQLite(), "users.sql")

  req_token = req$HTTP_TOKEN

  token_row <-
    dplyr::tbl(users, 'users') %>%
    dplyr::filter(token == req_token) %>%
    dplyr::collect()

  if (nrow(token_row) == 0){
    res$status <- 500
    return(list(error = 'token not allocated to user'))
  }

  return(as.list(token_row))
}
```

### Testing

I used `callr` to create a background process with the API running


```r
rp <- 
  callr::r_bg(function(){ 
    plumber::pr_run(plumber::pr('token-plumber-api.R'), port = 8989)
  })
```




```r
rp$is_alive()
```

```
## [1] TRUE
```

```r
cat(rp$read_error())
```

```
## Running plumber API at http://127.0.0.1:8989
## Running swagger Docs at http://127.0.0.1:8989/__docs__/
```

Then query the API using `httr2`


```r
library(httr2)

requrl <- httr2::request('http://127.0.0.1:8989')
```

The endpoint `/return-data` will be reached after the request goes through the
`token_check` filter. Here, no token is provided. Note that if an error is sent
by the server to the client, `httr2` will by default throw an R error and we do not
want that here hence the `req_error` line - we would otherwise not be able to see
what the error message sent was.


```r
# The response
resp_no_token <-
  requrl %>% 
  req_url_path_append('return-data') %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  print()
```

```
## <httr2_response>
```

```
## GET http://127.0.0.1:8989/return-data
```

```
## Status: 401 Unauthorized
```

```
## Content-Type: application/json
```

```
## Body: In memory (45 bytes)
```

```r
# The response message
resp_no_token %>% 
  resp_body_json() %>% 
  print()
```

```
## $error
## [1] "token not found in request header"
```

Thus a user needs to submit their credentials to the end point `/refresh-token` to receive a (time-limited) token. Remember this endpoint does not go through the `token_check` filter
due to the `@preempt` directive used. We then extract the value of the header `token`


```r
token <-
  requrl %>% 
  req_url_path_append('refresh-token') %>% 
  req_body_json(
    list(user = 'jbrown',
         password = '1234')
  ) %>% 
  req_perform() %>% 
  resp_header('token') %>% 
  print()
```

```
## [1] "4khDfzrRf0DyS96vwF6CyoWN"
```

And then include it in future requests


```r
resp_with_token <-
  requrl %>% 
  req_url_path_append('return-data') %>% 
  req_headers(token = token) %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  print()
```

```
## <httr2_response>
```

```
## GET http://127.0.0.1:8989/return-data
```

```
## Status: 200 OK
```

```
## Content-Type: application/json
```

```
## Body: In memory (118 bytes)
```

```r
resp_with_token %>% 
  resp_body_json() %>% 
  print()
```

```
## $name
## [1] "John"
## 
## $user
## [1] "jbrown"
## 
## $password
## [1] "1234"
## 
## $token
## [1] "4khDfzrRf0DyS96vwF6CyoWN"
## 
## $token_expiry
## [1] "1675421529.13027"
```

Since the token is time-limited (10 seconds here), what if we wait 12 seconds and try again?


```r
Sys.sleep(12)
```


```r
resp_with_token <-
  requrl %>% 
  req_url_path_append('return-data') %>% 
  req_headers(token = token) %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  print()
```

```
## <httr2_response>
```

```
## GET http://127.0.0.1:8989/return-data
```

```
## Status: 401 Unauthorized
```

```
## Content-Type: application/json
```

```
## Body: In memory (46 bytes)
```

```r
resp_with_token %>% 
  resp_body_json() %>% 
  print()
```

```
## $error
## [1] "token expired, please refesh token"
```

A call to `/refresh-token` is required to move forward ...

Kill background R process (the API)


```r
rp$kill()
```

```
## [1] TRUE
```

## Conclusion

Here we explored a HTTP API using plumber and attempted to create an authentication
system. It involved using API filters and endpoints, sending and receiving HTTP headers,
sending HTTP response codes, and using a local SQL database for credential storage. 

Obviously there are better ways to handle security (type of token, 
where does token go - in cookies?, encrypted cookies), or do what we did above is a better way (ensure
credential DB is more secure - set permissions on the server) but we have a simple working API with a security layer happening.




