import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Shopify from "../shopify"

class Webhook

  @create = (store, description) -> 
    Object.assign new Webhook,
      store: store
      deleted: false
      _: Obj.get "webhook",
        await Shopify.post store, "/webhooks.json", webhook: description

  @list: (store) ->
    webhooks = Obj.get "webhooks", await Shopify.get store, "/webhooks.json?limit=250"
    for webhook in webhooks
      Object.assign new Webhook,
        store: store
        _: webhook

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      topic: -> @_.topic
      url: -> @_.address
  ]
  delete: ->
    await Shopify.del @store, "/webhooks/#{@_.id}.json"
    @deleted = true
    @

export {
  Webhook
}
