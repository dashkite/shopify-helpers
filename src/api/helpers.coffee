meta = (name, value) ->
  namespace: "dashkite"
  key: name
  type: "single_line_text_field"
  value: JSON.stringify value

export {
  meta
}