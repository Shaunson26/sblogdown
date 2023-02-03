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




