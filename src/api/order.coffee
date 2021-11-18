import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import { getStore } from "../stores"
import * as Shopify from "../shopify"
import { except, meta } from "./helpers"
import { ProductVariant } from "./product"

class Order

  @from: (store, data) ->
    Object.assign new Order,
      store: store
      _: data

  @create: (store, { items } ) ->
    Object.assign new Order,
      store: store
      _: Obj.get "order",
        await Shopify.post store, "/orders.json",
          order:
            line_items: do ->
              for { variant, quantity } in items
                { variant_id: variant._.id, price: variant._.price, quantity }

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      lineItems: -> @_.line_items
  ]

  mget: (name) ->
    { metafields } = await Shopify.get @store,
      "/orders/#{@_.id}/metafields.json"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return JSON.parse field.value
    # if not found...
    undefined

  mset: (name, value) ->
    Shopify.post @store, "/orders/#{@_.id}/metafields.json",
      metafield: meta name, value

  forward: ->
    orders = {}
    for { variant_id, quantity, price } in @lineItems
      resellerVariant = await ProductVariant.get @store, variant_id
      source = await resellerVariant.mget "source"
      if source?
        store = await getStore source.vendor
        supplierVariant = await ProductVariant.get store, source.id
        orders[ store.name ] ?= { store, items: [] }
        orders[ store.name ].items.push
          variant: supplierVariant
          quantity: quantity
    orders = await do =>
      for storeName, { store, items } of orders
        order = await Order.create store, { items }
        await order.mset "source",
          vendor: @store.name
          id: @id
        order
    await @close()
    orders

  close: -> Shopify.post @store, "/orders/450789469/close.json"
  
  fulfill: ->
    source = await @mget "source"
    store = await getStore source.vendor
    resellerOrder = await Order.get store, source.id
    for resellerItem in resellerOrder.lineItems
      resellerVariant = await ProductVariant.get store, resellerItem.variant_id
      source = await resellerVariant.mget "source"
      for supplierItem in @lineItems when item.variant_id == source.id
        # TODO how do we update?
        # resellerItem.tracking = supplierItem.tracking
        undefined
    resellerOrder.put() 


        
export {
  Order
}
