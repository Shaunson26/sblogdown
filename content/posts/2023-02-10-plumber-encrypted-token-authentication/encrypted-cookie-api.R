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


