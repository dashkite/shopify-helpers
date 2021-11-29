import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Shopify from "../shopify"

class Shop

  @from: (store, data) ->
    Object.assign new Shop,
      store: store
      _: data    

  @get: (store) ->
    self = Object.assign new Shop, 
      { store }

    self.get()

  @getPrimaryLocationID: (store) ->
    shop = await @get store
    shop.primaryLocationID

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      primaryLocationID: -> @_.primary_location_id
  ]

  get: ->
    @_ = Obj.get "shop",
      await Shopify.get @store, 
        "/shop.json"
    @


        
export {
  Shop
}
