import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import { getStore } from "../stores"
import * as Shopify from "../shopify"
import { meta } from "./helpers"
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

  @list: (store) ->
    { orders } = await Shopify.get store, "/orders.json?status=any&limit=250"
    for order in orders
      Object.assign new Order,
        store: store
        _: order

  @get: (store, id) ->
    self = Object.assign new Order, { store, _: { id } }
    self.get()

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      lineItems: -> @_.line_items
      fulfillments: -> @_.fulfillments
  ]

  get: ->
    @_ = Obj.get "order",
      await Shopify.get @store, "/orders/#{@id}.json"
    @

  put: ->
    @_ = Obj.get "order", await Shopify.put @store, "/orders/#{@_.id}.json", { order: @_ }
    @

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

    orders

  close: -> Shopify.post @store, "/orders/#{@id}/close.json"

  getFulfillmentFromTrackingNumber: (trackingNumber) ->
    for fulfillment in @fulfillments when fulfillment.tracking_number == trackingNumber
      return fulfillment
    # When we fail to match...
    undefined

  fulfill: ->
    source = await @mget "source"
    if !source?
      # This supplier order is not one associated with DashKite.
      return

    { vendor, id } = source
    resellerStore = getStore vendor
    resellerOrder = await Order.get resellerStore, id
    for fulfillment in @fulfillments
      _fulfillment = resellerOrder.getFulfillmentFromTrackingNumber fulfillment.tracking_number 
      if !_fulfillment?
        resellerOrder.fulfillments.push 
          status: fulfillment.status
          tracking_company: fulfillment.tracking_company
          tracking_number: fulfillment.tracking_number
          order_id: resellerOrder.id
      else
        _fulfillment.status = fulfillment.status
        _fulfillment.tracking_company = fulfillment.tracking_company
        _fulfillment.tracking_number = fulfillment.tracking_number

      await resellerOrder.put()

  delete: ->
    await Shopify.del @store, "/orders/#{@id}.json"
    @deleted = true
    @


        
export {
  Order
}
