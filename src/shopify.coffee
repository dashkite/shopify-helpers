import fetch from "node-fetch"

import {
  getSecret
} from "@dashkite/dolores/secrets"

import * as Arr from "@dashkite/joy/array"
import * as Text from "@dashkite/joy/text"

createError = (response) ->
  details = await response.text()
  error = new Error "#{response.status}: #{response.statusText}.\n#{details}"
  error.response = response
  error.details = details
  error

getBase = (subdomain) -> "https://#{subdomain}.myshopify.com/admin/api/2021-10"

request = (method) ->
  ({key, subdomain, token}, target, body) ->
    do ({ headers, options, response } = {}) ->
      headers =
        "x-shopify-access-token": await getSecret token
      options =
        method: method
        headers: headers
      if body?
        headers[ "content-type" ] = "application/json"
        options.body = JSON.stringify body    
      response = await fetch "#{getBase subdomain}#{target}", options
      try
        if 200 <= response.status < 300
          body = await response.text()
          JSON.parse body
        else
          throw await createError response
      catch error
        throw error

get = request "get"
put = request "put"
del = request "delete"
post = request "post"

export {
  get
  put
  del
  post
}