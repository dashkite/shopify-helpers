except = (properties, object) ->
  result = {}
  for key, value of object when !( key in properties )
    result[ key ] = object[ key ]
  result

meta = (name, value) ->
  namespace: "dashkite"
  key: name
  type: "single_line_text_field"
  value: JSON.stringify value

export {
  except
  meta
}