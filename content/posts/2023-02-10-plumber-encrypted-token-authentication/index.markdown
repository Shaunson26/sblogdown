---
title: Plumber encrypted token authentication
author: Shaun Nielsen
date: '2023-02-10'
slug: []
categories: ['HTTP-API',]
tags: ['Plumber', 'callr', 'Encrypted cookie']
weight: 50
show_comments: yes
katex: no
draft: no
---

I'm continuing investigating the `plumber` R package. I explored  
[setting cookies in plumber](https://www.rplumber.io/articles/rendering-output.html?#setting-cookies),
and attempted to decipher the encrypted cookie use. After some time I reached an endpoint (pun intended!).
This post follows on (and resembles a lot) a [previous post on tokens with plumber](../2023-02-02-plumber-token-authentication). 

<!--more-->

## Background

[plumber documentation](https://www.rplumber.io/articles/rendering-output.html?#setting-cookies)
describes the ability to use cookies, both plain-text and encrypted. I wanted to 
try their encrypted cookies function to see how it works.

It requires explicitly adding a cookie function to the router after constructing it. 

```
pr %>%
  pr_cookie("mySecretHere", "cookieName")
```

I could not quite understand the follow text in the documentation, but I believe it makes
the object `req$session` available on incoming requests and then encrypts any data you
allocate to it, or at least any further objects you add to it. 

Let's see it in action

## The logic

1. A plumber HTTP API is up and running ('the API')
2. Users can request a token by POSTing credentials. The API validates the credentials using
a local DB*. If valid, it creates a token by encrypting a given value using `pr_cookie()`/`session_cookie()`,
and which is returned as a cookie in the response.
  - the value can be anything, even a complex object. **Here we pass it an expiry time value.**
  - the value is encrypted when it arrives to the client, and decrypted when the client passes it
  back to the server
3. When another request is made it must include the cookie header 'token' with the token value
4. The API checks the request for a cookie 'token', 
5. If the token is found, it will be **decrypted back to the time value** for which we can run it 
through a predicate function (if/else)
6. Where any of the validation steps fail, a response is sent with various 400 status codes. 

* Having a DB means this thing is not stateless ..

> This logic is different to my previous post, as we no longer need to store the token or it's expiry time
in a DB

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

`encrypted-cookie-api.R`

Note the use of a cryptological key.


```r
library(plumber)

#* @apiTitle Plumber Example API using encrypted cookies
#* @apiDescription A filter and endpoints for using encrypted cookies

# This is the key for encryption in the example
# IMPORTANT - You would generally keep a stored key in a keyring, e.g
#   keyring::key_set_with_value("plumber_api", plumber::random_cookie_key())
#   key <- keyring::key_get("plumber_api")
key <- plumber::random_cookie_key()

# Programmatically alter your API
#* @plumber
function(pr) {
  pr %>%
    # Overwrite the default serializer to return unboxed JSON
    pr_set_serializer(serializer_unboxed_json()) %>%
    # Add the encrypted cookie function, cookie called "token", encrypted with key valye
    pr_cookie(key, "token")
}

#* @filter token_check
#*
#* Check that a token is provided and is valid for carrying out request. This
#* filter is run for every request unless a `@preempt token_check` is used.
#*
#* @param req,res plumber request and response objects
function(req, res) {

  if (is.null(req$session$token)){
    res$status <- 401
    return(list(error = 'token cookie not found in request header'))
  }

  if (Sys.time() > req$session$token){
    res$status <- 401
    return(list(error = 'token expired, please refresh'))
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

  any_missing_credentials <-
    is.null(req$body$user) && is.null(req$body$password)

  if (any_missing_credentials){
    res$status <- 400
    return(list(error = 'user and/or password not included in request body'))
  }

  users <- RSQLite::dbConnect(RSQLite::SQLite(), "users.sql")

  req_user <- req$body$user

  user_row <-
    dplyr::tbl(users, 'users') %>%
    dplyr::filter(user == req_user) %>%
    dplyr::collect()

  if (nrow(user_row) == 0){
    res$status <- 401
    return(list(error = 'credentials incorrect (dev - user not found)'))
  }

  password_incorrect <- req$body$password != user_row$password

  if (password_incorrect){
    res$status <- 401
    return(list(error = 'credentials incorrect (dev -password incorrect)'))
  }

  req$session$token <- Sys.time() + 10

  return(list(token_expiry = req$session$token))

}

#* Do something
#*
#* Do something. This function include the `token_check` filter.
#*
#* @get /do-something
function() {
  return('Congratulations, you passed the test!')
}
```

### Testing

I used `callr` to create a background process with the API running


```r
rp <- 
  callr::r_bg(function(){ 
    plumber::pr_run(plumber::pr('encrypted-cookie-api.R'), port = 8989)
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

The endpoint `/do-something` will be reached after the request goes through the
`token_check` filter. Here, no token is provided. Note that if an error is sent
by the server to the client, `httr2` will by default throw an R error and we do not
want that here hence the `req_error()` line - we would otherwise not be able to see
what the error message sent was.


```r
# The response
resp_no_token <-
  requrl %>% 
  req_url_path_append('do-something') %>% 
  req_error(is_error = function(res) FALSE) %>% 
  req_perform() %>% 
  print()
```

```
## <httr2_response>
```

```
## GET http://127.0.0.1:8989/do-something
```

```
## Status: 401 Unauthorized
```

```
## Content-Type: application/json
```

```
## Body: In memory (52 bytes)
```

```r
# The response message
resp_no_token %>% 
  resp_body_json() %>% 
  print()
```

```
## $error
## [1] "token cookie not found in request header"
```

Thus a user needs to submit their credentials to the end point `/refresh-token` to 
receive a (time-limited) token. Remember this endpoint does not go through the `token_check` filter
due to the `@preempt` directive used. We then extract the value of the cookie in the header.
You must be careful if there are multiple cookies received - here there is only one.


```r
token_resp <-
  requrl %>% 
  req_url_path_append('refresh-token') %>% 
  req_body_json(
    list(user = 'jbrown',
         password = '1234')
  ) %>% 
  req_perform() %>% 
  print()
```

```
## <httr2_response>
```

```
## POST http://127.0.0.1:8989/refresh-token
```

```
## Status: 200 OK
```

```
## Content-Type: application/json
```

```
## Body: In memory (38 bytes)
```


```r
token_resp_headers <-
  token_resp %>% 
  resp_headers('set-cookie')

token_resp_headers
```

```
## <httr2_headers>
```

```
## Set-Cookie: token=VysIOK2s0sppD3efG7jZXAtZ2gn%2BPL1fMq%2BqftuGu0Qr76BcPitCJtIEa3PkrT%2BMyA%3D%3D_QdYp2RPLjW45RCwMEgwcr9D4y04MrhuY; HttpOnly
```

```r
token <- sub(';.*', '', token_resp_headers[[1]])
token
```

```
## [1] "token=VysIOK2s0sppD3efG7jZXAtZ2gn%2BPL1fMq%2BqftuGu0Qr76BcPitCJtIEa3PkrT%2BMyA%3D%3D_QdYp2RPLjW45RCwMEgwcr9D4y04MrhuY"
```

And then include it in future requests


```r
resp_with_token <-
  requrl %>% 
  req_url_path_append('do-something') %>%
  req_error(is_error = function(res) FALSE) %>% 
  req_headers(cookie = token) %>% 
  req_perform()

resp_with_token %>% 
  resp_body_json() %>% 
  print()
```

```
## [1] "Congratulations, you passed the test!"
```

Since the token is time-limited (10 seconds here), what if we wait 12 seconds and try again?


```r
Sys.sleep(12)
```


```r
resp_with_token <-
  requrl %>% 
  req_url_path_append('do-something') %>%
  req_error(is_error = function(res) FALSE) %>% 
  req_headers(cookie = token) %>% 
  req_perform()

resp_with_token %>% 
  resp_body_json() %>% 
  print()
```

```
## $error
## [1] "token expired, please refresh"
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

Here we explored using encrypted cookies with `plumber`. We learned how to set
a new encrypted cookie with a value (a time stamp), and how it encrypted on it's way 
to the client and how plumber will decrypt it when it is returned.

We improved on my  [previous post](../2023-02-02-plumber-token-authentication) by not 
needing to store the token or the expiry time in a database.



